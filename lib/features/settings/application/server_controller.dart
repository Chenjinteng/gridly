// lib/features/settings/application/server_controller.dart
// LAN_WEB v2.0.0 P1 Riverpod controller
//
// 职责:
// - 持久化「局域网服务」开关状态(SharedPreferences)
// - 检测当前 WiFi IP(给用户访问的地址)
// - 启停 foreground service(Android 14+ dataSync type)
// - 查询 service 是否在跑(service crash / kill 后 UI 同步)
//
// 注意:
// - flutter_foreground_task 只支持 Android / iOS,macOS dev 时调用会 throw
// - 2026-10-17 平台守卫 Platform.isAndroid,避免 macOS dev 崩
//
// 详细:
// - docs/LAN_WEB.md P1 拍板 + 实施计划
// - pub.dev/packages/flutter_foreground_task(11.0.3,Dev-hwang / pravera.me)
// - pub.dev/packages/network_info_plus(^7.0.0,fluttercommunity,2026-10-17 降版本解 win32 冲突)
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/server/auth.dart';
import '../../../core/server/gridly_server.dart';
import '../../../core/server/lan_web_task_handler.dart';

const _kLanWebEnabledKey = 'lan_web_enabled';

/// LAN_WEB 状态:enable 持久化 + 当前 WiFi IP + service 是否在跑
class LanWebState {
  const LanWebState({
    required this.enabled,
    required this.ip,
    required this.serviceRunning,
    required this.devMode,
  });

  final bool enabled;
  final String? ip;            // 当前 WiFi IP(enabled = true 时显示)
  final bool serviceRunning;   // 服务是否在跑(fg_service on Android,direct server on macOS dev)
  final bool devMode;          // dev mode = 当前平台不支持 fg_task(macOS),走 direct server 路径

  LanWebState copyWith({
    bool? enabled,
    String? ip,
    bool? serviceRunning,
    bool? devMode,
  }) {
    return LanWebState(
      enabled: enabled ?? this.enabled,
      ip: ip ?? this.ip,
      serviceRunning: serviceRunning ?? this.serviceRunning,
      devMode: devMode ?? this.devMode,
    );
  }

  /// 用户访问 URL(enabled + serviceRunning 必齐,ip 可 fallback)
  ///
  /// ip 优先级:
  /// 1. NetworkInfo.getWifiIP() 真实 IP(同 WiFi 设备可访问)
  /// 2. dev mode + ip == null → 127.0.0.1(macOS dev 本机浏览器兜底)
  /// 3. 都拿不到 → null(生产模式 UI 不显示 URL)
  String? get accessUrl {
    if (!enabled || !serviceRunning) return null;
    final displayIp = ip ?? (devMode ? '127.0.0.1' : null);
    if (displayIp == null) return null;
    return 'http://$displayIp:$kLanWebPort';
  }

  static const initial = LanWebState(
    enabled: false,
    ip: null,
    serviceRunning: false,
    devMode: false,
  );
}

/// LAN_WEB 控制器
///
/// 注意:
/// - addTaskDataCallback 在 init() 之后才生效,所以 dispose 时必须 remove
/// - isRunningService 是异步查询,UI 显示可能有 1-2 秒延迟
/// - macOS dev 模式不支持 fg_task,走 direct shelf server 路径(不经 fg_task)
///   让 macOS 也能 toggle 测试 server 部分;fg_service 那块(锁屏/常驻通知)必须 Android 真机测
class LanWebController extends StateNotifier<LanWebState> {
  LanWebController(this._db) : super(LanWebState.initial) {
    _init();
  }

  /// AppDatabase 注入(startGridlyServer 需要)
  final AppDatabase _db;

  /// 当前平台是否支持 fg_task(仅 Android / iOS,macOS 不支持)
  /// false 时走 dev mode:直接 startGridlyServer() / stopGridlyServer()
  static bool get _isSupportedPlatform =>
      Platform.isAndroid || Platform.isIOS;

  Future<void> _init() async {
    final supported = _isSupportedPlatform;
    final devMode = !supported;

    // 1. 加载持久化的 enable 状态
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool(_kLanWebEnabledKey) ?? false;

    // 2. 检测当前 WiFi IP(任何平台都试,macOS dev 也能显示)
    String? ip;
    try {
      ip = await NetworkInfo().getWifiIP();
    } catch (e) {
      // network_info_plus 在没 WiFi / 飞行模式会抛
      debugPrint('NetworkInfo.getWifiIP error: $e');
    }

    // 3. 检测服务是否在跑
    //   - supported:查 fg_task 的真实状态
    //   - devMode:看持久化的 enable(简化处理,init 时假设上次状态有效)
    bool isRunning = false;
    if (supported) {
      isRunning = await FlutterForegroundTask.isRunningService;
      // 4. 注册 service → main 通信回调(P1 不用,但保留接口给 P2)
      FlutterForegroundTask.addTaskDataCallback(_onServiceData);
    } else {
      // dev mode:无 fg_task,init 时无法查 server 真实状态,后续 toggle 即可
      isRunning = false;
    }

    state = LanWebState(
      enabled: savedEnabled && isRunning,
      ip: ip,
      serviceRunning: isRunning,
      devMode: devMode,
    );
  }

