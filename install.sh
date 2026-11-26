#!/bin/bash
# Installs, updates or removes PhoneBox.
#
#   Install or update:  curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash
#   A given version:    curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | PHONEBOX_VERSION=0.1.0 bash
#   Uninstall:          curl -fsSL https://raw.githubusercontent.com/cyesaa/phone-box/main/install.sh | bash -s -- --uninstall
#
# Files downloaded with curl are not quarantined, so macOS does not block the (not notarized) app.
# For testing: PHONEBOX_ZIP=<local zip> uses that file instead of downloading, PHONEBOX_DEST=<dir> installs somewhere
# else (and quits only a PhoneBox running from there), PHONEBOX_NO_OPEN=1 does not start the app afterwards.
set -euo pipefail

REPO="cyesaa/phone-box"
BUNDLE_ID="com.phonebox.PhoneBox"
APP="PhoneBox.app"
ASSET="PhoneBox.zip"

WORK=""
cleanup() { [ -z "$WORK" ] || rm -rf "$WORK"; }
trap cleanup EXIT

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

check_mac() {
  [ "$(uname -s)" = "Darwin" ] || fail "PhoneBox runs only on macOS."
  # uname -m says x86_64 in a shell running under Rosetta, even on Apple silicon.
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ] || fail "PhoneBox needs a Mac with Apple silicon (M1 or later)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 14 ] || fail "PhoneBox needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."
}

# /Applications when it is writable, otherwise ~/Applications (no admin rights needed).
destination() {
  if [ -n "${PHONEBOX_DEST:-}" ]; then
    local dest="$PHONEBOX_DEST"
    # No trailing slashes (messages would show "…//PhoneBox.app"), but "/" stays "/".
    while [ "${#dest}" -gt 1 ] && [ "${dest%/}" != "$dest" ]; do dest="${dest%/}"; done
    echo "$dest"
  elif [ -w /Applications ]; then
    echo /Applications
  else
    echo "$HOME/Applications"
  fi
}

