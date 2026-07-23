# tgdesk.exe — Um único executável, Host e Técnico

Este é o build consolidado: **um só exe** contendo o núcleo RustDesk (captura
de tela, viewer, tudo que já existia) **e** as telas do TGDesk Hub
(Admin/Técnico), na mesma janela de processo — não são mais dois builds
separados (`client-remote` + `client-hub`).

## Como a unificação funciona

O próprio RustDesk já abre janelas extras dentro do **mesmo processo/exe**
para sessão remota, transferência de arquivo, terminal etc. — usando o
plugin `desktop_multi_window` (ver `flutter/lib/utils/multi_window_manager.dart`
e o `switch` em `flutter/lib/main.dart`). Só acrescentei mais um tipo de
janela nessa mesma lista: `WindowType.TgdeskHub`, que abre nossas telas
(login → dispositivos/admin/técnicos) como uma janela nativa a mais,
sem depender do núcleo Rust/FFI (é só HTTP/WebSocket puro em Dart).

- Botão de acesso: ícone `admin_panel_settings_outlined` no canto inferior
  direito da barra lateral esquerda do RustDesk (perto do ícone de
  configurações existente) — abre a janela do Hub.
- O diferencial Host vs. Técnico é **só a UI exposta**, exatamente como você
  descreveu: o mesmo `tgdesk.exe` sempre é capaz de servir uma sessão remota
  (é literalmente o núcleo RustDesk completo); a diferença é que sem login de
  técnico, não há acesso às telas de gestão.

## O que falta para fechar 100%

- **Verificação visual do clique**: compilei com sucesso e confirmei que o
  processo roda estável, mas não consegui confirmar de forma automatizada
  (sem interação manual) que o clique no ícone abre a janela — tentativas de
  automação por coordenadas de tela não acertaram o botão de forma confiável,
  e evitei repetir captura de tela cheia após um incidente anterior de
  privacidade nesta sessão. **Peço que você mesmo clique no ícone uma vez
  para confirmar visualmente** — o mecanismo é exatamente o mesmo (mesmo
  código, mesmo padrão) que já funciona para as outras janelas do RustDesk.
- **Consolidação do túnel WireGuard**: hoje ainda existem dois executáveis Go
  separados (`client-host/tgdesk-host.exe` para o papel Host,
  `client-tunnel/tgdesk-tunnel.exe` para o papel Técnico). O próximo passo é
  unir os dois num único `tgdesk-agent.exe` (com sub-modos `host`/`technician`)
  e fazer o `tgdesk.exe` lançá-lo sozinho na inicialização — hoje ele ainda
  não faz isso automaticamente.
- **RustDesk_id automático**: como o núcleo RustDesk agora roda dentro do
  próprio `tgdesk.exe` (não é mais um processo filho separado lançado pelo
  `tgdesk-host.exe`), o passo de capturar `--get-id` e reportar ao servidor
  precisa ser refeito como parte do agente único acima.

## Rodar

```bash
./tgdesk.exe
```
