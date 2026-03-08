#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Claude Usage Bar"
BUNDLE_NAME="ClaudeUsageBar"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"

echo "Building $APP_NAME..."

# Build release binary
swift build -c release --package-path "$PROJECT_DIR"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/arm64-apple-macosx/release/$BUNDLE_NAME" "$APP_DIR/Contents/MacOS/$BUNDLE_NAME"

# Copy Info.plist and icon
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc code sign (required for notification permissions)
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Built: $APP_DIR"
echo ""
echo "To install: cp -r \"$APP_DIR\" /Applications/"
echo "To run:     open \"$APP_DIR\""
