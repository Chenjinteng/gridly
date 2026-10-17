// lib/core/server/lan_web_task_handler.dart
// LAN_WEB v2.0.0 P2 keep-alive TaskHandler
//
// P2 架构变更:
// - HTTP server 移到 main isolate(直接 DB 访问,避免 fg_service ↔ main IPC 复杂度)
// - fg_service 改 keep-alive 心跳:不跑 server,只保活进程 + 显示常驻通知
// - lock screen 仍能访问(server 在 main isolate,fg_service 保活进程)
//
// flutter_foreground_task 11.x 模式:
// - top-level @pragma('vm:entry-point') 回调注册 TaskHandler
// - TaskHandler 跑在 foreground service 的 background isolate(本 commit 几乎空)
//
// 详细:
// - docs/LAN_WEB.md P2 拍板(2026-10-17)
// - pub.dev/packages/flutter_foreground_task(11.0.3, Dev-hwang / pravera.me)
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// foreground service 启动回调(top-level + @pragma('vm:entry-point') 必须)
/// 由 FlutterForegroundTask.startService(callback: lanWebKeepAliveCallback) 触发
@pragma('vm:entry-point')
void lanWebKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(KeepAliveTaskHandler());
}

/// gridly 局域网服务 Keep-Alive TaskHandler
///
/// P2 角色:fg_service 只用于
/// 1. 显示「gridly 局域网服务」常驻通知
/// 2. 保持 Android 进程不被系统杀(dataSync type)
/// 3. onRepeatEvent 心跳:60s 一次,未来可用来健康检查 / 更新通知
///
/// 注意:不启动 HTTP server(那在 main isolate 跑)
/// 注意:Android 15 dataSync 限 24h 内 6h,超时系统会调 onDestroy(isTimeout=true)
class KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // No-op:HTTP server 跑在 main isolate
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 60s 心跳,目前 P2 无需做事;P3 / P4 可加健康检查
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // No-op:fg_service stop 时 main isolate 也调 stopGridlyServer
  }
}