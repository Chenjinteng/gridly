#!/usr/bin/env bash
# scripts/build_web_for_macos.sh
# 把 Flutter web build 产物拷进 macOS .app 的 Resources/web/(P3 commit 11+)
#
# 用法:
#   ./scripts/build_web_for_macos.sh       # release build
#   ./scripts/build_web_for_macos.sh --debug
#
# 流程:
#   1. flutter build web (target lib/web_main.dart)
#   2. rm -rf macos/Runner/Resources/web + 重建空目录
#   3. cp -R build/web/* macos/Runner/Resources/web/
#   4. 提示用户跑 flutter run -d macos
#
# 之后 macOS app 启动时,Platform.script 在 .app/Contents/MacOS/gridly,
# ../Resources/web/ 就是 web 资源位置(server 通过 walk-up Platform.script 找)
#
# 后续 P4+ 可改用 Xcode Run Script build phase 在 build 时自动跑这个脚本
# (避免 dev 阶段每次手动跑)

set -euo pipefail

MODE="--release"
if [ "${1:-}" = "--debug" ]; then
  MODE="--debug"
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_DIR"

echo "== 1. flutter build web =="
flutter build web --target=lib/web_main.dart "$MODE"

echo
echo "== 2. 清空 macos/Runner/Resources/web =="
rm -rf macos/Runner/Resources/web
mkdir -p macos/Runner/Resources/web

echo
echo "== 3. 拷 build/web/* → macos/Runner/Resources/web/ =="
cp -R build/web/* macos/Runner/Resources/web/

echo
echo "✓ Done. 资源数: $(ls -1 macos/Runner/Resources/web | wc -l)"
echo
echo "下一步:"
echo "  flutter run -d macos"
echo
echo "注意:Xcode 项目 (macos/Runner.xcodeproj) 第一次需要添加 macos/Runner/Resources/web/"
echo "为 'folder reference'(不是 group),这样整个目录会被 bundle 进 .app。"
echo "如果还没加,可以:"
echo "  open macos/Runner.xcworkspace"
echo "  右键 Runner → Add Files to 'Runner' → 选 macos/Runner/Resources/web → Add as: Folder Reference"
