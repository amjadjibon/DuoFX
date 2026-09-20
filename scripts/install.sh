#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} == --help || $# -gt 2 ]]; then
  printf 'Usage: %s [dmg-path] [installation-directory]\nDefaults: build/DuoFX.dmg /Applications\n' "$0"
  exit 0
fi

dmg_path=${1:-build/DuoFX.dmg}
install_dir=${2:-/Applications}
if [[ ! -f "$dmg_path" ]]; then
  printf 'DMG not found: %s\nRun scripts/package.sh first.\n' "$dmg_path" >&2
  exit 1
fi
mkdir -p "$install_dir"
install_dir=$(cd "$install_dir" && pwd)
if [[ ! -w "$install_dir" ]]; then
  printf 'Cannot write to %s. Use: bash scripts/install.sh "%s" "$HOME/Applications"\n' "$install_dir" "$dmg_path" >&2
  exit 1
fi

mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/duofx-install.XXXXXX")
staging_dir=$(mktemp -d "$install_dir/.duofx-install.XXXXXX")
destination="$install_dir/DuoFX.app"
mounted=false
installed=false
cleanup() {
  # Restore the previous app if replacement failed after moving it aside.
  if [[ "$installed" == false && -d "$staging_dir/Previous.app" && ! -e "$destination" ]]; then
    mv "$staging_dir/Previous.app" "$destination"
  fi
  if [[ "$mounted" == true ]]; then hdiutil detach "$mount_dir" -quiet || true; fi
  # Never recursively remove the mount point: it may still contain a mounted disk.
  rmdir "$mount_dir" 2>/dev/null || true
  rm -rf "$staging_dir"
}
trap cleanup EXIT

hdiutil attach "$dmg_path" -readonly -nobrowse -mountpoint "$mount_dir" -quiet
mounted=true
source_app="$mount_dir/DuoFX.app"
if [[ ! -d "$source_app" || -L "$destination" || ( -e "$destination" && ! -d "$destination" ) ]]; then
  printf 'The image must contain DuoFX.app and the destination must be an app directory.\n' >&2
  exit 1
fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")
if [[ "$bundle_id" != com.amjadjibon.duofx ]]; then
  printf 'The image does not contain the expected DuoFX application.\n' >&2
  exit 1
fi
if [[ -d "$destination" ]]; then
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
  if [[ "$existing_id" != "$bundle_id" ]]; then
    printf 'An unrelated app already exists at %s; choose another installation directory.\n' "$destination" >&2
    exit 1
  fi
fi
codesign --verify --deep --strict "$source_app"
ditto "$source_app" "$staging_dir/DuoFX.app"
codesign --verify --deep --strict "$staging_dir/DuoFX.app"

# Ask the running app to quit so its coordinator stops capture and closes HID handles.
xcrun swift scripts/quit-running-app.swift
if [[ -d "$destination" ]]; then mv "$destination" "$staging_dir/Previous.app"; fi
mv "$staging_dir/DuoFX.app" "$destination"
installed=true
open "$destination"
printf 'Installed and launched %s\nClick the DuoFX folding-laptop icon in the menu bar for Settings, Pause, and Quit.\n' "$destination"
