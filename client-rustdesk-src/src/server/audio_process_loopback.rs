// Capture the system audio of this machine while excluding whatever this process
// (and its children) plays.
//
// The plain output loopback captures "everything the speakers are playing", which
// includes the remote operator's voice once we start playing it here. That copy
// travels straight back to the operator as echo. Excluding our own process tree
// removes the echo by construction: the voice is heard locally but never captured.
//
// Requires Windows 10 2004 (build 19041) or newer. Callers must fall back to the
// regular output loopback when `start` returns an error.

use std::{
    ptr,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread::JoinHandle,
};

use hbb_common::{bail, log, ResultType};
use windows::{
    core::{implement, Interface, Ref, Result as WinResult},
    Win32::{
        Foundation::{CloseHandle, HANDLE, WAIT_OBJECT_0},
        Media::Audio::{
            ActivateAudioInterfaceAsync, IActivateAudioInterfaceAsyncOperation,
            IActivateAudioInterfaceCompletionHandler, IActivateAudioInterfaceCompletionHandler_Impl,
            IAudioCaptureClient, IAudioClient, AUDCLNT_BUFFERFLAGS_SILENT,
            AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
            AUDCLNT_STREAMFLAGS_LOOPBACK, AUDIOCLIENT_ACTIVATION_PARAMS,
            AUDIOCLIENT_ACTIVATION_PARAMS_0, AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
            AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS, PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE,
            VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, WAVEFORMATEX,
        },
        System::{
            Com::{
                CoInitializeEx, CoUninitialize, StructuredStorage::PROPVARIANT, BLOB,
                COINIT_MULTITHREADED,
            },
            Threading::{CreateEventW, SetEvent, WaitForSingleObject},
            Variant::VT_BLOB,
        },
    },
};

/// The format we ask the virtual loopback device for. It converts on our behalf,
/// so we pick what the encoder wants instead of adapting to a device format.
pub const SAMPLE_RATE: u32 = 48000;
pub const CHANNELS: u16 = 2;

const WAVE_FORMAT_IEEE_FLOAT: u16 = 3;
/// Buffer duration in 100-nanosecond units (20 ms).
const BUFFER_DURATION: i64 = 200_000;
/// How long to block on the "samples ready" event before re-checking the stop flag.
const WAIT_TIMEOUT_MS: u32 = 200;
/// How long to wait for the asynchronous activation of the virtual device.
const ACTIVATION_TIMEOUT_MS: u32 = 2000;

/// A running capture. Dropping it stops the capture thread and joins it.
pub struct Capture {
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl Drop for Capture {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            // The capture thread wakes at least every WAIT_TIMEOUT_MS, so this is bounded.
            if thread.join().is_err() {
                log::error!("process loopback capture thread panicked");
            }
        }
    }
}

/// Owns an event handle and closes it on drop, so early returns cannot leak it.
struct Event(HANDLE);

impl Event {
    fn new() -> ResultType<Self> {
        // Auto-reset, initially unsignalled.
        match unsafe { CreateEventW(None, false, false, None) } {
            Ok(handle) => Ok(Self(handle)),
            Err(err) => bail!("failed to create audio event: {}", err),
        }
    }

    fn handle(&self) -> HANDLE {
        self.0
    }
}

impl Drop for Event {
    fn drop(&mut self) {
        if !self.0.is_invalid() {
            unsafe {
                let _ = CloseHandle(self.0);
            }
        }
    }
}

/// Signals an event once the asynchronous device activation has finished.
#[implement(IActivateAudioInterfaceCompletionHandler)]
struct ActivationHandler {
    done: HANDLE,
}

impl IActivateAudioInterfaceCompletionHandler_Impl for ActivationHandler_Impl {
    fn ActivateCompleted(
        &self,
        _operation: Ref<'_, IActivateAudioInterfaceAsyncOperation>,
    ) -> WinResult<()> {
        unsafe { SetEvent(self.done) }
    }
}

