#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-TGdesk}"
GITHUB_USER="${GITHUB_USER:-GodZlayer}"
GITHUB_REPO="${GITHUB_REPO:-tgdesk}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
WORK_DIR="${WORK_DIR:-/opt/TGdesk-src}"
INSTALL_DIR="${INSTALL_DIR:-/opt/TGdesk}"
LAUNCHER_PATH="${LAUNCHER_PATH:-/usr/local/bin/tgdesk}"
DESKTOP_FILE_PATH="${DESKTOP_FILE_PATH:-/usr/share/applications/tgdesk.desktop}"
VCPKG_DIR="${VCPKG_DIR:-$HOME/vcpkg}"
SCITER_URL="${SCITER_URL:-https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so}"

echo "[1/9] Instalando dependencias do AlmaLinux"
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
  make \
  nasm \
  openssl-devel \
  pam-devel \
  pulseaudio-libs-devel \
  tar \
  unzip \
  wget \
  xdotool-devel \
  xz \
  zip

echo "[2/9] Instalando Rust"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
source "$HOME/.cargo/env"

echo "[3/9] Preparando vcpkg"
if [ ! -d "$VCPKG_DIR/.git" ]; then
  git clone https://github.com/microsoft/vcpkg "$VCPKG_DIR"
fi
git -C "$VCPKG_DIR" fetch --all --tags
git -C "$VCPKG_DIR" checkout 2023.04.15
"$VCPKG_DIR/bootstrap-vcpkg.sh"
export VCPKG_ROOT="$VCPKG_DIR"
"$VCPKG_ROOT/vcpkg" install --x-install-root="$VCPKG_ROOT/installed" libvpx libyuv opus aom

echo "[4/9] Baixando o codigo-fonte"
sudo rm -rf "$WORK_DIR"
sudo mkdir -p "$(dirname "$WORK_DIR")"
sudo chown "$USER":"$USER" "$(dirname "$WORK_DIR")"
git clone "https://github.com/$GITHUB_USER/$GITHUB_REPO.git" "$WORK_DIR"
git -C "$WORK_DIR" checkout "$GITHUB_BRANCH"

echo "[5/9] Configurando Git local do clone"
git -C "$WORK_DIR" config user.name "godzlayer"
git -C "$WORK_DIR" config user.email "santoss.cog@gmail.com"

echo "[6/9] Baixando runtime do Sciter"
mkdir -p "$WORK_DIR/target/release"
curl -L "$SCITER_URL" -o "$WORK_DIR/target/release/libsciter-gtk.so"

echo "[7/9] Compilando TGdesk"
cd "$WORK_DIR"
cargo build --release

echo "[8/9] Instalando arquivos finais"
sudo rm -rf "$INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"
sudo cp "$WORK_DIR/target/release/rustdesk" "$INSTALL_DIR/TGdesk"
sudo cp "$WORK_DIR/target/release/libsciter-gtk.so" "$INSTALL_DIR/libsciter-gtk.so"
sudo cp -r "$WORK_DIR/src" "$INSTALL_DIR/src"
sudo cp -r "$WORK_DIR/res" "$INSTALL_DIR/res"
sudo mkdir -p "$INSTALL_DIR/data/flutter_assets/assets"
if [ -f "$WORK_DIR/tgimg/favicon.ico" ]; then
  sudo cp "$WORK_DIR/tgimg/favicon.ico" "$INSTALL_DIR/data/flutter_assets/assets/icon.ico"
fi
if [ -f "$WORK_DIR/flutter/assets/icon.png" ]; then
  sudo cp "$WORK_DIR/flutter/assets/icon.png" "$INSTALL_DIR/data/flutter_assets/assets/icon.png"
fi
if [ -f "$WORK_DIR/flutter/assets/logo.png" ]; then
  sudo cp "$WORK_DIR/flutter/assets/logo.png" "$INSTALL_DIR/data/flutter_assets/assets/logo.png"
fi

sudo tee "$LAUNCHER_PATH" >/dev/null <<'EOF'
#!/usr/bin/env bash
cd /opt/TGdesk
exec ./TGdesk "$@"
EOF
sudo chmod +x "$LAUNCHER_PATH"

sudo tee "$DESKTOP_FILE_PATH" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Exec=$LAUNCHER_PATH
Icon=$INSTALL_DIR/data/flutter_assets/assets/icon
Terminal=false
Categories=Network;RemoteAccess;
StartupNotify=true
EOF

echo "[9/9] Finalizado"
echo
echo "Abrir via terminal: tgdesk"
echo "Instalado em: $INSTALL_DIR"
echo "Fluxo de uso: apos a instalacao, o TGdesk abre e segue o fluxo normal do programa."
