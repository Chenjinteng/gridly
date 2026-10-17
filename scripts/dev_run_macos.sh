#!/usr/bin/env bash
# scripts/dev_run_macos.sh
# LAN_WEB dev wrapper:启 macOS app + 自动起 server + 配对码可用
#
# 用法:
#   ./scripts/dev_run_macos.sh                  # release build(默认)
#   ./scripts/dev_run_macos.sh --debug          # debug build
#   ./scripts/dev_run_macos.sh --build-web      # 强制 rebuild web React (web-react/dist)
#
# 一条命令完成:
#   1. (可选) cd web-react && npm run build
#   2. cd macos && xcodebuild ... build (Bundle Web Assets phase 自动拷 dist/ -> .app/Resources/web/)
#   3. 启 .app + GRIDLY_DEV_AUTOSTART=1 (跳过 UI toggle)
#
# 用户只需要 Chrome 开 http://localhost:8123/ + 6 位配对码登录
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_DIR"

MODE="--release"
BUILD_WEB=false
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="--debug" ;;
    --build-web) BUILD_WEB=true ;;
    *) echo "unknown arg: $arg"; exit 1 ;;
  esac
done

# 1. (可选) 重新 build React web → web-react/dist/
if [ "$BUILD_WEB" = true ]; then
  echo "== build React web =="
  (cd web-react && npm run build)
fi

# 2. 检查 web-react/dist 存在(Xcode Bundle Web Assets phase 要读这个)
if [ ! -d "web-react/dist" ]; then
  echo "ERROR: web-react/dist/ 不存在。先跑:"
  echo "  cd web-react && npm install && npm run build"
  echo "或者:"
  echo "  $0 --build-web"
  exit 1
fi

# 3. P3 commit 19: dev mode 自动起 server(跳过 UI toggle)。UAT 必备。
export GRIDLY_DEV_AUTOSTART=1
echo "GRIDLY_DEV_AUTOSTART=$GRIDLY_DEV_AUTOSTART"

# 4. 跑 macOS app(Xcode build 触发 Bundle Web Assets phase 拷 React 静态资源进 .app)
echo "== flutter run -d macos $MODE =="
flutter run -d macos $MODE
