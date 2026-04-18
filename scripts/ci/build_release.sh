#!/bin/zsh

set -euo pipefail

: "${APP_NAME:=Scratchpad}"
: "${SCHEME:=Scratchpad}"
: "${PROJECT_PATH:=Scratchpad.xcodeproj}"
: "${CONFIGURATION:=Release}"
: "${VERSION:?VERSION is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY is required}"
: "${SPARKLE_PRIVATE_ED_KEY:?SPARKLE_PRIVATE_ED_KEY is required}"

ROOT_DIR="${ROOT_DIR:-$(pwd)}"
ARCHIVE_PATH="$RUNNER_TEMP/$APP_NAME.xcarchive"
EXPORT_PATH="$RUNNER_TEMP/export"
DMG_STAGING_PATH="$RUNNER_TEMP/dmg-staging"
ARTIFACTS_DIR="$RUNNER_TEMP/release-assets"
SPARKLE_DIR="$RUNNER_TEMP/Sparkle"
SPARKLE_KEY_FILE="$RUNNER_TEMP/sparkle_private_ed25519"
DMG_PATH="$ARTIFACTS_DIR/$APP_NAME.dmg"
APPCAST_PATH="$ARTIFACTS_DIR/appcast.xml"
RELEASE_NOTES_PATH="$ARTIFACTS_DIR/$APP_NAME.dmg.md"
TAG="v$VERSION"
DOWNLOAD_URL="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/$APP_NAME.dmg"

echo "$SPARKLE_PRIVATE_ED_KEY" > "$SPARKLE_KEY_FILE"
chmod 600 "$SPARKLE_KEY_FILE"

mkdir -p "$ARTIFACTS_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_STAGING_PATH"

echo "Updating build versions to $VERSION"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/g" "$ROOT_DIR/$PROJECT_PATH/project.pbxproj"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $VERSION/g" "$ROOT_DIR/$PROJECT_PATH/project.pbxproj"

echo "Archiving app"
xcodebuild \
  -project "$ROOT_DIR/$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  archive

echo "Exporting signed app"
xcodebuild \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -exportArchive

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
  echo "Notarizing exported app"
  ditto -c -k --keepParent "$EXPORT_PATH/$APP_NAME.app" "$RUNNER_TEMP/$APP_NAME.zip"
  xcrun notarytool submit "$RUNNER_TEMP/$APP_NAME.zip" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait
  xcrun stapler staple "$EXPORT_PATH/$APP_NAME.app"
  xcrun stapler validate "$EXPORT_PATH/$APP_NAME.app"
fi

echo "Creating DMG"
brew install create-dmg
mkdir -p "$DMG_STAGING_PATH"
ditto "$EXPORT_PATH/$APP_NAME.app" "$DMG_STAGING_PATH/$APP_NAME.app"
create-dmg \
  --volname "$APP_NAME" \
  --volicon "$EXPORT_PATH/$APP_NAME.app/Contents/Resources/AppIcon.icns" \
  --window-pos 200 120 \
  --window-size 620 320 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 175 150 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 445 150 \
  --hdiutil-quiet \
  "$DMG_PATH" \
  "$DMG_STAGING_PATH/"

echo "Preparing Sparkle release notes"
cat > "$RELEASE_NOTES_PATH" <<EOF
# Scratchpad $VERSION

- Automated release from \`main\`
- Commit: \`${GITHUB_SHA:-unknown}\`
EOF

echo "Building Sparkle tools"
git clone --depth=1 --branch 2.9.1 https://github.com/sparkle-project/Sparkle.git "$SPARKLE_DIR"
make -C "$SPARKLE_DIR" release

GENERATE_APPCAST_BIN="$(find "$SPARKLE_DIR" -type f -name generate_appcast -perm -111 | head -n 1)"
if [[ -z "$GENERATE_APPCAST_BIN" ]]; then
  echo "Unable to locate Sparkle generate_appcast binary" >&2
  exit 1
fi

echo "Generating appcast"
"$GENERATE_APPCAST_BIN" "$ARTIFACTS_DIR" --ed-key-file "$SPARKLE_KEY_FILE"

python3 <<PY
from pathlib import Path

appcast_path = Path("$APPCAST_PATH")
xml = appcast_path.read_text()
xml = xml.replace("file://$DMG_PATH", "$DOWNLOAD_URL")
xml = xml.replace("$DMG_PATH", "$DOWNLOAD_URL")
appcast_path.write_text(xml)
PY

echo "Verifying release artifacts"
[[ -f "$DMG_PATH" ]]
[[ -f "$APPCAST_PATH" ]]

echo "Artifacts ready in $ARTIFACTS_DIR"
