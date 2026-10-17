// lib/core/server/lan_web_task_handler.dart
// LAN_WEB v2.0.0 P1 foreground service TaskHandler
//
// flutter_foreground_task 11.x 模式:
// - top-level @pragma('vm:entry-point') 回调注册 TaskHandler
// - TaskHandler 跑在 foreground service 的 background isolate
// - 启动 HTTP server 在这个 isolate 里(锁屏 server 仍活)
//
// 详细:
// - docs/LAN_WEB.md P1 拍板
// - pub.dev/packages/flutter_foreground_task(11.0.3, Dev-hwang / pravera.me)
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'gridly_server.dart';

/// foreground service 启动回调(top-level + @pragma('vm:entry-point') 必须)
/// 由 FlutterForegroundTask.startService(callback: lanWebStartCallback) 触发
@pragma('vm:entry-point')
void lanWebStartCallback() {
  FlutterForegroundTask.setTaskHandler(LanWebTaskHandler());
}

/// gridly 局域网服务 TaskHandler
///
/// - onStart:启动 shelf_plus HTTP server(serve 完成后 isolate 持续存活,server 监听端口)
/// - onDestroy:关闭 server 释放端口
/// - onRepeatEvent:P1 无需定时任务,空实现
class LanWebTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // startGridlyServer 内部 await serve(...),返回时 server 已 bind 端口
    // server 在 background isolate 里持续 listen,直到 onDestroy close 它
    // 注意:Android 15 dataSync 限 24h 内 6h(用户拉前台重置),
    //       超时系统会调 onDestroy(isTimeout=true),后续 P4 加 UI 提示
    await startGridlyServer();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // P1 不需要定时任务
    // P2 可能用来推数据更新到 web(但当前实时性策略是手动刷新,这里仍留空)
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await stopGridlyServer();
  }
}