#!/usr/bin/env bash
# scripts/dev_run_macos.sh
# LAN_WEB dev wrapper:跑 `flutter run -d macos` 时自动设 GRIDLY_WEB_DIR env var
#
# 用法:
#   ./scripts/dev_run_macos.sh                    # default build
#   ./scripts/dev_run_macos.sh --build-web        # 先 build web,再跑
#   ./scripts/dev_run_macos.sh --debug            # debug build
#
# 解决 macOS sandbox 把 executable virtualize 到
# ~/Library/Containers/cn.jinteng.gridly/Data/ 的问题
# (cwd 和 Platform.script 都 walk-up 走不到项目根)
#
# 改用 env var 显式传 web 资源绝对路径,server (P3 commit 12) 会优先用 env
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$PROJECT_DIR"

MODE="--release"
BUILD_FIRST=false
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="--debug" ;;
    --build-web) BUILD_FIRST=true ;;
    *) echo "unknown arg: $arg"; exit 1 ;;
  esac
done

# 1. 如果指定,先 build web
if [ "$BUILD_FIRST" = true ]; then
  echo "== build web =="
  flutter build web --target=lib/web_main.dart "$MODE"
fi

# 2. 检查 build/web 存在
if [ ! -d "build/web" ]; then
  echo "ERROR: build/web 不存在。先跑:"
  echo "  flutter build web --target=lib/web_main.dart"
  echo "或者:"
  echo "  $0 --build-web"
  exit 1
fi

# 3. 设 env var(absolute path 避免任何相对路径问题)
export GRIDLY_WEB_DIR="$PROJECT_DIR/build/web"
echo "GRIDLY_WEB_DIR=$GRIDLY_WEB_DIR"

# P3 commit 19: dev mode 自动起 server(跳过 UI toggle)。UAT 必备。
export GRIDLY_DEV_AUTOSTART=1
echo "GRIDLY_DEV_AUTOSTART=$GRIDLY_DEV_AUTOSTART"

# 4. 跑 macOS app
echo "== flutter run -d macos =="
flutter run -d macos
