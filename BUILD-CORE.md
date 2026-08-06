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

## A dependência que trava: ffmpeg 7.x

`hwcodec` usa `FF_PROFILE_H264_HIGH`, `FF_PROFILE_HEVC_MAIN` e
`AVFrame::key_frame` — os três removidos no ffmpeg 8. Com ffmpeg 8 o build
falha em `util.cpp` e `ffmpeg_ram_decode.cpp`.

O vcpkg de hoje instala 8.x. O RustDesk fixa o commit de vcpkg em
`VCPKG_COMMIT_ID` (`.github/workflows/flutter-build.yml`) exatamente para
evitar isso; naquele commit o port é 7.1.1.

Sem mover a árvore inteira do vcpkg — o que invalidaria libyuv, opus, aom, vpx
e libjpeg-turbo já instalados —, extraia só o port do ffmpeg como overlay:

```
mkdir -p .vcpkg-overlay
git -C C:/vcpkg archive 120deac3062162151622ca4860575a33844ba10b ports/ffmpeg \
  | tar -x -C .vcpkg-overlay --strip-components=1

cd C:/vcpkg
./vcpkg.exe remove ffmpeg:x64-windows-static --recurse
./vcpkg.exe install "ffmpeg[amf,nvcodec,qsv]:x64-windows-static" \
  --overlay-ports=C:/Users/santo/Documents/TGDESK/.vcpkg-overlay --recurse
```

O triplet é `x64-windows-static` porque `.cargo/config.toml` compila com
`+crt-static`, e o crate `vcpkg` escolhe o triplet a partir disso. O ffmpeg
instalado em `x64-windows` (dinâmico) não serve.

As features `amf,nvcodec,qsv` são as mesmas do triplet dinâmico: são a
aceleração por hardware da AMD, da NVIDIA e da Intel. Compilar sem `hwcodec`
resolveria o erro e publicaria uma regressão silenciosa — a DLL em produção
tem hwcodec.
