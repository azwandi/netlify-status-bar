#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NetlifyStatusBar"
RELEASE_TAG="${1:-}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
APPCAST_URL="${APPCAST_URL:-https://azwandi.github.io/netlify-status-bar/appcast.xml}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-}"
ARCHIVE_PATH="$ROOT_DIR/build/${APP_NAME}.xcarchive"
UPDATES_DIR="$ROOT_DIR/build/updates"
ZIP_NAME="${APP_NAME}-${RELEASE_TAG}.zip"

if [[ -z "$RELEASE_TAG" ]]; then
  echo "Usage: $0 <release-tag>" >&2
  exit 1
fi

if [[ -z "$SPARKLE_PRIVATE_KEY" ]]; then
  echo "SPARKLE_PRIVATE_KEY must be set to generate a signed appcast." >&2
  exit 1
fi

if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="https://github.com/azwandi/netlify-status-bar/releases/download/${RELEASE_TAG}/"
fi

SPARKLE_BIN_DIR="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/artifacts/sparkle/Sparkle/bin' | head -n 1)"
if [[ -z "$SPARKLE_BIN_DIR" ]]; then
  echo "Sparkle tools not found. Run 'xcodegen generate' and build the project once first." >&2
  exit 1
fi

rm -rf "$ARCHIVE_PATH" "$UPDATES_DIR"
mkdir -p "$UPDATES_DIR"

cd "$ROOT_DIR"
xcodegen generate
xcodebuild archive \
  -scheme "$APP_NAME" \
  -project "$ROOT_DIR/${APP_NAME}.xcodeproj" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  SPARKLE_APPCAST_URL="$APPCAST_URL" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"

APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UPDATES_DIR/$ZIP_NAME"

if [[ -n "$RELEASE_NOTES_FILE" ]]; then
  cp "$RELEASE_NOTES_FILE" "$UPDATES_DIR/${ZIP_NAME%.zip}.md"
fi

echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN_DIR/generate_appcast" \
  --ed-key-file - \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/azwandi/netlify-status-bar" \
  --embed-release-notes \
  -o appcast.xml \
  "$UPDATES_DIR"

mkdir -p "$ROOT_DIR/docs"
cp "$UPDATES_DIR/appcast.xml" "$ROOT_DIR/docs/appcast.xml"
touch "$ROOT_DIR/docs/.nojekyll"

echo "Created update archive: $UPDATES_DIR/$ZIP_NAME"
echo "Updated appcast: $ROOT_DIR/docs/appcast.xml"
