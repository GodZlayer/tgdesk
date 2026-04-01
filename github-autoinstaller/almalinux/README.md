# AlmaLinux Autoinstaller

Esta pasta foi separada para voce subir direto ao GitHub e usar o fluxo de instalacao por linha de comando.

Arquivos:

- `install.sh`: baixa o repositorio, instala dependencias, compila e instala o `TGdesk`
- `one-line.txt`: comando pronto para instalacao em uma linha

Fluxo:

1. O usuario executa a one-liner no AlmaLinux.
2. O script instala dependencias e compila o `TGdesk`.
3. O programa final fica em `/opt/TGdesk`.
4. O launcher `tgdesk` e criado em `/usr/local/bin/tgdesk`.
5. Depois da instalacao, o uso segue o fluxo normal do app instalado.

One-liner padrao:

```bash
curl -fsSL https://raw.githubusercontent.com/godzlayer/TGdesk/main/github-autoinstaller/almalinux/install.sh | bash
```

Variaveis opcionais:

```bash
GITHUB_USER=godzlayer GITHUB_REPO=TGdesk GITHUB_BRANCH=main curl -fsSL https://raw.githubusercontent.com/godzlayer/TGdesk/main/github-autoinstaller/almalinux/install.sh | bash
```
