#!/usr/bin/env bash
# Publishes PhoneBox <version> on GitHub Releases: make release VERSION=0.2.0
#
# From a clean main that matches origin/main, this sets the version in Resources/Info.plist, runs the
# tests, builds dist/PhoneBox-<version>.zip, commits "Release <version>", tags v<version>, pushes both in one atomic push,
# creates a draft GitHub release with generated notes, uploads the zip as PhoneBox.zip (the stable name
# install.sh downloads) and only then publishes it. Works while the repository is private too; install.sh only works while it is public.
#
# Token: $GITHUB_TOKEN if set, otherwise the GitHub CLI's (`gh auth token`), otherwise the github.com credential git
# already uses (Keychain).
# DRY_RUN=1 does every check and build but changes nothing in git or on GitHub.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
VERSION="${1:-}"
DRY_RUN="${DRY_RUN:-}"

fail() { echo "error: $*" >&2; exit 1; }
say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "usage: make release VERSION=x.y.z"
cd "$ROOT"

# owner/name from the origin URL (https or ssh).
REPO="$(git remote get-url origin | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || fail "origin is not a GitHub repository: $(git remote get-url origin)"

[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
[ "$(git branch --show-current)" = "main" ] || fail "switch to main first"
git fetch --quiet --tags origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main is not the same as origin/main; pull or push first"
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || fail "tag v$VERSION already exists"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
say "PhoneBox $CURRENT (build $BUILD) -> $VERSION (build $((BUILD + 1)))"

# Until "Release <version>" is committed, any exit (a dry run, a failed test or build, no token) puts Info.plist back.
restore_plist() { git checkout -- "$PLIST"; }
trap restore_plist EXIT
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $((BUILD + 1))" "$PLIST"

say "Testing"
make test >/dev/null
say "Building"
make dist >/dev/null
ZIP="$ROOT/dist/PhoneBox-$VERSION.zip"
[ -f "$ZIP" ] || fail "$ZIP was not built"

if [ -n "$DRY_RUN" ]; then
  say "Dry run: built $ZIP; would commit, tag v$VERSION, push and publish to $REPO"
  exit 0
fi

TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v gh >/dev/null; then
  TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | GIT_TERMINAL_PROMPT=0 git credential fill 2>/dev/null | sed -n 's/^password=//p')"
fi
[ -n "$TOKEN" ] || fail "no GitHub token: set GITHUB_TOKEN or sign in to github.com with git"

say "Committing and tagging v$VERSION"
git commit --quiet -m "Release $VERSION" -- "$PLIST"
trap - EXIT
# Until the push succeeds, the commit and the tag exist only here: say how to undo them before running this again.
local_only() {
  echo "error: the commit \"Release $VERSION\" and the tag v$VERSION exist only locally; undo them with" \
    "\`git tag -d v$VERSION && git reset --hard HEAD~1\` before running this again." >&2
}
trap local_only EXIT
git tag -a "v$VERSION" -m "PhoneBox $VERSION"
git push --atomic --quiet origin main "v$VERSION"
trap - EXIT

# From here until the release is published, a failure leaves a tag on GitHub without a release: say how to go on.
unpublished() {
  echo "error: the tag v$VERSION is on GitHub without a published release; finish or delete the draft at" \
    "https://github.com/$REPO/releases, or remove the tag with" \
    "\`git push --delete origin v$VERSION && git tag -d v$VERSION\` and run this again." >&2
}
trap unpublished EXIT

# The token goes to curl as a config on stdin, so it never shows in curl's arguments (ps).
api() {
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" |
    curl -fsS -K - -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

say "Creating the draft GitHub release"
BODY="$(cat <<EOF
Install or update with one command in Terminal:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash
\`\`\`

Or download PhoneBox.zip below, unzip it, move PhoneBox.app to /Applications and run
\`xattr -dr com.apple.quarantine /Applications/PhoneBox.app\` before opening it.

Needs a Mac with Apple silicon and macOS 14 or later, and an iPhone with its USB cable. Nothing is installed on the
iPhone: the dashboard opens in Safari.
EOF
)"
PAYLOAD="$(TAG="v$VERSION" NAME="PhoneBox $VERSION" BODY="$BODY" /usr/bin/python3 -c \
  'import json, os; print(json.dumps({"tag_name": os.environ["TAG"], "name": os.environ["NAME"], "body": os.environ["BODY"], "generate_release_notes": True, "draft": True}))')"
RELEASE="$(api -X POST "https://api.github.com/repos/$REPO/releases" -d "$PAYLOAD")"
RELEASE_ID="$(printf '%s' "$RELEASE" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["id"])')"

say "Uploading PhoneBox.zip"
api -X POST -H "Content-Type: application/zip" --data-binary "@$ZIP" \
  "https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets?name=PhoneBox.zip" >/dev/null

# Published only now, so releases/latest/download/PhoneBox.zip never points at a release without its zip.
say "Publishing the release"
PUBLISHED="$(api -X PATCH "https://api.github.com/repos/$REPO/releases/$RELEASE_ID" -d '{"draft":false}')"
trap - EXIT
RELEASE_URL="$(printf '%s' "$PUBLISHED" | /usr/bin/python3 -c 'import json, sys; print(json.load(sys.stdin)["html_url"])')"
say "Published $RELEASE_URL"
