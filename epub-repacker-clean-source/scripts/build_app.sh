#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> 正在编译 EPUBRepacker Release 独立二进制..."
mkdir -p "$ROOT_DIR/.cache/clang"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.cache/clang"

swift build -c release --disable-sandbox --scratch-path .build/scratch --product EPUBRepackerApp

APP_NAME="EPUBRepacker.app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "==> 构建 macOS .app 目录结构..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "==> 拷贝可执行文件..."
cp "$ROOT_DIR/.build/scratch/release/EPUBRepackerApp" "$MACOS_DIR/EPUBRepacker"
chmod +x "$MACOS_DIR/EPUBRepacker"

echo "==> 处理应用图标..."
ICON_SRC="$ROOT_DIR/Sources/EPUBRepackerApp/Resources/AppIcon.icns"
if [ ! -f "$ICON_SRC" ]; then
    python3 "$ROOT_DIR/scripts/generate_app_icon.py"
fi
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "==> 生成标准 Info.plist..."
cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>EPUBRepacker</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.EPUBRepacker</string>
    <key>CFBundleName</key>
    <string>EPUB Repacker</string>
    <key>CFBundleDisplayName</key>
    <string>EPUB Repacker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>EPUB Electronic Publication</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>org.idpf.epub-container</string>
                <string>com.apple.ibooks.epub</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "==> 本地代码签名 (Ad-Hoc Signing)..."
codesign --force --deep --sign - "$APP_BUNDLE"
touch "$APP_BUNDLE"

echo ""
echo "============================================================"
echo "🎉 成功生成 macOS 独立应用: $APP_BUNDLE"
echo "你可以直接双击运行，或将其拖入 /Applications 文件夹使用！"
echo "============================================================"
