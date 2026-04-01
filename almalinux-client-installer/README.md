# TGdesk AlmaLinux Client Installer

Esta e a pasta unica e exclusiva do instalador do client para AlmaLinux.

Conteudo:

- `install.sh`
- `one-line.txt`

One-line:

```bash
curl -fsSL https://raw.githubusercontent.com/GodZlayer/tgdesk/main/almalinux-client-installer/install.sh | bash
```

Fluxo:

1. baixa o codigo do repositorio
2. instala dependencias
3. compila o TGdesk
4. instala o client em `/opt/TGdesk`
5. cria o launcher `tgdesk`
6. depois disso o uso segue o fluxo normal do programa
