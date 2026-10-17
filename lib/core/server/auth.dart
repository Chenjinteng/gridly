// lib/core/server/auth.dart
// LAN_WEB v2.0.0 P2 鉴权模块
//
// 职责:
// - 6 位配对码生成 / 校验(默认 5 分钟有效)
// - session token 生成 / 持久化(SharedPreferences,7 天有效)
// - shelf auth middleware(校验 cookie → 注入 session 到 request context)
// - Set-Cookie / Clear-Cookie helper
//
// 架构:跑在 main isolate 跟 HTTP server 一起,跟 fg_service 无关
// 详细:docs/LAN_WEB.md P2 拍板
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// LAN_WEB 鉴权常量
class LanWebAuth {
  /// 6 位配对码有效期
  static const Duration pairingCodeTtl = Duration(minutes: 5);

  /// session 有效期
  static const Duration sessionTtl = Duration(days: 7);

  /// cookie 名
  static const String cookieName = 'gridly_session';

  /// SharedPreferences 存 sessions 的 key
  static const String _kSessionsKey = 'lan_web_sessions';
}

/// 一次性 6 位配对码(in-memory,5 分钟有效)
class PairingCode {
  final String code;        // 6 位数字字符串
  final DateTime expiresAt;

  const PairingCode({required this.code, required this.expiresAt});

  bool get isValid => DateTime.now().isBefore(expiresAt);

  /// 剩余秒数(expired 时返 0)
  int get remainingSeconds {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'expiresAt': expiresAt.toIso8601String(),
        'remainingSeconds': remainingSeconds,
      };
}

/// 配对码存储(单例 in-memory,5 分钟有效)
class PairingCodeStore {
  PairingCode? _current;
  final Random _rng = Random.secure();

  /// 获取当前码(过期或无则重新生成)
  PairingCode current() {
    if (_current != null && _current!.isValid) return _current!;
    return _generate();
  }

  /// 强制刷新(用户点"刷新配对码"按钮时调)
  PairingCode refresh() => _generate();

  /// 校验输入码(命中且未过期)
  bool verify(String input) {
    if (_current == null) return false;
    if (!_current!.isValid) return false;
    return _current!.code == input;
  }

  /// 配对成功后清掉(防复用 + 不再展示给 user)
  void clear() {
    _current = null;
  }

  PairingCode _generate() {
    // 000000 - 999999
    final code = _rng.nextInt(1000000).toString().padLeft(6, '0');
    _current = PairingCode(
      code: code,
      expiresAt: DateTime.now().add(LanWebAuth.pairingCodeTtl),
    );
    return _current!;
  }
}

/// 已配对 session(7 天有效,持久化)
class ActiveSession {
  final String token;        // 32 字符 hex
  final DateTime createdAt;
  // lastSeenAt 可变:每次 findByToken 命中就更新(避免每次创建新对象)
  DateTime lastSeenAt;
  final String label;        // user 起的标签或 "Device 1"

  ActiveSession({
    required this.token,
    required this.createdAt,
    required this.lastSeenAt,
    required this.label,
  });

  bool get isExpired =>
      DateTime.now().isAfter(createdAt.add(LanWebAuth.sessionTtl));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'token': token,
        'createdAt': createdAt.toIso8601String(),
        'lastSeenAt': lastSeenAt.toIso8601String(),
        'label': label,
      };

  static ActiveSession fromJson(Map<String, dynamic> j) => ActiveSession(
        token: j['token'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        lastSeenAt: DateTime.parse(j['lastSeenAt'] as String),
        label: (j['label'] as String?) ?? 'Device',
      );
}

/// Session 存储(SharedPreferences 持久化,7 天有效)
class SessionStore {
  final List<ActiveSession> _sessions = [];
  final Random _rng = Random.secure();
  bool _loaded = false;

  /// 测试用:清空 in-memory cache(下一次 load() 会从 prefs 重读)
  /// 不删 SharedPreferences(那是持久化层,测试用 setMockInitialValues 兜底)
  void clear() {
    _sessions.clear();
    _loaded = false;
  }

