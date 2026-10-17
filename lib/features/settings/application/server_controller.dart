// lib/features/settings/application/server_controller.dart
// LAN_WEB v2.0.0 P1 Riverpod controller
//
// 职责:
// - 持久化「局域网服务」开关状态(SharedPreferences)
// - 检测当前 WiFi IP(给用户访问的地址)
// - 启停 foreground service(Android 14+ dataSync type)
// - 查询 service 是否在跑(service crash / kill 后 UI 同步)
//
// 详细:
// - docs/LAN_WEB.md P1 拍板 + 实施计划
// - pub.dev/packages/flutter_foreground_task(11.0.3,Dev-hwang / pravera.me)
// - pub.dev/packages/network_info_plus(8.2.2,fluttercommunity)
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/server/gridly_server.dart';
import '../../../core/server/lan_web_task_handler.dart';

const _kLanWebEnabledKey = 'lan_web_enabled';

/// LAN_WEB 状态:enable 持久化 + 当前 WiFi IP + fg service 是否在跑
class LanWebState {
  const LanWebState({
    required this.enabled,
    required this.ip,
    required this.serviceRunning,
  });

  final bool enabled;
  final String? ip;            // 当前 WiFi IP(enabled = true 时显示)
  final bool serviceRunning;   // fg service 是否在跑

  LanWebState copyWith({
    bool? enabled,
    String? ip,
    bool? serviceRunning,
  }) {
    return LanWebState(
      enabled: enabled ?? this.enabled,
      ip: ip ?? this.ip,
      serviceRunning: serviceRunning ?? this.serviceRunning,
    );
  }

  /// 用户访问 URL(enabled + serviceRunning + ip 都齐才非空)
  String? get accessUrl {
    if (!enabled || !serviceRunning || ip == null) return null;
    return 'http://$ip:$kLanWebPort';
  }

  static const initial =
      LanWebState(enabled: false, ip: null, serviceRunning: false);
}

/// LAN_WEB 控制器
///
/// 注意:
/// - addTaskDataCallback 在 init() 之后才生效,所以 dispose 时必须 remove
/// - isRunningService 是异步查询,UI 显示可能有 1-2 秒延迟
class LanWebController extends StateNotifier<LanWebState> {
  LanWebController() : super(LanWebState.initial) {
    _init();
  }

  Future<void> _init() async {
    // 1. 加载持久化的 enable 状态
    final prefs = await SharedPreferences.getInstance();
    final savedEnabled = prefs.getBool(_kLanWebEnabledKey) ?? false;

    // 2. 检测当前 WiFi IP
    String? ip;
    try {
      ip = await NetworkInfo().getWifiIP();
    } catch (e) {
      // network_info_plus 在没有 WiFi / 飞行模式会抛
      debugPrint('NetworkInfo.getWifiIP error: $e');
    }

    // 3. 检测 fg service 当前是否在跑(可能上次没正确停)
    final isRunning = await FlutterForegroundTask.isRunningService;

    // 4. 注册 service → main 通信回调(P1 不用,但保留接口给 P2)
    FlutterForegroundTask.addTaskDataCallback(_onServiceData);

    state = LanWebState(
      enabled: savedEnabled && isRunning,
      ip: ip,
      serviceRunning: isRunning,
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
      await _ensureNotificationPermission();
      serviceRunning = await _startService();
    } else {
      serviceRunning = !(await _stopService());
    }

    state = state.copyWith(enabled: enabled, serviceRunning: serviceRunning);
  }

  Future<bool> _ensureNotificationPermission() async {
    // Android 13+ 需要通知权限(fg service 常驻通知必显示)
    if (!await FlutterForegroundTask.checkNotificationPermission()) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    return FlutterForegroundTask.checkNotificationPermission();
  }

  Future<bool> _startService() async {
    // 初始化 fg_task 选项(必须在 startService 前调一次)
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
        // P1 不需要定时任务(实时性策略是手动刷新);保留 repeat 兜底
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,           // 开机不自启(自用可控开关)
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,           // HTTP server IO 密集,不必 wake CPU
        allowWifiLock: true,            // 保持 WiFi 唤醒,避免锁屏断流
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'gridly 局域网服务',
      notificationText: state.accessUrl ?? '正在启动…',
      notificationIcon: null,
      callback: lanWebStartCallback,
    );

    // ServiceRequestResult.success / failed / ignore
    return result == ServiceRequestSuccess;
  }

  Future<bool> _stopService() async {
    await FlutterForegroundTask.stopService();
    // 重新查询真实状态(避免 UI 短暂显示错)
    await Future.delayed(const Duration(milliseconds: 200));
    final stillRunning = await FlutterForegroundTask.isRunningService;
    return stillRunning;
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onServiceData);
    super.dispose();
  }
}

/// Provider 入口
final lanWebControllerProvider =
    StateNotifierProvider<LanWebController, LanWebState>((ref) {
  return LanWebController();
});