/// Starts capturing this machine's audio with `exclude_pid`'s process tree left out.
///
/// `on_data` receives interleaved f32 samples at `SAMPLE_RATE` / `CHANNELS`. It runs
/// on the capture thread, so it must not block.
pub fn start<F>(exclude_pid: u32, on_data: F) -> ResultType<Capture>
where
    F: FnMut(&[f32]) + Send + 'static,
{
    let stop = Arc::new(AtomicBool::new(false));
    // The COM objects below are created on, and confined to, the capture thread.
    // Activation failures have to travel back here, so the thread reports through
    // this channel before entering its loop.
    let (tx, rx) = std::sync::mpsc::channel();
    let stop_thread = stop.clone();
    let thread = std::thread::spawn(move || {
        capture_thread(exclude_pid, stop_thread, on_data, tx);
    });
    match rx.recv() {
        Ok(Ok(())) => Ok(Capture {
            stop,
            thread: Some(thread),
        }),
        Ok(Err(err)) => {
            // The thread already exited; join it so it does not linger.
            let _ = thread.join();
            Err(err)
        }
        Err(_) => {
            let _ = thread.join();
            bail!("process loopback capture thread exited before reporting")
        }
    }
}

fn capture_thread<F>(
    exclude_pid: u32,
    stop: Arc<AtomicBool>,
    mut on_data: F,
    report: std::sync::mpsc::Sender<ResultType<()>>,
) where
    F: FnMut(&[f32]) + Send + 'static,
{
    // COINIT_MULTITHREADED: this thread only ever pumps audio, it has no message loop.
    let com = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    if com.is_err() {
        let _ = report.send(Err(hbb_common::anyhow::anyhow!(
            "failed to initialize COM for audio capture: {:?}",
            com
        )));
        return;
    }

    let result = run_capture(exclude_pid, &stop, &mut on_data, report);
    if let Err(err) = result {
        log::error!("process loopback capture stopped: {}", err);
    }
    unsafe { CoUninitialize() };
}

fn run_capture<F>(
    exclude_pid: u32,
    stop: &AtomicBool,
    on_data: &mut F,
    report: std::sync::mpsc::Sender<ResultType<()>>,
) -> ResultType<()>
where
    F: FnMut(&[f32]),
{
    let client = match activate_client(exclude_pid) {
        Ok(client) => client,
        Err(err) => {
            let _ = report.send(Err(err));
            return Ok(());
        }
    };

    let format = WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_IEEE_FLOAT,
        nChannels: CHANNELS,
        nSamplesPerSec: SAMPLE_RATE,
        nAvgBytesPerSec: SAMPLE_RATE * CHANNELS as u32 * 4,
        nBlockAlign: CHANNELS * 4,
        wBitsPerSample: 32,
        cbSize: 0,
    };

    let samples_ready = match init_client(&client, &format) {
        Ok(event) => event,
        Err(err) => {
            let _ = report.send(Err(err));
            return Ok(());
        }
    };

    let capture: IAudioCaptureClient = match unsafe { client.GetService() } {
        Ok(capture) => capture,
        Err(err) => {
            let _ = report.send(Err(hbb_common::anyhow::anyhow!(
                "failed to get capture service: {}",
                err
            )));
            return Ok(());
        }
    };

    if let Err(err) = unsafe { client.Start() } {
        let _ = report.send(Err(hbb_common::anyhow::anyhow!(
            "failed to start audio capture: {}",
            err
        )));
        return Ok(());
    }

    // Past this point the caller considers the capture live.
    let _ = report.send(Ok(()));
    log::info!(
        "capturing system audio with process tree {} excluded",
        exclude_pid
    );

    let result = pump(&capture, &samples_ready, stop, on_data);
    unsafe {
        let _ = client.Stop();
    }
    result
}

