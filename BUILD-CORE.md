# Compilar o core Rust (`libtgdeskcore.dll`)

O build do cliente **não** compila o Rust. `Invoke-TGDeskBuild.ps1 -Scope Full`
roda `flutter build windows --release`, e o CMake do Flutter apenas **copia**
`client-rustdesk-src/target/release/libtgdeskcore.dll` para o diretório de
release (`flutter/windows/CMakeLists.txt`, `RUSTDESK_LIB`).

Consequência: mudar qualquer coisa em `client-rustdesk-src/src/` e rodar só o
pipeline publica um `tgdesk.exe` novo com o core **antigo**. Isso já quase
aconteceu na 1.1.51 — o C++ passou a registrar a janela como
`TGDESK_RUNNER_WIN32_WINDOW` e o core antigo continuaria procurando
`FLUTTER_RUNNER_WIN32_WINDOW`, deixando o "Fechar janela" da bandeja mandando
`WM_CLOSE` para a janela de outro aplicativo.

**Antes de publicar, confira a data:**

```
ls -la client-rustdesk-src/target/release/libtgdeskcore.dll
git log -1 --format=%cd -- client-rustdesk-src/src
```

Se o commit for mais novo que a DLL, recompile.

## O comando

```
$env:VCPKG_ROOT='C:\vcpkg'
cd client-rustdesk-src
cargo build --release --lib --features flutter,hwcodec
```

Depois rode o pipeline (`Invoke-TGDeskBuild.ps1 -Scope Full`), que copia a DLL
nova para o stage.

## A dependência que trava: o ffmpeg tem que ser o do RustDesk

O ffmpeg do vcpkg **não serve**, e por dois motivos independentes.

**Versão.** `hwcodec` usa `FF_PROFILE_H264_HIGH`, `FF_PROFILE_HEVC_MAIN` e
`AVFrame::key_frame`, os três removidos no ffmpeg 8. O vcpkg de hoje instala
8.x, e a compilação morre em `util.cpp` e `ffmpeg_ram_decode.cpp`.

**Configuração.** Instalar o 7.1.1 do vcpkg faz compilar, e então o link falha
com `swr_alloc`, `swr_convert` e mais quatro símbolos de `libswresample`,
além de `IID_ICodecAPI` e `IID_IMFTransform`. O motivo é que
`build.rs` do hwcodec linka apenas `avcodec`, `avutil`, `avformat` e `libmfx`
— ele foi escrito para a build **mínima** que o RustDesk mantém, com
`--disable-everything` e `--disable-swresample`. A build completa do vcpkg
compila caminhos de código que aquela lista de bibliotecas não cobre.

O port certo está no próprio repositório, em
`client-rustdesk-src/res/vcpkg/ffmpeg` — é para ele que o comentário do
`build.rs` do hwcodec aponta. Junto dele vêm `aom`, `libvpx`, `libyuv`,
`mfx-dispatch` e `opus`, pela mesma razão.

```
cd C:/vcpkg
./vcpkg.exe remove ffmpeg:x64-windows-static --recurse
./vcpkg.exe install "ffmpeg[amf,nvcodec,qsv]:x64-windows-static" \
  --overlay-ports=C:/Users/santo/Documents/TGDESK/client-rustdesk-src/res/vcpkg \
  --recurse
```

O triplet é `x64-windows-static` porque `.cargo/config.toml` compila com
`+crt-static`, e o crate `vcpkg` escolhe o triplet a partir disso. O ffmpeg
instalado em `x64-windows` (dinâmico) não serve.

As features `amf,nvcodec,qsv` são a aceleração por hardware da AMD, da NVIDIA e
da Intel. Compilar sem `hwcodec` resolveria o erro e publicaria uma regressão
silenciosa — a DLL em produção tem hwcodec.
