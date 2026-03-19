#!/usr/bin/env sh
set -eu

VERSION="${1:-0.15.2}"
INSTALL_ROOT="${INSTALL_ROOT:-/usr/local/zig}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux)
    case "$arch" in
      x86_64|amd64) zig_target="x86_64-linux" ;;
      aarch64|arm64) zig_target="aarch64-linux" ;;
      *) echo "unsupported Linux architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      x86_64|amd64) zig_target="x86_64-macos" ;;
      arm64|aarch64) zig_target="aarch64-macos" ;;
      *) echo "unsupported macOS architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "unsupported host OS: $os" >&2
    exit 1
    ;;
esac

archive="zig-${zig_target}-${VERSION}.tar.xz"
url="https://ziglang.org/download/${VERSION}/${archive}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT INT TERM

curl -fLsS "$url" -o "$tmp_dir/zig.tar.xz"
tar -xJf "$tmp_dir/zig.tar.xz" -C "$tmp_dir"

extracted_dir="$tmp_dir/zig-${zig_target}-${VERSION}"

if [ ! -d "$extracted_dir" ]; then
  echo "expected extracted Zig directory not found: $extracted_dir" >&2
  exit 1
fi

sudo rm -rf "$INSTALL_ROOT"
sudo mv "$extracted_dir" "$INSTALL_ROOT"
echo "$INSTALL_ROOT"
