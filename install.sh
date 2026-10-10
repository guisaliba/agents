#!/usr/bin/env bash
# Install the approved Pi stack in user-owned paths. No authentication is copied.
set -Eeuo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SYSTEM_PACKAGES=false
SERVICE=true
usage() {
  printf '%s\n' 'Usage: ./install.sh [--system-packages] [--no-service]' \
    'Arch Linux, Debian 12+, Ubuntu 24.04+. User-local pinned runtimes.' \
    '--system-packages: explicitly install OS prerequisites through sudo.' \
    '--no-service: provision files without enabling or starting the memory service.'
}
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --system-packages) SYSTEM_PACKAGES=true ;;
    --no-service) SERVICE=false ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done
[[ $(uname -s) == Linux ]] || { printf 'Linux is required.\n' >&2; exit 1; }
# This is the operating system's public identification file, not a dotenv file.
source /etc/os-release
source "$REPO/lib/platform.sh"
PLATFORM=$(pi_port_platform "${ID:-}" "${ID_LIKE:-}")
case "$PLATFORM" in
  arch) PACKAGES=(curl git python chromium librsvg imagemagick xz); MANAGER=pacman ;;
  debian) PACKAGES=(curl git python3 chromium librsvg2-bin imagemagick xz-utils); MANAGER=apt ;;
  ubuntu) PACKAGES=(curl git python3 librsvg2-bin imagemagick xz-utils); MANAGER=apt ;;
  *) printf 'Unsupported distribution: %s. No installation was made.\n' "${ID:-unknown}" >&2; exit 1 ;;
esac
if [[ $PLATFORM != arch ]]; then
  major=${VERSION_ID%%.*}
  [[ $major =~ ^[0-9]+$ ]] || { printf 'Unknown distribution version.\n' >&2; exit 1; }
  if [[ $PLATFORM == debian && $major -lt 12 || $PLATFORM == ubuntu && $major -lt 24 ]]; then
    printf 'Use Debian 12+ or Ubuntu 24.04+.\n' >&2; exit 1
  fi
fi
if "$SYSTEM_PACKAGES"; then
  if [[ $MANAGER == pacman ]]; then sudo pacman -S --needed "${PACKAGES[@]}"
  else sudo apt-get update; sudo apt-get install "${PACKAGES[@]}"; fi
fi
for tool in curl git python3 tar xz sha256sum rsvg-convert; do
  command -v "$tool" >/dev/null || { printf 'Missing prerequisite: %s. See README.md.\n' "$tool" >&2; exit 1; }
done
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' || { printf 'Python 3.11+ is required.\n' >&2; exit 1; }
BROWSER=false
for file in /usr/bin/chromium /usr/bin/google-chrome /usr/bin/chromium-browser; do
  [[ -x $file ]] && BROWSER=true
done
"$BROWSER" || { printf 'Install native Chromium or Google Chrome before installation. Ubuntu snap browsers are not verified.\n' >&2; exit 1; }
if "$SERVICE"; then
  systemctl --user show --property=Version --value >/dev/null 2>&1 || { printf 'A working systemd user manager is required. Use --no-service only for provisioning.\n' >&2; exit 1; }
fi
ROOT=${PI_PORT_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pi-port}
export PI_PORT_HOME="$ROOT"
python3 -B "$REPO/lib/pi_port.py" prepare "$ROOT"
ARCH=$(uname -m)
TEMP=$(mktemp -d)
trap 'rm -rf -- "$TEMP"' EXIT
: > "$TEMP/npm-user.conf"
: > "$TEMP/npm-global.conf"
fetch_runtime() {
  local name=$1 url checksum archive
  mapfile -t asset < <(python3 -B "$REPO/lib/pi_port.py" asset "$name" "$ARCH")
  [[ ${#asset[@]} == 3 ]] || { printf 'Unsupported architecture or invalid release lock.\n' >&2; exit 1; }
  url=${asset[0]}; checksum=${asset[1]}; archive=${asset[2]}
  if [[ ! -d $ROOT/runtime/$name ]]; then
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 300 "$url" -o "$TEMP/$archive"
    printf '%s  %s\n' "$checksum" "$TEMP/$archive" | sha256sum --check --status
    python3 -B "$REPO/lib/pi_port.py" extract "$TEMP/$archive" "$TEMP/$name" "$name"
    mv -- "$TEMP/$name" "$ROOT/runtime/$name"
  fi
}
fetch_runtime node
export PATH="$ROOT/runtime/node/bin:$PATH"
fetch_runtime ai-memory
fetch_runtime rtk
python3 -B "$REPO/lib/pi_port.py" versions "$ROOT"
for package in runtime manager renderer; do
  destination="$ROOT/packages/$package"
  python3 -B "$REPO/lib/pi_port.py" manifests "$REPO/pi/$package" "$destination"
  (cd -- "$destination"; npm ci --ignore-scripts --no-audit --no-fund --userconfig="$TEMP/npm-user.conf" --globalconfig="$TEMP/npm-global.conf" --cache="$ROOT/cache/npm")
done
python3 -B "$REPO/lib/pi_port.py" sources "$ROOT"
python3 -B "$REPO/pi/configure-subagents.py" --agent-dir "$ROOT/agent"
python3 -B "$REPO/lib/pi_port.py" configure "$ROOT"
if "$SERVICE"; then
  systemctl --user daemon-reload
  systemctl --user enable --now pi-port-memory.service
  python3 -B "$REPO/lib/pi_port.py" health "$ROOT"
fi
printf '\nInstalled. Authentication stays under your control.\nRun: %s login\nThen: %s doctor\n' "$HOME/.local/bin/pi-port" "$HOME/.local/bin/pi-port"