  /// 启动时调一次(异步,从 SharedPreferences 加载)
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(LanWebAuth._kSessionsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _sessions
          ..clear()
          ..addAll(list.map(
              (j) => ActiveSession.fromJson(j as Map<String, dynamic>)));
      } catch (e) {
        // 损坏的 JSON 清掉,免得阻塞启动
        _sessions.clear();
      }
    }
    _purgeExpired();
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_sessions.map((s) => s.toJson()).toList());
    await prefs.setString(LanWebAuth._kSessionsKey, json);
  }

  void _purgeExpired() {
    _sessions.removeWhere((s) => s.isExpired);
  }

  /// 创建新 session
  ActiveSession create({String label = 'Device'}) {
    _purgeExpired();
    final session = ActiveSession(
      token: _generateToken(),
      createdAt: DateTime.now(),
      lastSeenAt: DateTime.now(),
      label: label,
    );
    _sessions.add(session);
    _save();
    return session;
  }

  /// 查 token,找到就更新 lastSeenAt 并返 session
  ActiveSession? findByToken(String token) {
    _purgeExpired();
    for (final s in _sessions) {
      if (s.token == token) {
        s.lastSeenAt = DateTime.now();
        _save();
        return s;
      }
    }
    return null;
  }

  /// 撤销某 token 的 session
  bool revoke(String token) {
    final before = _sessions.length;
    _sessions.removeWhere((s) => s.token == token);
    if (_sessions.length < before) {
      _save();
      return true;
    }
    return false;
  }

  /// 列出所有 active session(可排除当前)
  List<ActiveSession> list({String? excludeToken}) {
    _purgeExpired();
    if (excludeToken == null) return List.unmodifiable(_sessions);
    return List.unmodifiable(
        _sessions.where((s) => s.token != excludeToken));
  }

  String _generateToken() {
    // 32 字符 hex(16 字节)
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// shelf middleware:校验 cookie + 注入 session 到 request context
///
/// - /api/auth/* 路径不校验(配对流程本身要 public)
/// - /api/health 路径不校验(简单健康检查)
/// - 其它路径:无 cookie / session 过期 / 找不到 → 401
Middleware authMiddleware(SessionStore sessions) {
  return (Handler inner) {
    return (Request request) async {
      // 公开路径白名单
      // ⚠️ shelf_router quirk:middleware 拿到的 request.url.path 是
      //   shelf_router 内部加 local "/" 后 normalize 过的形式,
      //   - 'GET /' → path = '' 或 '/'(两种都见过)
      //   - 'GET /api/auth/code' → path = 'api/auth/code'(leading slash 被 strip)
      //   - 'GET /api/health' → path = 'api/health'
      // 白名单用 startsWith 不带 slash 形式
      final path = request.url.path;
      if (path.startsWith('api/auth/') ||
          path == 'api/health' ||
          path == '/api/health' ||
          path.isEmpty ||
          path == '/') {
        return inner(request);
      }

      // 解析 cookie
      final cookieHeader = request.headers['Cookie'] ?? '';
      final token = _parseCookie(cookieHeader, LanWebAuth.cookieName);

      if (token == null) {
        return _unauthorized('missing_cookie');
      }

      final session = sessions.findByToken(token);
      if (session == null) {
        return _unauthorized('session_expired');
      }

      // 注入 session 到 context
      return inner(request.change(
          context: <String, Object>{...request.context, 'session': session}));
    };
  };
}

/// 配对成功的 Set-Cookie header 值
String buildSessionSetCookie(String token) {
  final maxAge = LanWebAuth.sessionTtl.inSeconds;
  return '${LanWebAuth.cookieName}=$token; '
      'Path=/; '
      'HttpOnly; '
      'SameSite=Lax; '
      'Max-Age=$maxAge';
}

/// 注销时清 cookie
String buildSessionClearCookie() {
  return '${LanWebAuth.cookieName}=; '
      'Path=/; '
      'HttpOnly; '
      'SameSite=Lax; '
      'Max-Age=0';
}

/// 401 响应
Response _unauthorized(String error) {
  return Response(401,
      body: jsonEncode(<String, String>{'error': error}),
      headers: <String, String>{'Content-Type': 'application/json'});
}

/// 从 Cookie header 解析指定 name 的值
String? _parseCookie(String header, String name) {
  // Cookie: name1=value1; name2=value2
  if (header.isEmpty) return null;
  for (final part in header.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq == -1) continue;
    final n = trimmed.substring(0, eq);
    if (n == name) {
      return Uri.decodeComponent(trimmed.substring(eq + 1));
    }
  }
  return null;
}