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
  # Bump marketing version. Auto-increment CFBundleVersion (monotonic integer)
  # because Sparkle compares CFBundleVersion to decide which build is newer —
  # if we reuse the marketing string here, "0.2.3" < "4" in string-compare
  # and Sparkle would refuse to update an installed v0.2.2 (CFBundleVersion=4)
  # to v0.2.3 (CFBundleVersion=0.2.3).
  CURRENT_BUILD="$(/usr/bin/awk '/CFBundleVersion:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)"
  NEW_BUILD=$((CURRENT_BUILD + 1))
  /usr/bin/sed -i '' \
    -e "s/CFBundleShortVersionString: \".*\"/CFBundleShortVersionString: \"$NEW_VERSION\"/" \
    -e "s/CFBundleVersion: \".*\"/CFBundleVersion: \"$NEW_BUILD\"/" \
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
if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc not installed (needed to render release notes for Sparkle)." >&2
  echo "  brew install pandoc" >&2
  exit 1
fi
if gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists on $GH_REPO. Bump version first." >&2; exit 1
fi

NOTES_FILE="$PROJECT_ROOT/docs/release-notes/$TAG.md"
if [ ! -f "$NOTES_FILE" ]; then
  echo "Missing release notes: $NOTES_FILE" >&2
  echo "Write user-facing notes (zh + en) before releasing." >&2
  exit 1
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

# ---------- 4.5. Sparkle appcast ----------
SPARKLE_BIN="$PROJECT_ROOT/.sparkle-tools/bin"
if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "Sparkle tools missing at $SPARKLE_BIN/. Re-run: " >&2
  echo "  mkdir -p $PROJECT_ROOT/.sparkle-tools && cd $_ && \\" >&2
  echo "    curl -sL -o sparkle.tar.xz 'https://github.com/sparkle-project/Sparkle/releases/download/2.7.0/Sparkle-2.7.0.tar.xz' && \\" >&2
  echo "    tar xf sparkle.tar.xz" >&2
  exit 1
fi

echo "==> Build appcast pool"
POOL="$BUILD_DIR/appcast-pool"
mkdir -p "$POOL"
cp "$ZIP_PATH" "$POOL/"
# Seed the pool with the existing appcast so generate_appcast only needs to
# add the new entry rather than re-deriving all historical versions.
if [ -f "$PROJECT_ROOT/docs/appcast.xml" ]; then
  cp "$PROJECT_ROOT/docs/appcast.xml" "$POOL/appcast.xml"
fi

# Render the markdown release notes to HTML beside the zip — generate_appcast
# picks up matching <basename>.html files and embeds them as Sparkle's
# <description>, so the update alert shows the actual notes instead of a one-
# liner.
NOTES_HTML="$POOL/Tutti-${VERSION}.html"
pandoc -f markdown -t html "$NOTES_FILE" -o "$NOTES_HTML"

echo "==> generate_appcast (signs with EdDSA key from keychain)"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$GH_REPO/releases/download/$TAG/" \
  --link "https://github.com/$GH_REPO/releases/tag/$TAG" \
  "$POOL"

mkdir -p "$PROJECT_ROOT/docs"
cp "$POOL/appcast.xml" "$PROJECT_ROOT/docs/appcast.xml"

# ---------- 5. Publish to GitHub Releases ----------
echo "==> Publish GitHub release $TAG"
gh release create "$TAG" "$ZIP_PATH" \
  --repo "$GH_REPO" \
  --title "Tutti $VERSION" \
  --notes-file "$NOTES_FILE" \
  --latest

RELEASE_URL="$(gh release view "$TAG" --repo "$GH_REPO" --json url -q .url)"

# ---------- 6. Commit appcast.xml so Sparkle clients see the new release ----------
echo "==> Commit + push docs/appcast.xml"
cd "$PROJECT_ROOT"
git add docs/appcast.xml
if git diff --cached --quiet; then
  echo "  (no appcast change to commit)"
else
  git commit -m "appcast: $VERSION"
  git push origin main
fi

echo ""
echo "Done."
echo "  Local artifact: $ZIP_PATH"
echo "  GitHub release: $RELEASE_URL"
echo "  Appcast:        https://barrybarrywu.github.io/tutti/appcast.xml"
echo ""
if [ -n "$NEW_VERSION" ]; then
  echo "Reminder: commit the version bump in project.yml + Tutti/Info.plist"
fi
