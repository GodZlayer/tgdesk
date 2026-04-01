#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-TGdesk}"
GITHUB_USER="${GITHUB_USER:-godzlayer}"
GITHUB_REPO="${GITHUB_REPO:-TGdesk}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/TGdesk-src}"
TARGET_DIR="${TARGET_DIR:-/opt/TGdesk}"
BIN_NAME="${BIN_NAME:-TGdesk}"
DESKTOP_FILE_PATH="${DESKTOP_FILE_PATH:-/usr/share/applications/tgdesk.desktop}"
OS_MAJOR="$(rpm -E %rhel 2>/dev/null || true)"

enable_extra_repos() {
  sudo dnf install -y dnf-plugins-core epel-release
  if [ "$OS_MAJOR" = "8" ]; then
    sudo dnf config-manager --set-enabled powertools || true
  else
    sudo dnf config-manager --set-enabled crb || true
  fi
}

echo "[1/8] Instalando dependencias de build"
enable_extra_repos
sudo dnf install -y \
  clang \
  cmake \
  curl \
  gcc \
  gcc-c++ \
  git \
  gstreamer1-devel \
  gstreamer1-plugins-base-devel \
  gtk3-devel \
  libXfixes-devel \
  libXrandr-devel \
  libatomic \
  libxdo-devel \
  make \
  nasm \
  openssl-devel \
  pam-devel \
  pulseaudio-libs-devel \
  tar \
  unzip \
  wget \
  yasm \
  xz \
  zip

echo "[2/8] Preparando codigo-fonte"
sudo rm -rf "$INSTALL_ROOT"
sudo mkdir -p "$(dirname "$INSTALL_ROOT")"
sudo chown "$USER":"$USER" "$(dirname "$INSTALL_ROOT")"
git clone "https://github.com/$GITHUB_USER/$GITHUB_REPO.git" "$INSTALL_ROOT"
git -C "$INSTALL_ROOT" checkout "$GITHUB_BRANCH"

echo "[3/8] Configurando Git local do projeto"
git -C "$INSTALL_ROOT" config user.name "godzlayer"
git -C "$INSTALL_ROOT" config user.email "santoss.cog@gmail.com"

echo "[4/8] Compilando build AlmaLinux"
bash "$INSTALL_ROOT/scripts/build-almalinux.sh"

echo "[5/8] Instalando arquivos finais"
sudo rm -rf "$TARGET_DIR"
sudo mkdir -p "$TARGET_DIR"
sudo tar -xzf "$INSTALL_ROOT/dist/TGdesk-almalinux-x86_64.tar.gz" -C /tmp
sudo cp -r /tmp/TGdesk/. "$TARGET_DIR/"
sudo rm -rf /tmp/TGdesk

echo "[6/8] Criando launcher"
sudo tee /usr/local/bin/tgdesk >/dev/null <<'EOF'
#!/usr/bin/env bash
cd /opt/TGdesk
exec ./TGdesk "$@"
EOF
sudo chmod +x /usr/local/bin/tgdesk

echo "[7/8] Criando atalho grafico"
sudo tee "$DESKTOP_FILE_PATH" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=/usr/local/bin/tgdesk
Icon=$TARGET_DIR/data/flutter_assets/assets/icon
Terminal=false
Categories=Network;RemoteAccess;
StartupNotify=true
EOF

echo "[8/8] Finalizado"
echo
echo "Executar: tgdesk"
echo "Instalado em: $TARGET_DIR"
