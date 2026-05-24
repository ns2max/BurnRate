#!/bin/bash
set -e

APP=BurnRate.app

echo "Building BurnRate..."

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"

xcrun swiftc Sources/main.swift \
    -O \
    -target arm64-apple-macosx12.0 \
    -o "$APP/Contents/MacOS/BurnRate"

echo "Done: $APP"
echo ""
echo "━━━ For accurate real-time % ━━━"
echo "Install the hook so Claude Code reports live rate limit data:"
echo ""
echo "  mkdir -p ~/.config/burnrate"
echo "  cp burnrate-hook.sh ~/.config/burnrate/hook.sh"
echo "  chmod +x ~/.config/burnrate/hook.sh"
echo ""
echo "Then add to ~/.claude/settings.json:"
echo '  "statusLine": {"type":"command","command":"~/.config/burnrate/hook.sh"}'
echo ""
echo "Without the hook, BurnRate estimates from local token data"
echo "(works, but may not match Claude Code'\''s internal rate limit %)."
echo ""
echo "Run:  open $APP"
