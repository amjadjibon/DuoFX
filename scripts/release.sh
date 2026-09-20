#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: scripts/release.sh [vX.Y.Z[-suffix]] [--draft] [--prerelease]
                          [--notes-file PATH] [--dry-run]

Build a fresh Release DMG and upload it with a SHA-256 checksum to GitHub.
The tag defaults to v + CFBundleShortVersionString in DuoFX/Info.plist.
Requires a clean checkout, HEAD pushed to origin, gh authentication, and Xcode.
Existing releases are never overwritten. Existing tags must point to HEAD.

  --draft          Upload a draft instead of publishing immediately.
  --prerelease     Mark as prerelease (automatic for tags with a suffix).
  --notes-file     Use this Markdown file instead of generated release notes.
                   Paths are relative to the repository root.
  --dry-run        Show the plan without building, authenticating, or uploading.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
compatibility_notes() {
  cat <<'EOF'
## Compatibility

- **Apple silicon Macs (M-series, arm64)** running **macOS 14 Sonoma or later**.
- This DMG does **not support Intel Macs**.
- Automatic lid animation requires a **MacBook with a compatible lid-angle sensor**. Sensor availability varies by model; manual preview is available when the sensor is unsupported.
EOF
}
tag=''
notes_file=''
dry_run=false
draft=false
prerelease=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dry-run) dry_run=true ;;
    --draft) draft=true ;;
    --prerelease) prerelease=true ;;
    --notes-file)
      [[ $# -ge 2 && -n "$2" ]] || die '--notes-file needs a path.'
      notes_file=$2; shift ;;
    --*) die "Unknown option: $1" ;;
    *) [[ -z "$tag" ]] || die 'Supply only one release tag.'; tag=$1 ;;
  esac
  shift
done

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' DuoFX/Info.plist)
tag=${tag:-v$version}
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]] || die 'Use a tag such as v0.1.0 or v0.1.0-beta.1.'
[[ "${tag%%-*}" == "v$version" ]] || die "Tag $tag does not match app version $version. Update Info.plist and commit first."
[[ -z "$notes_file" || -r "$notes_file" ]] || die "Cannot read release notes: $notes_file"
if [[ "$tag" == *-* ]]; then prerelease=true; fi
head_commit=$(git rev-parse HEAD)
origin_url=$(git remote get-url origin)
case "$origin_url" in
  git@github.com:*) repository=${origin_url#git@github.com:} ;;
  https://github.com/*) repository=${origin_url#https://github.com/} ;;
  ssh://git@github.com/*) repository=${origin_url#ssh://git@github.com/} ;;
  *) die 'origin must be a github.com repository URL.' ;;
esac
repository=${repository%.git}
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 'Cannot determine owner/repository from origin.'
asset_name="DuoFX-$tag-arm64.dmg"
asset="build/$asset_name"
checksum="$asset.sha256"
release_notes="build/DuoFX-$tag-release-notes.md"
release_command=(gh release create "$tag" "$asset" "$checksum" --repo "$repository"
                 --target "$head_commit" --title "DuoFX $tag" --notes-file "$release_notes")
if [[ -z "$notes_file" ]]; then
  release_command+=(--generate-notes)
fi
if [[ "$draft" == true ]]; then release_command+=(--draft); fi
if [[ "$prerelease" == true ]]; then release_command+=(--prerelease); fi

if [[ "$dry_run" == true ]]; then
  printf 'Build version %s from %s for %s.\n' "$version" "$head_commit" "$repository"
  printf 'Would run: bash scripts/package.sh\n'
  printf 'Would create: %s and %s\n' "$asset" "$checksum"
  printf 'Would run:'; printf ' %q' "${release_command[@]}"; printf '\n'
  printf 'Release description starts with:\n'
  compatibility_notes
  printf 'Dry run only; clean checkout, authentication, remote commit, and tag checks run during release.\n'
  exit 0
fi

[[ -z "$(git status --porcelain)" ]] || die 'Commit or stash pending changes before releasing.'
command -v gh >/dev/null || die 'Install GitHub CLI (gh) and run gh auth login.'
gh auth status --hostname github.com >/dev/null 2>&1 || die 'Run gh auth login --hostname github.com first.'
# A release tag must describe the exact sources packaged below.
gh api "repos/$repository/commits/$head_commit" --silent || die 'Push HEAD to origin before releasing.'
remote_tags=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}")
remote_commit=$(printf '%s\n' "$remote_tags" | awk '
  /\^\{\}$/ { peeled=$1; next } NF { direct=$1 }
  END { print (peeled != "" ? peeled : direct) }')
[[ -z "$remote_commit" || "$remote_commit" == "$head_commit" ]] || die "Remote tag $tag points to another commit."
if gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  die "Release $tag already exists. Choose a new version; releases are not overwritten."
fi

bash scripts/package.sh
[[ "$(git rev-parse HEAD)" == "$head_commit" && -z "$(git status --porcelain)" ]] || die 'Sources changed during the build. Retry from a clean checkout.'
app='build/Build/Products/Release/DuoFX.app'
built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$built_version" == "$version" ]] || die 'Built app version does not match the release.'
codesign --verify --deep --strict "$app"
[[ -s build/DuoFX.dmg ]] || die 'Packaging did not produce a DMG.'
cp build/DuoFX.dmg "$asset"
(cd build && shasum -a 256 "$asset_name") > "$checksum"
# Emit the Homebrew cask for this exact asset so the tap is never hand-edited
# with a stale version or checksum.
sha=$(awk '{print $1}' "$checksum")
sed -e "s/^# Generated by .* Do not edit by hand\.$/# Generated by scripts\/release.sh for $tag. Do not edit by hand./" \
    -e "s/^  version \".*\"$/  version \"${tag#v}\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" Casks/duofx.rb > build/duofx.rb
printf 'Cask for the tap written to build/duofx.rb\n'
# Prepare the body separately so even a notes-file path matching the output is
# read completely before replacement. Keep the finished Markdown for review.
notes_temp=$(mktemp build/.release-notes.XXXXXX)
trap 'rm -f "$notes_temp"' EXIT
compatibility_notes > "$notes_temp"
if [[ -n "$notes_file" ]]; then
  printf '\n\n' >> "$notes_temp"
  cat "$notes_file" >> "$notes_temp"
fi
mv "$notes_temp" "$release_notes"
"${release_command[@]}"