# The pids of the PhoneBox processes to quit before the copy in folder $1 is replaced or removed, one per line.
# Without PHONEBOX_DEST that is every PhoneBox: one running from anywhere else would fight the new one for the port.
# A test install (PHONEBOX_DEST) only quits a copy that runs from that folder, given with trailing slashes or through
# a symlink too (/tmp -> /private/tmp: ps shows the resolved path), and leaves one that runs from elsewhere alone.
# -a: pgrep skips its own ancestors by default, and when PhoneBox runs this script to update itself, PhoneBox is one
# of them.
running_pids() {
  if [ -z "${PHONEBOX_DEST:-}" ]; then
    pgrep -ax PhoneBox || true
    return 0
  fi
  local pid path dir="$1" resolved=""
  while [ "$dir" != "${dir%/}" ]; do dir="${dir%/}"; done
  if [ -d "${dir:-/}" ]; then
    resolved="$(cd "${dir:-/}" 2>/dev/null && pwd -P || true)"
    resolved="${resolved%/}"
  fi
  # The root folder ("/") must not match every path: only the app placed directly in it counts.
  local root=""
  if [ -z "$dir" ]; then root=/PhoneBox.app; fi
  for pid in $(pgrep -ax PhoneBox || true); do
    path="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    if [ -n "$root" ]; then
      case "$path" in "$root"/*) echo "$pid" ;; esac
    else
      case "$path" in "$dir"/* | "${resolved:-$dir}"/*) echo "$pid" ;; esac
    fi
  done
  return 0
}

should_quit() {
  [ -n "$(running_pids "$1")" ]
}

# Quits the PhoneBox processes that running_pids names for folder $1 and waits up to 5 s for them to go.
quit_running_app() {
  local pids pid alive
  pids="$(running_pids "$1")"
  [ -n "$pids" ] || return 0
  say "Quitting the running PhoneBox"
  # One pid per word.
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  for _ in $(seq 1 50); do
    alive=""
    for pid in $pids; do
      if ps -p "$pid" >/dev/null 2>&1; then alive=1; fi
    done
    [ -n "$alive" ] || return 0
    sleep 0.1
  done
  fail "PhoneBox did not quit. Quit it from its menu bar icon and run this again."
}

install() {
  check_mac
  local dest zip
  dest="$(destination)"
  WORK="$(mktemp -d)"

  if [ -n "${PHONEBOX_ZIP:-}" ]; then
    zip="$PHONEBOX_ZIP"
    say "Using $zip"
  else
    local url
    if [ -n "${PHONEBOX_VERSION:-}" ]; then
      url="https://github.com/$REPO/releases/download/v${PHONEBOX_VERSION#v}/$ASSET"
    else
      url="https://github.com/$REPO/releases/latest/download/$ASSET"
    fi
    zip="$WORK/$ASSET"
    say "Downloading PhoneBox ${PHONEBOX_VERSION:-(latest)}"
    curl -fL --progress-bar "$url" -o "$zip" || fail "Download failed: $url (is there such a release?)"
  fi

  ditto -x -k "$zip" "$WORK/unpacked" || fail "The download is not a valid zip."
  [ -d "$WORK/unpacked/$APP" ] || fail "The zip does not contain $APP."
  codesign --verify --deep --strict "$WORK/unpacked/$APP" 2>/dev/null || fail "$APP failed its signature check."

  if should_quit "$dest"; then quit_running_app "$dest"; fi
  mkdir -p "$dest"
  # Copy next to the final place first: if the copy fails (disk full) the old app is still there.
  rm -rf "${dest:?}/.PhoneBox-installing.app"
  ditto "$WORK/unpacked/$APP" "$dest/.PhoneBox-installing.app" || { rm -rf "${dest:?}/.PhoneBox-installing.app"; fail "Could not copy PhoneBox into $dest."; }
  rm -rf "${dest:?}/$APP"
  mv "$dest/.PhoneBox-installing.app" "$dest/$APP"
  # Only browsers add this, but a zip someone passed along may carry it.
  xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

  local version
  version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
  say "Installed PhoneBox $version in $dest"
  if [ -z "${PHONEBOX_NO_OPEN:-}" ]; then
    open "$dest/$APP"
    say "PhoneBox is running: look for the phone icon in the menu bar."
  fi
  echo "    Plug in your iPhone with its cable; the QR code opens the first time. Scan it with the iPhone's camera."
  echo "    If macOS asks whether PhoneBox may accept incoming connections, allow it: that is how the iPhone reaches it."
}

uninstall() {
  local removed=0 dir dirs
  # With PHONEBOX_DEST (a test install) only that copy goes; settings, the pairing key and permissions stay.
  if [ -n "${PHONEBOX_DEST:-}" ]; then
    dirs=("$(destination)")
  else
    dirs=(/Applications "$HOME/Applications")
  fi
  for dir in "${dirs[@]}"; do
    if should_quit "$dir"; then quit_running_app "$dir"; break; fi
  done
  for dir in "${dirs[@]}"; do
    [ -d "$dir/$APP" ] || continue
    rm -rf "${dir:?}/$APP"
    say "Removed $dir/$APP"
    removed=1
  done
  [ "$removed" = 1 ] || say "PhoneBox was not installed in ${dirs[*]}."
  [ -z "${PHONEBOX_DEST:-}" ] || return 0
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
  rm -rf "$HOME/Library/Application Support/PhoneBox" "$HOME/Library/Logs/PhoneBox"
  tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
  say "Removed PhoneBox's settings, pairing key and permissions. On the iPhone, delete its Home Screen icon."
}

case "${1:-}" in
  --uninstall) uninstall ;;
  "") install ;;
  *) fail "Unknown option: $1 (use --uninstall to remove PhoneBox)" ;;
esac
