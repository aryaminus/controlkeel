#!/usr/bin/env sh
set -eu

REPO="${CONTROLKEEL_GITHUB_REPO:-aryaminus/controlkeel}"
VERSION="${CONTROLKEEL_VERSION:-latest}"
INSTALL_DIR="${CONTROLKEEL_INSTALL_DIR:-}"

detect_os() {
  case "$(uname -s)" in
    Darwin) printf "macos" ;;
    Linux) printf "linux" ;;
    *)
      echo "unsupported operating system: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf "x86_64" ;;
    arm64|aarch64) printf "arm64" ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

binary_asset_name() {
  os="$1"
  arch="$2"

  case "${os}:${arch}" in
    linux:x86_64) printf "controlkeel-linux-x86_64" ;;
    linux:arm64) printf "controlkeel-linux-arm64" ;;
    macos:x86_64) printf "controlkeel-macos-x86_64" ;;
    macos:arm64) printf "controlkeel-macos-arm64" ;;
    *)
      echo "unsupported platform: ${os}/${arch}" >&2
      exit 1
      ;;
  esac
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

# Verify the downloaded binary against the published controlkeel-checksums.txt
# before it is ever made executable or moved into place. Fails closed: a
# missing checksums file, a missing entry, an absent sha256 tool, or a
# mismatch all abort the install. Set CONTROLKEEL_SKIP_CHECKSUM=1 to bypass.
verify_checksum() {
  file="$1"
  asset="$2"
  base_url="$3"

  if [ "${CONTROLKEEL_SKIP_CHECKSUM:-}" = "1" ]; then
    echo "warning: CONTROLKEEL_SKIP_CHECKSUM=1 set; skipping integrity verification" >&2
    return 0
  fi

  checksums="${TMP_DIR}/controlkeel-checksums.txt"
  if ! curl -fsSL "${base_url}/controlkeel-checksums.txt" -o "$checksums"; then
    echo "error: could not download checksums for integrity verification" >&2
    echo "       set CONTROLKEEL_SKIP_CHECKSUM=1 to bypass (not recommended)" >&2
    exit 1
  fi

  expected="$(awk -v a="$asset" '$2 ~ ("(^|/)" a "$") {print $1; exit}' "$checksums")"
  if [ -z "$expected" ]; then
    echo "error: no checksum entry for ${asset}; refusing to install" >&2
    exit 1
  fi

  if ! actual="$(sha256_of "$file")"; then
    echo "error: no sha256 tool (sha256sum/shasum) available to verify download" >&2
    echo "       set CONTROLKEEL_SKIP_CHECKSUM=1 to bypass (not recommended)" >&2
    exit 1
  fi

  if [ "$expected" != "$actual" ]; then
    echo "error: checksum mismatch for ${asset}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi

  echo "Verified ${asset} (sha256 ${actual})"
  verify_signature "$file" "$asset" "$base_url"
}

# Verify the cosign signature when cosign is installed. Falls back gracefully
# when cosign is not available. Cosign keyless signing uses GitHub OIDC identity.
verify_signature() {
  file="$1"
  asset="$2"
  base_url="$3"

  if [ "${CONTROLKEEL_SKIP_SIGNATURE:-}" = "1" ]; then
    return 0
  fi

  if ! command -v cosign >/dev/null 2>&1; then
    echo "note: cosign not found; skipping signature verification (checksum-only mode)"
    return 0
  fi

  sig_file="${TMP_DIR}/${asset}.sig"
  cert_file="${TMP_DIR}/${asset}.pem"

  if ! curl -fsSL "${base_url}/${asset}.sig" -o "$sig_file" 2>/dev/null; then
    if [ "${CONTROLKEEL_REQUIRE_SIGNATURE:-}" = "1" ]; then
      echo "error: no cosign signature available for ${asset}" >&2
      exit 1
    fi
    echo "note: no cosign signature available for ${asset}; skipping"
    return 0
  fi

  if ! curl -fsSL "${base_url}/${asset}.pem" -o "$cert_file" 2>/dev/null; then
    if [ "${CONTROLKEEL_REQUIRE_SIGNATURE:-}" = "1" ]; then
      echo "error: no cosign certificate available for ${asset}" >&2
      exit 1
    fi
    echo "note: no cosign certificate available for ${asset}; skipping"
    return 0
  fi

  if cosign verify-blob "$file"     --signature "$sig_file"     --certificate "$cert_file"     --certificate-identity-regexp "^https://github.com/${REPO}/.github/workflows/release.yml@refs/tags/v[0-9].*"     --certificate-oidc-issuer "https://token.actions.githubusercontent.com"     >/dev/null 2>&1; then
    echo "Verified ${asset} signature (cosign keyless)"
  else
    echo "error: cosign signature verification failed for ${asset}" >&2
    exit 1
  fi
}

release_base_url() {
  if [ "$VERSION" = "latest" ]; then
    printf "https://github.com/%s/releases/latest/download" "$REPO"
  else
    printf "https://github.com/%s/releases/download/v%s" "$REPO" "$VERSION"
  fi
}

default_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    printf "%s" "$INSTALL_DIR"
  elif [ -w "/usr/local/bin" ]; then
    printf "/usr/local/bin"
  else
    printf "%s/.local/bin" "${HOME:-$PWD}"
  fi
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
ASSET="$(binary_asset_name "$OS" "$ARCH")"
BASE_URL="$(release_base_url)"
DEST_DIR="$(default_install_dir)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$DEST_DIR"

curl -fsSL "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/controlkeel"
verify_checksum "${TMP_DIR}/controlkeel" "$ASSET" "$BASE_URL"
chmod +x "${TMP_DIR}/controlkeel"
mv "${TMP_DIR}/controlkeel" "${DEST_DIR}/controlkeel"

echo "Installed ControlKeel to ${DEST_DIR}/controlkeel"
echo ""

case ":$PATH:" in
  *":${DEST_DIR}:"*) ;;
  *)
    echo "Add ${DEST_DIR} to your PATH first:" >&2
    echo "  export PATH=\"${DEST_DIR}:\$PATH\"" >&2
    rc_file=""
    case "${SHELL:-}" in
      */zsh) rc_file="${HOME}/.zshrc" ;;
      */bash) rc_file="${HOME}/.bashrc" ;;
    esac
    if [ -n "$rc_file" ]; then
      echo "  Tip: add this to ${rc_file} to persist across shells." >&2
    else
      echo "  Tip: add this to ~/.zshrc or ~/.bashrc to persist across shells." >&2
    fi
    echo "" >&2
    ;;
esac

cat <<'EOF'
Next steps — set up this project and wire ControlKeel into your agent host:

  1. From the repository you want to govern:
       controlkeel setup

  2. Attach to the agent you use (project scope is the default):
       controlkeel attach claude-code
       controlkeel attach cursor
       controlkeel attach codex-cli
       controlkeel attach opencode
       controlkeel attach copilot

  3. Verify the local governance path:
       controlkeel attach doctor
       controlkeel provider doctor
       controlkeel status
       controlkeel findings

  4. Optional — sync governance evidence to a control plane:
       controlkeel cloud connect --enroll https://controlkeel.com
     (or your self-host URL, e.g. https://govern.acme.com)
       controlkeel cloud doctor

Run `controlkeel --help` for the full surface. See docs/self-hosting.md
to run your own controlkeel.com on fly.io.
EOF
