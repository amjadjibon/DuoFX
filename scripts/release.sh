#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: scripts/release.sh vX.Y.Z[-suffix] [--draft] [--prerelease]
                          [--notes-file PATH] [--tap OWNER/REPO] [--dry-run]

Build a fresh Release DMG and upload it with a SHA-256 checksum to GitHub.
The tag is the only source of the version: scripts/configure-version.py stamps
the bundle from it, and the site's version field is set from it too. The bundle
is never hand-edited; the one version the tree does record is Web/site.config.ts,
which this script bumps and commits before tagging, so the tag describes a tree
that advertises the release it is.
Requires a clean checkout, HEAD pushed to origin, gh authentication, and Xcode.
Existing releases are never overwritten. Existing tags must point to HEAD.

  --draft          Upload a draft instead of publishing immediately.
  --prerelease     Mark as prerelease (automatic for tags with a suffix).
  --notes-file     Use this Markdown file instead of generated release notes.
                   Paths are relative to the repository root.
  --tap            Publish the generated Homebrew cask to this tap repository,
                   e.g. amjadjibon/homebrew-tap. Skipped when omitted.
  --dry-run        Show the plan without building, authenticating, or uploading.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
site_config='Web/site.config.ts'
tag_created=false
bump_committed=false
branch_pushed=false
base_commit=''
notes_temp=''
# A single EXIT trap: a second `trap ... EXIT` would silently replace this one
# and the tag would survive a failed release.
cleanup() {
  local status=$?
  if [[ -n "$notes_temp" ]]; then rm -f "$notes_temp"; fi
  # Never leave a local tag behind for a release that did not ship, or the next
  # attempt fails its own "tag already exists" check.
  if [[ "$tag_created" == true && $status -ne 0 ]]; then
    git tag -d "$tag" >/dev/null 2>&1 || true
  fi
  # The bump is committed before the tag, so a failed release would otherwise
  # leave a version claim for something that never shipped. Rewinding is safe
  # only while the commit is local: the checkout was clean before it was made,
  # so base_commit is the exact state to return to. Once pushed, leave it.
  if [[ "$bump_committed" == true && "$branch_pushed" == false && $status -ne 0 ]]; then
    git reset --quiet --hard "$base_commit" >/dev/null 2>&1 || true
  fi
  return $status
}
trap cleanup EXIT
compatibility_notes() {
  cat <<'EOF'
## Compatibility

- **Apple silicon Macs (M-series, arm64)** running **macOS 14 Sonoma or later**.
- This DMG does **not support Intel Macs**.
- Automatic lid animation requires a **MacBook with a compatible lid-angle sensor**. Sensor availability varies by model; manual preview is available when the sensor is unsupported.

## Opening DuoFX the first time

This build is **not notarized**, so macOS refuses it on a plain double-click and reports that DuoFX "is damaged and can't be opened". Nothing is wrong with the download; that is Gatekeeper declining an app Apple has not notarized.

1. Open the DMG and drag **DuoFX** to **Applications**.
2. Right-click `/Applications/DuoFX.app`, choose **Open**, and confirm at the prompt.

Only the first launch needs this. The same thing from Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/DuoFX.app
```

Verify the download against the published `.sha256` first if you would rather check it before removing the quarantine flag.
EOF
}
tag=''
notes_file=''
tap=''
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
    --tap)
      [[ $# -ge 2 && -n "$2" ]] || die '--tap needs a repository, e.g. amjadjibon/homebrew-tap.'
      tap=$2; shift ;;
    --*) die "Unknown option: $1" ;;
    *) [[ -z "$tag" ]] || die 'Supply only one release tag.'; tag=$1 ;;
  esac
  shift
done

[[ -n "$tag" ]] || { usage >&2; exit 2; }
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]] || die 'Use a tag such as v0.1.0 or v0.1.0-beta.1.'
version=${tag#v}
# CFBundleShortVersionString takes at most three dot-separated integers, so the
# bundle carries the numeric core while the release and cask carry the full tag.
marketing=${version%%-*}
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
release_command=()
# Assembled on demand: --target must name the commit the tag ends up on, which
# is not known until the site version bump below has been committed.
build_release_command() {
  release_command=(gh release create "$tag" "$asset" "$checksum" --repo "$repository"
                   --target "$head_commit" --title "DuoFX $tag" --notes-file "$release_notes")
  if [[ -z "$notes_file" ]]; then
    release_command+=(--generate-notes)
  fi
  if [[ "$draft" == true ]]; then release_command+=(--draft); fi
  if [[ "$prerelease" == true ]]; then release_command+=(--prerelease); fi
}

site_version() { awk -F'"' '/^  version: "/ { print $2; exit }' "$site_config"; }

# The published site should name the version it is shipping, so the bump happens
# here rather than by hand after the fact. It is committed before the tag is
# created, which puts it in the tree the tag describes. Already correct is a
# no-op: re-running a release commits nothing.
sync_site_version() {
  [[ -f "$site_config" ]] || die "Missing $site_config; cannot set the site version."
  local current
  current=$(site_version)
  [[ -n "$current" ]] || die "No version field found in $site_config."
  if [[ "$current" == "$version" ]]; then
    printf 'Site version is already %s.\n' "$version"
    return
  fi
  sed -i '' -e "s|^  version: \".*\",\$|  version: \"$version\",|" "$site_config"
  [[ "$(site_version)" == "$version" ]] || die "Could not set the version in $site_config."
  git add "$site_config"
  git commit --quiet -m "chore(web): advertise $version on the site"
  bump_committed=true
  printf 'Site version %s -> %s.\n' "$current" "$version"
}

if [[ "$dry_run" == true ]]; then
  build_release_command
  printf 'Tag %s at %s, then build version %s for %s.\n' "$tag" "$head_commit" "$marketing" "$repository"
  current_site=$([[ -f "$site_config" ]] && site_version || true)
  if [[ "$current_site" == "$version" ]]; then
    printf 'Site version in %s is already %s.\n' "$site_config" "$version"
  else
    printf 'Would set the site version in %s from %s to %s and commit it.\n' \
      "$site_config" "${current_site:-unknown}" "$version"
  fi
  printf 'Would run: bash scripts/package.sh\n'
  printf 'Would create: %s and %s\n' "$asset" "$checksum"
  printf 'Would run:'; printf ' %q' "${release_command[@]}"; printf '\n'
  if [[ -n "$tap" ]]; then
    printf 'Would publish build/duofx.rb to %s as Casks/duofx.rb.\n' "$tap"
  else
    printf 'Would write build/duofx.rb; pass --tap OWNER/REPO to publish it.\n'
  fi
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
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "Tag $tag already exists locally."

# Everything above only inspects; this is the first step that writes. Bump the
# site before tagging so the tag covers it, and remember where to rewind to.
base_commit=$head_commit
sync_site_version
head_commit=$(git rev-parse HEAD)
build_release_command

# The tag is created before the build because it is what the build reads its
# version from. cleanup() removes it again if anything below fails.
git tag -a "$tag" -m "DuoFX $version"
tag_created=true

bash scripts/package.sh
[[ "$(git rev-parse HEAD)" == "$head_commit" && -z "$(git status --porcelain)" ]] || die 'Sources changed during the build. Retry from a clean checkout.'
app='build/Build/Products/Release/DuoFX.app'
built_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$built_version" == "$marketing" ]] || die "Built app version $built_version does not match the tag ($marketing)."
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$build_number" == "$(git rev-list --count HEAD)" ]] || die 'Built bundle version was not stamped from git.'
codesign --verify --deep --strict "$app"
[[ -s build/DuoFX.dmg ]] || die 'Packaging did not produce a DMG.'
cp build/DuoFX.dmg "$asset"
(cd build && shasum -a 256 "$asset_name") > "$checksum"
# Generate the Homebrew cask here rather than keeping a checked-in template, so
# the version and checksum always describe the asset uploaded by this run. The
# tap holds only published casks. #{version} is Ruby interpolation, left literal
# by this heredoc because it contains no shell expansion.
sha=$(awk '{print $1}' "$checksum")
cask="build/duofx.rb"
cat > "$cask" <<CASK
# Generated by scripts/release.sh for $tag. Do not edit by hand.
cask "duofx" do
  version "${tag#v}"
  sha256 "$sha"

  url "https://github.com/$repository/releases/download/v#{version}/DuoFX-v#{version}-arm64.dmg"
  name "DuoFX"
  desc "Menu-bar app that animates the desktop as the MacBook lid closes"
  homepage "https://duofx.amjadjibon.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "DuoFX.app"

  uninstall quit: "com.amjadjibon.duofx"

  zap trash: [
    "~/Library/Preferences/com.amjadjibon.duofx.plist",
    "~/Library/Saved Application State/com.amjadjibon.duofx.savedState",
  ]
end
CASK
# Prepare the body separately so even a notes-file path matching the output is
# read completely before replacement. Keep the finished Markdown for review.
notes_temp=$(mktemp build/.release-notes.XXXXXX)
compatibility_notes > "$notes_temp"
if [[ -n "$notes_file" ]]; then
  printf '\n\n' >> "$notes_temp"
  cat "$notes_file" >> "$notes_temp"
fi
mv "$notes_temp" "$release_notes"
if [[ "$bump_committed" == true ]]; then
  git push --quiet origin HEAD
  branch_pushed=true
fi
git push --quiet origin "$tag"
"${release_command[@]}"

# Publish the cask only after the release exists, so the tap never points at a
# download GitHub is not serving yet.
if [[ -n "$tap" ]]; then
  tap_checkout=$(mktemp -d "${TMPDIR:-/tmp}/duofx-tap.XXXXXX")
  gh repo clone "$tap" "$tap_checkout" -- --depth 1 --quiet
  mkdir -p "$tap_checkout/Casks"
  cp "$cask" "$tap_checkout/Casks/duofx.rb"
  git -C "$tap_checkout" add Casks/duofx.rb
  if git -C "$tap_checkout" diff --quiet --cached; then
    printf 'Cask in %s is already up to date.\n' "$tap"
  else
    git -C "$tap_checkout" commit --quiet -m "duofx ${tag#v}"
    git -C "$tap_checkout" push --quiet -u origin HEAD
    printf 'Installable with: brew install --cask %s/duofx\n' "${tap/homebrew-/}"
  fi
  rm -rf "$tap_checkout"
fi
