#!/usr/bin/env bash
# Salaryman installer.
# Usage: install.sh [--unattended]
set -euo pipefail

SALARYMAN_URL="${SALARYMAN_URL:-https://raw.githubusercontent.com/p-phi/salaryman/main/salaryman.sh}"
SALARYMAN_BIN="${SALARYMAN_BIN:-$HOME/.local/bin}"

UNATTENDED=false
for arg in "$@"; do
  case "$arg" in
    --unattended) UNATTENDED=true ;;
    -h|--help)
      echo "usage: install.sh [--unattended]"
      exit 0 ;;
    *)
      echo "error: unknown argument: $arg" >&2
      exit 1 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- deps

missing=()
command -v curl >/dev/null || missing+=("curl")
command -v jq   >/dev/null || missing+=("jq")

if [[ ${#missing[@]} -gt 0 ]]; then
  say "missing dependencies: ${missing[*]}"

  # Detect a package manager.
  os=$(uname -s)
  pkg_install=""
  if [[ "$os" == "Darwin" ]]; then
    command -v brew >/dev/null && pkg_install="brew install ${missing[*]}"
  else
    . /etc/os-release 2>/dev/null || true
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*ubuntu*) pkg_install="apt-get update && apt-get install -y ${missing[*]}" ;;
      *fedora*|*rhel*)   pkg_install="dnf install -y ${missing[*]}" ;;
      *arch*)            pkg_install="pacman -S --noconfirm ${missing[*]}" ;;
      *alpine*)          pkg_install="apk add ${missing[*]}" ;;
    esac
  fi

  if [[ -z "$pkg_install" ]]; then
    fail "no supported package manager found. Install ${missing[*]} manually, then re-run this script."
  fi

  # Check we can actually run the package manager with sudo.
  if [[ "$os" != "Darwin" ]]; then
    if ! command -v sudo >/dev/null; then
      fail "sudo is not available. Install ${missing[*]} manually or re-run this script with the right privileges."
    fi
    if ! sudo -n true 2>/dev/null; then
      fail "sudo requires a password, or is not permitted. Re-run this script with the right privileges, or install ${missing[*]} manually."
    fi
  fi

  say "install command: $pkg_install"

  if [[ "$UNATTENDED" != true ]]; then
    printf 'install these dependencies now? [y/N] '
    read -r answer
    case "$answer" in
      [yY]|[yY][eE][sS]) ;;
      *) fail "aborted. Install ${missing[*]} manually and re-run." ;;
    esac
  fi

  if [[ "$os" == "Darwin" ]]; then
    eval "$pkg_install"
  else
    sudo sh -c "$pkg_install"
  fi

  # Re-check.
  command -v curl >/dev/null || fail "curl is still missing after install."
  command -v jq   >/dev/null || fail "jq is still missing after install."
  say "dependencies installed."
fi

# ---------------------------------------------------------------- download

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

say "downloading $SALARYMAN_URL"
curl -fsSL "$SALARYMAN_URL" -o "$tmp" || fail "download failed."

head -n1 "$tmp" | grep -q '^#!' || fail "downloaded file does not look like a script."
grep -q 'SALARYMAN_ENDPOINT' "$tmp" || fail "downloaded file does not look like salaryman."

# ---------------------------------------------------------------- install

mkdir -p "$SALARYMAN_BIN"
chmod +x "$tmp"
mv "$tmp" "$SALARYMAN_BIN/salaryman"
trap - EXIT

say "installed $SALARYMAN_BIN/salaryman"

# ---------------------------------------------------------------- PATH

case ":$PATH:" in
  *":$SALARYMAN_BIN:"*) ;;
  *)
    say ""
    say "$SALARYMAN_BIN is not on your PATH. Add this to your shell config:"
    say "  export PATH=\"$SALARYMAN_BIN:\$PATH\""
    ;;
esac
