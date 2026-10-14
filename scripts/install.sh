#!/bin/bash
# Installs the latest Remember Who You Are release (including alpha/pre-releases).
set -euo pipefail

APP_NAME="Remember Who You Are.app"
REPO="rckbrcls/remember-who-you-are"
ASSET_PREFIX="RememberWhoYouAre-macos-"
API="https://api.github.com/repos/${REPO}/releases"

VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    -h|--help) echo "Usage: install.sh [--version <version>]"; exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer only supports macOS."; exit 1
fi
if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]; then
  echo "Remember Who You Are needs macOS 26 or later."; exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# /releases/latest ignores pre-releases, so list releases and take the newest match.
RELEASES=$(curl -fsSL -H "Accept: application/vnd.github+json" "${API}?per_page=20")
ASSET_JSON=$(printf "%s" "$RELEASES" | python3 -c '
import json, sys
prefix, version = sys.argv[1], sys.argv[2]
for release in json.load(sys.stdin):
    if release.get("draft"):
        continue
    tag = release.get("tag_name", "").lstrip("v")
    if version and tag != version:
        continue
    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if name.startswith(prefix) and name.endswith(".zip"):
            print(json.dumps({
                "name": name,
                "url": asset["browser_download_url"],
                "size": asset["size"],
                "digest": asset.get("digest", ""),
                "tag": release["tag_name"],
            }))
            sys.exit(0)
print("ERROR: no matching release asset found.", file=sys.stderr)
sys.exit(1)
' "$ASSET_PREFIX" "$VERSION")

field() { printf "%s" "$ASSET_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
NAME=$(field name); URL=$(field url); SIZE=$(field size); DIGEST=$(field digest); TAG=$(field tag)

echo "Downloading Remember Who You Are ${TAG}..."
ZIP="$TMP_DIR/$NAME"
curl -fL "$URL" -o "$ZIP"

if [ "$(stat -f%z "$ZIP")" -ne "$SIZE" ]; then
  echo "Downloaded file size mismatch."; exit 1
fi
if [ "${DIGEST#sha256:}" != "$DIGEST" ]; then
  if [ "$(shasum -a 256 "$ZIP" | awk '{print $1}')" != "${DIGEST#sha256:}" ]; then
    echo "Downloaded file digest does not match the GitHub Release asset."; exit 1
  fi
fi

ditto -x -k "$ZIP" "$TMP_DIR/extract"
APP="$TMP_DIR/extract/$APP_NAME"
[ -d "$APP" ] || { echo "$APP_NAME not found in the archive."; exit 1; }

if [ -w /Applications ]; then TARGET="/Applications"; else TARGET="$HOME/Applications"; fi
mkdir -p "$TARGET"

pkill -x RememberWhoYouAre 2>/dev/null || true
rm -rf "$TARGET/$APP_NAME"
ditto "$APP" "$TARGET/$APP_NAME"
xattr -dr com.apple.quarantine "$TARGET/$APP_NAME" 2>/dev/null || true

echo "Installed to $TARGET/$APP_NAME"
open "$TARGET/$APP_NAME"
