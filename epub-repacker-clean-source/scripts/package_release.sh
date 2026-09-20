#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="1.0.0"
APP_NAME="EPUBRepacker"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_NAME="${APP_NAME}-macOS-v${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "==> 1. 构建 Release 应用包..."
./scripts/build_app.sh

echo "==> 2. 使用 ditto 制作安全的 macOS 分发 Zip 压缩包..."
rm -f "$ZIP_PATH"
# ditto preserves macOS file permissions, ad-hoc signatures, and extended attributes
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> 3. 计算 SHA-256 校验和..."
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256"

echo ""
echo "============================================================"
echo "🎉 发布包构建完成！"
echo "发布文件: $ZIP_PATH"
echo "SHA256:   $(cat "$ZIP_PATH.sha256" | awk '{print $1}')"
echo "你可以直接将该 Zip 文件上传至 GitHub Releases。"
echo "============================================================"