fn activate_client(exclude_pid: u32) -> ResultType<IAudioClient> {
    let activated = Event::new()?;
    let handler = ActivationHandler {
        done: activated.handle(),
    };
    let handler: IActivateAudioInterfaceCompletionHandler = handler.into();

    let mut params = AUDIOCLIENT_ACTIVATION_PARAMS {
        ActivationType: AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
        Anonymous: AUDIOCLIENT_ACTIVATION_PARAMS_0 {
            ProcessLoopbackParams: AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
                TargetProcessId: exclude_pid,
                ProcessLoopbackMode: PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE,
            },
        },
    };

    // The activation parameters are passed as a VT_BLOB variant.
    let mut variant = PROPVARIANT::default();
    unsafe {
        let inner = &mut variant.Anonymous.Anonymous;
        inner.vt = VT_BLOB;
        inner.Anonymous.blob = BLOB {
            cbSize: std::mem::size_of::<AUDIOCLIENT_ACTIVATION_PARAMS>() as u32,
            pBlobData: &mut params as *mut _ as *mut u8,
        };
    }

    let operation = unsafe {
        ActivateAudioInterfaceAsync(
            VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
            &IAudioClient::IID,
            Some(&variant),
            &handler,
        )
    };
    let operation = match operation {
        Ok(operation) => operation,
        Err(err) => bail!("process loopback is unavailable: {}", err),
    };

    if unsafe { WaitForSingleObject(activated.handle(), ACTIVATION_TIMEOUT_MS) } != WAIT_OBJECT_0 {
        bail!("timed out activating the process loopback device");
    }

    let mut activate_result = windows::core::HRESULT(0);
    let mut interface = None;
    unsafe { operation.GetActivateResult(&mut activate_result, &mut interface) }
        .map_err(|err| hbb_common::anyhow::anyhow!("failed to read activation result: {}", err))?;
    if activate_result.is_err() {
        bail!("process loopback activation failed: {:?}", activate_result);
    }
    match interface {
        Some(interface) => interface
            .cast::<IAudioClient>()
            .map_err(|err| hbb_common::anyhow::anyhow!("unexpected activation result: {}", err)),
        None => bail!("process loopback activation returned no interface"),
    }
}

fn init_client(client: &IAudioClient, format: &WAVEFORMATEX) -> ResultType<Event> {
    // A process loopback client is always shared mode and event driven, and it does
    // not accept a periodicity.
    unsafe {
        client.Initialize(
            AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
            BUFFER_DURATION,
            0,
            format,
            None,
        )
    }
    .map_err(|err| hbb_common::anyhow::anyhow!("failed to initialize audio capture: {}", err))?;

    let samples_ready = Event::new()?;
    unsafe { client.SetEventHandle(samples_ready.handle()) }
        .map_err(|err| hbb_common::anyhow::anyhow!("failed to set audio event handle: {}", err))?;
    Ok(samples_ready)
}

fn pump<F>(
    capture: &IAudioCaptureClient,
    samples_ready: &Event,
    stop: &AtomicBool,
    on_data: &mut F,
) -> ResultType<()>
where
    F: FnMut(&[f32]),
{
    // Reused across packets so a silent stretch does not reallocate every wake-up.
    let mut silence: Vec<f32> = Vec::new();
    while !stop.load(Ordering::SeqCst) {
        unsafe { WaitForSingleObject(samples_ready.handle(), WAIT_TIMEOUT_MS) };
        loop {
            if stop.load(Ordering::SeqCst) {
                return Ok(());
            }
            let mut data: *mut u8 = ptr::null_mut();
            let mut frames: u32 = 0;
            let mut flags: u32 = 0;
            if unsafe { capture.GetBuffer(&mut data, &mut frames, &mut flags, None, None) }.is_err()
            {
                // No more packets queued.
                break;
            }
            if frames == 0 {
                unsafe { capture.ReleaseBuffer(0) }.ok();
                break;
            }
            let samples = frames as usize * CHANNELS as usize;
            if flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0 || data.is_null() {
                silence.clear();
                silence.resize(samples, 0.0);
                on_data(&silence);
            } else {
                // The device writes interleaved f32 in the format we asked for.
                on_data(unsafe { std::slice::from_raw_parts(data as *const f32, samples) });
            }
            unsafe { capture.ReleaseBuffer(frames) }.ok();
        }
    }
    Ok(())
}
