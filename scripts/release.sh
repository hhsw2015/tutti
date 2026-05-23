#!/usr/bin/env bash
# Tutti release: bump version → build → sign → notarize → staple → zip → publish to GitHub Releases.
#
# Prereqs (one-time):
#   xcrun notarytool store-credentials "tutti-notary" \
#     --apple-id <your-apple-id> --team-id RFW398ARA9 --password <app-specific-password>
#   gh auth login   (must be the account that owns BarryBarrywu/tutti)
#
# Usage:
#   ./scripts/release.sh           # release current version from project.yml
#   ./scripts/release.sh 0.1.1     # bump version first, then release

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

SCHEME="Tutti"
CONFIG="Release"
BUILD_DIR="$PROJECT_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/Tutti.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/Tutti.app"
KEYCHAIN_PROFILE="tutti-notary"
SIGN_IDENTITY="Developer ID Application: BaoLin Wu (RFW398ARA9)"
GH_REPO="BarryBarrywu/tutti"

# ---------- 1. Version handling ----------
NEW_VERSION="${1:-}"
if [ -n "$NEW_VERSION" ]; then
  if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must be x.y.z (got: $NEW_VERSION)" >&2
    exit 1
  fi
  echo "==> Bumping version to $NEW_VERSION in project.yml"
  /usr/bin/sed -i '' \
    -e "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$NEW_VERSION\"/" \
    -e "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$NEW_VERSION\"/" \
    project.yml
  xcodegen generate
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Tutti/Info.plist)"
TAG="v$VERSION"
ZIP_PATH="$BUILD_DIR/Tutti-${VERSION}.zip"

echo "==> Tutti $VERSION → tag $TAG → repo $GH_REPO"

# ---------- 2. Pre-flight ----------
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not installed. brew install gh" >&2; exit 1
fi
if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on $GH_REPO. Bump version first." >&2; exit 1
fi

# ---------- 3. Build ----------
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archive"
xcodebuild -project Tutti.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  archive

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "FAIL: archive not produced" >&2
  exit 1
fi

echo "==> Export .app"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>RFW398ARA9</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --display --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime"

# ---------- 4. Notarize ----------
echo "==> Zip for notarization"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submit to notarytool (3–10 min)"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Staple ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Repackage stapled .app"
rm "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ---------- 5. Publish to GitHub Releases ----------
echo "==> Publish GitHub release $TAG"
gh release create "$TAG" "$ZIP_PATH" \
  --repo "$GH_REPO" \
  --title "Tutti $VERSION" \
  --generate-notes \
  --latest

RELEASE_URL="$(gh release view "$TAG" --repo "$GH_REPO" --json url -q .url)"

echo ""
echo "Done."
echo "  Local artifact: $ZIP_PATH"
echo "  GitHub release: $RELEASE_URL"
echo ""
if [ -n "$NEW_VERSION" ]; then
  echo "Reminder: commit the version bump in project.yml + Tutti/Info.plist"
fi
