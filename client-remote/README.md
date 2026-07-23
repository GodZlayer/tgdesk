# Cliente de Acesso Remoto (Fase 2 — Módulo B)

`rustdesk.exe` real, compilado a partir do código-fonte oficial do RustDesk
(núcleo Rust + UI Flutter), configurado para falar com o **nosso** rendezvous
(`hbbs`)/relay (`hbbr`) em vez dos servidores públicos do RustDesk — exatamente
como descrito na Seção 8.B do plano de arquitetura.

Testado nesta máquina: o processo registrou seu ID e chave pública no hbbs do
TGDesk (`docker logs server-rendezvous-1` mostrou `update_pk ...`), e o próprio
config (`RustDesk2.toml`) gravou `rendezvous_server = '127.0.0.1:21116'` — ou
seja, a sinalização já usa nossa infraestrutura, não a rede pública.

Ainda não testado nesta rodada: uma sessão de tela ponta-a-ponta completa
(Host servindo + Técnico visualizando), que exige um segundo dispositivo/VM —
fica como próximo passo natural.

## Como apontar para o hbbs/hbbr do TGDesk

O RustDesk guarda essas duas opções em `%APPDATA%\RustDesk\config\RustDesk2.toml`,
seção `[options]`:

```toml
[options]
custom-rendezvous-server = '<host_ou_ip_do_seu_hbbs>'
key = '<chave_pública_do_seu_hbbs>'
```

A chave pública é impressa no log do `hbbs` no primeiro boot:
```bash
docker logs server-rendezvous-1 | grep "Key:"
```

Em produção isso deve ser feito por código (o instalador do TGDesk grava esse
arquivo antes do primeiro uso), não manualmente — aqui foi feito à mão só para
validar o pipeline.

## Rodar

```bash
./rustdesk.exe
```

Abre a UI normal do RustDesk. O ID mostrado na tela é o ID que um técnico usaria
para se conectar a este Host — mas por enquanto essa vinculação de ID ainda não
está integrada ao fluxo de pareamento/organização do TGDesk (isso é o próximo
passo: amarrar o ID do RustDesk ao `device_id` do api-core no momento do bind).

## Recompilar do zero

Ver `../client-rustdesk-src/README` (não existe ainda — resumo do processo):
1. `vcpkg install --triplet x64-windows-static` (precisa do fix de versão do NASM,
   ver `C:\vcpkg\scripts\cmake\vcpkg_find_acquire_program(NASM).cmake`)
2. `cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked`
3. `flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/windows/bridge_generated.h`
4. Corrigir classes `Opaque`/`Struct` geradas sem modificador `base`/`final` (bug de
   geração com Dart 3.5+, ver histórico do generated_bridge.dart)
5. `cargo build --locked --features flutter --lib --release` (gera `librustdesk.dll`)
6. `cd flutter && flutter build windows --release`
7. Copiar `target/release/deps/dylib_virtual_display.dll` para a pasta de saída