  void _onServiceData(Object data) {
    // P1 placeholder;P2 接收 fg service 推过来的数据库状态变化
  }

  /// 用户切换开关
  Future<void> setEnabled(bool enabled) async {
    if (enabled == state.enabled) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLanWebEnabledKey, enabled);

    bool serviceRunning;
    if (enabled) {
      if (state.devMode) {
        // dev mode (macOS):直接起 shelf server,绕开 fg_task
        serviceRunning = await _startServerDirect();
      } else {
        await _ensureNotificationPermission();
        serviceRunning = await _startService();
      }
    } else {
      if (state.devMode) {
        await stopGridlyServer();
        serviceRunning = false;
      } else {
        serviceRunning = !(await _stopService());
      }
    }

    state = state.copyWith(enabled: enabled, serviceRunning: serviceRunning);
  }

  /// dev mode 启动:直接调 startGridlyServer()(跟 fg_service 路径同一个 server 实现)
  /// macOS dev 上能跑通 shelf HTTP server,让浏览器访问 http://127.0.0.1:8123/ 验 JSON
  Future<bool> _startServerDirect() async {
    try {
      await startGridlyServer(db: _db);
      return true;
    } catch (e) {
      debugPrint('dev mode startGridlyServer error: $e');
      return false;
    }
  }

  Future<NotificationPermission> _ensureNotificationPermission() async {
    // Android 13+ 需要通知权限(fg service 常驻通知必显示)
    // checkNotificationPermission() 返回 enum,跟 .granted 比较
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    return FlutterForegroundTask.checkNotificationPermission();
  }

  /// Android 路径:start fg_service (keep-alive) + start HTTP server (in main isolate)
  /// - fg_service 用 lanWebKeepAliveCallback,只保活 + 显示通知,不跑 server
  /// - HTTP server 跑 main isolate,直接 DB 访问,无 IPC 复杂度
  /// - 失败回滚:server 起不来就 stopService
  Future<bool> _startService() async {
    // 1. 初始化 fg_task 选项(必须在 startService 前调一次)
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'gridly_lan_web',
        channelName: '局域网 Web 服务',
        channelDescription: '开启后,同 WiFi 电脑可访问 gridly 账本',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 60s 心跳(KeepAliveTaskHandler.onRepeatEvent),保活 + 未来加健康检查
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: true,
      ),
    );

    // 2. start fg_service (keep-alive)
    final fgResult = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'gridly 局域网服务',
      notificationText: state.accessUrl ?? '正在启动…',
      notificationIcon: null,
      callback: lanWebKeepAliveCallback,
    );

    if (fgResult is! ServiceRequestSuccess) {
      debugPrint('fg_service startService failed: $fgResult');
      return false;
    }

    // 3. start HTTP server in main isolate
    try {
      await startGridlyServer(db: _db);
      return true;
    } catch (e) {
      // server 起不来就回滚 fg_service
      debugPrint('startGridlyServer failed, rolling back fg_service: $e');
      await FlutterForegroundTask.stopService();
      return false;
    }
  }

  /// Android 路径:stop HTTP server first,then stop fg_service
  /// - 反序:server 先关(释放端口),再 stop fg_service(关闭常驻通知 + 释放保活)
  Future<bool> _stopService() async {
    // 1. stop HTTP server first
    await stopGridlyServer();
    // 2. stop fg_service
    await FlutterForegroundTask.stopService();
    // 3. 重新查询真实状态
    await Future.delayed(const Duration(milliseconds: 200));
    return await FlutterForegroundTask.isRunningService;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    super.dispose();
  }

  // ====== P2 鉴权 / sessions 操作(给 UI modal 用)======

  /// 拿当前 6 位配对码(过期或无则重新生成)
  PairingCode getCurrentPairingCode() => pairingCodeStore.current();

  /// 强制刷新 6 位配对码(用户点"刷新"按钮时调)
  PairingCode refreshPairingCode() => pairingCodeStore.refresh();

  /// 列出已配对的 active sessions
  List<ActiveSession> listActiveSessions() => sessionStore.list();

  /// 撤销某 session(返回是否真撤销了;异步,await 写完 prefs)
  Future<bool> revokeSession(String token) => sessionStore.revoke(token);
}

/// Provider 入口
final lanWebControllerProvider =
    StateNotifierProvider<LanWebController, LanWebState>((ref) {
  return LanWebController(ref.read(databaseProvider));
});