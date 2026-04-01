#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_DIR="${VCPKG_DIR:-$HOME/vcpkg}"
SCITER_URL="${SCITER_URL:-https://raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.lnx/x64/libsciter-gtk.so}"
BUILD_MODE="${BUILD_MODE:-release}"

echo "[1/7] Installing AlmaLinux build dependencies"
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
  libasan \
  libatomic \
  libdrm-devel \
  libstdc++-static \
  make \
  nasm \
  openssl-devel \
  pam-devel \
  perl \
  pulseaudio-libs-devel \
  python3 \
  tar \
  unzip \
  wget \
  xdotool-devel \
  xz \
  zip

echo "[2/7] Installing Rust toolchain if needed"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
source "$HOME/.cargo/env"

echo "[3/7] Preparing vcpkg"
if [ ! -d "$VCPKG_DIR/.git" ]; then
  git clone https://github.com/microsoft/vcpkg "$VCPKG_DIR"
fi
git -C "$VCPKG_DIR" fetch --all --tags
git -C "$VCPKG_DIR" checkout 2023.04.15
"$VCPKG_DIR/bootstrap-vcpkg.sh"
export VCPKG_ROOT="$VCPKG_DIR"

echo "[4/7] Installing vcpkg libraries"
"$VCPKG_ROOT/vcpkg" install --x-install-root="$VCPKG_ROOT/installed" libvpx libyuv opus aom

echo "[5/7] Fetching Linux Sciter runtime"
mkdir -p "$ROOT_DIR/target/$BUILD_MODE"
curl -L "$SCITER_URL" -o "$ROOT_DIR/target/$BUILD_MODE/libsciter-gtk.so"

echo "[6/7] Building TGdesk for AlmaLinux"
cd "$ROOT_DIR"
cargo build --release

echo "[7/7] Packing tarball"
ARTIFACT_DIR="$ROOT_DIR/dist/almalinux/TGdesk"
rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"
cp "$ROOT_DIR/target/release/rustdesk" "$ARTIFACT_DIR/TGdesk"
cp "$ROOT_DIR/target/release/libsciter-gtk.so" "$ARTIFACT_DIR/libsciter-gtk.so"
cp -r "$ROOT_DIR/src" "$ARTIFACT_DIR/src"
cp -r "$ROOT_DIR/res" "$ARTIFACT_DIR/res"
mkdir -p "$ARTIFACT_DIR/data/flutter_assets/assets"
if [ -f "$ROOT_DIR/tgimg/favicon.ico" ]; then
  cp "$ROOT_DIR/tgimg/favicon.ico" "$ARTIFACT_DIR/data/flutter_assets/assets/icon.ico"
fi
if [ -f "$ROOT_DIR/flutter/assets/icon.png" ]; then
  cp "$ROOT_DIR/flutter/assets/icon.png" "$ARTIFACT_DIR/data/flutter_assets/assets/icon.png"
fi
if [ -f "$ROOT_DIR/flutter/assets/logo.png" ]; then
  cp "$ROOT_DIR/flutter/assets/logo.png" "$ARTIFACT_DIR/data/flutter_assets/assets/logo.png"
fi
tar -C "$ROOT_DIR/dist/almalinux" -czf "$ROOT_DIR/dist/TGdesk-almalinux-x86_64.tar.gz" TGdesk

echo
echo "Build complete:"
echo "  $ROOT_DIR/dist/TGdesk-almalinux-x86_64.tar.gz"
