import fs from "node:fs";
import { performance } from "node:perf_hooks";

const base = "http://10.70.0.1:8080";
const output = "/tests/artifacts/telemetry-load-raw.json";
const deviceCount = Number(process.env.TGDESK_LOAD_DEVICES || 24);
const ratePerDevice = Number(process.env.TGDESK_LOAD_RATE || 1);
const durationSeconds = Number(process.env.TGDESK_LOAD_DURATION || 12);
const sockets = [];
const evidence = {
  schema_version: 1,
  scenario: "telemetry-load-raw",
  state: "running",
  measured_at: new Date().toISOString(),
};

async function request(path, { method = "GET", token, body } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  const raw = await response.text();
  let data = raw;
  try { data = raw ? JSON.parse(raw) : null; } catch {}
  if (!response.ok) throw new Error(`${method} ${path}: ${response.status}: ${raw}`);
  return data;
}

async function openSocket(url) {
  const socket = new WebSocket(url);
  sockets.push(socket);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("websocket open timeout")), 10000);
    socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
    socket.addEventListener("error", () => reject(new Error("websocket open failed")), { once: true });
  });
  return socket;
}

function nextMessage(socket, predicate, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      socket.removeEventListener("message", listener);
      reject(new Error("message timeout"));
    }, timeout);
    const listener = (event) => {
      const message = JSON.parse(event.data);
      if (!predicate(message)) return;
      clearTimeout(timer);
      socket.removeEventListener("message", listener);
      resolve(message);
    };
    socket.addEventListener("message", listener);
  });
}

function percentile(values, ratio) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * ratio) - 1)] || 0;
}

try {
  const suffix = Date.now().toString(36);
  const adminKey = JSON.parse(fs.readFileSync("/tests/artifacts/keys/admin.tgdesk-key", "utf8"));
  const admin = await request("/api/v1/auth/control-key/install", {
    method: "POST",
    body: { key: adminKey, machine_id: "testlab-admin-vm" },
  });
  const organization = await request("/api/v1/organizations", {
    method: "POST", token: admin.token, body: { name: `Load ${suffix}` },
  });
  const network = await request("/api/v1/networks", {
    method: "POST",
    token: admin.token,
    body: { organization_id: organization.id, name: `LoadNet ${suffix}` },
  });

  const devices = [];
  for (let index = 0; index < deviceCount; index += 1) {
    const guest = await request("/api/v1/devices/register", {
      method: "POST",
      body: {
        hostname: `LOAD-${suffix}-${index}`,
        mac: `02:74:${(index >> 8).toString(16).padStart(2, "0")}:${(index & 255).toString(16).padStart(2, "0")}:${suffix.slice(-2).padStart(2, "0")}:01`,
        role: "host",
      },
    });
    await request("/api/v1/pairing/bind", {
      method: "POST",
      token: admin.token,
      body: {
        pairing_code: guest.pairing_code,
        organization_id: organization.id,
        network_id: network.id,
      },
    });
    const socket = await openSocket(
      `ws://10.70.0.1:8080/ws/control/device?device_id=${encodeURIComponent(guest.device_id)}&device_token=${encodeURIComponent(guest.device_token)}`,
    );
    await nextMessage(socket, (message) => message.type === "ready");
    devices.push({ ...guest, socket });
  }

  const expected = deviceCount * ratePerDevice * durationSeconds;
  const latencies = [];
  let succeeded = 0;
  let failed = 0;
  const intervalMs = 1000 / ratePerDevice;
  const started = performance.now();
  for (let tick = 0; tick < durationSeconds * ratePerDevice; tick += 1) {
    const scheduled = started + tick * intervalMs;
    const delay = scheduled - performance.now();
    if (delay > 0) await new Promise((resolve) => setTimeout(resolve, delay));
    await Promise.all(devices.map(async ({ socket }, index) => {
      const sent = performance.now();
      const response = nextMessage(socket, (message) => message.type === "telemetry_stats", 5000);
      socket.send(JSON.stringify({
        type: "telemetry",
        payload: {
          hardware: {
            cpu: { name: "Load CPU", usage: 40 + (tick % 20), clock_mhz: 2400 },
            memory_summary: {
              total_bytes: 17179869184,
              used_bytes: 8589934592 + index * 1024,
              available_bytes: 8589934592 - index * 1024,
              usage: 50,
            },
            gpus: [],
            storage: [{ id: "disk0", used_pct: 60, smart_status: "Healthy" }],
            networks: [{ id: "net0", status: "Up" }],
          },
        },
      }));
      try {
        await response;
        succeeded += 1;
        latencies.push(performance.now() - sent);
      } catch {
        failed += 1;
      }
    }));
  }

  evidence.state = "passed";
  evidence.finished_at = new Date().toISOString();
  evidence.metrics = {
    device_count: deviceCount,
    rate_per_device_hz: ratePerDevice,
    duration_seconds: durationSeconds,
    expected_messages: expected,
    succeeded,
    failed,
    success_rate_pct: expected ? succeeded * 100 / expected : 0,
    latency_ms: {
      average: latencies.reduce((a, b) => a + b, 0) / Math.max(1, latencies.length),
      p95: percentile(latencies, 0.95),
      maximum: Math.max(0, ...latencies),
    },
  };
  fs.writeFileSync(output, JSON.stringify(evidence, null, 2));
  process.stdout.write(JSON.stringify(evidence, null, 2));
} catch (error) {
  evidence.state = "failed";
  evidence.finished_at = new Date().toISOString();
  evidence.error = error.stack || error.message;
  fs.writeFileSync(output, JSON.stringify(evidence, null, 2));
  process.stderr.write(JSON.stringify(evidence, null, 2));
  process.exitCode = 1;
} finally {
  for (const socket of sockets) try { socket.close(); } catch {}
}
