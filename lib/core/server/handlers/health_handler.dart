// lib/core/server/handlers/health_handler.dart
// LAN_WEB v2.0.0 P1 健康检查接口
//
// 浏览器访问 http://192.168.x.x:8123/ 看到的 JSON
// P2 会改为真实数据(交易条数 / 资产余额等)
//
// 跑在 foreground service isolate 里,刻意避免依赖 plugin
// (package_info_plus 等 plugin 在 background isolate 不可靠,
//  避免 plugin 平台通道找不到的踩坑)。版本号 hardcode 在编译时常量,
// 跟 pubspec.yaml 的 version 字段保持一致(由 CI / commit hook 检查)。

/// 跟 pubspec.yaml version 同步(2026-10-17 LAN_WEB P1 起点)
const String kGridlyWebVersion = '2.0.0';
const int kGridlyWebBuild = 113;

/// P1 健康检查响应
///
/// 返回示例:
/// ```json
/// {
///   "name": "gridly web",
///   "version": "2.0.0",
///   "build": 107,
///   "transactions": 0,
///   "phase": "P1 prototype"
/// }
/// ```
Map<String, dynamic> healthHandler() {
  return <String, dynamic>{
    'name': 'gridly web',
    'version': kGridlyWebVersion,
    'build': kGridlyWebBuild,
    // P1 placeholder;P2 接入 transactionsProvider(从 main isolate 传数据进来)
    'transactions': 0,
    'phase': 'P1 prototype',
  };
}