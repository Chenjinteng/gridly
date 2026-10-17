// lib/core/server/handlers/auth_handler.dart
// LAN_WEB v2.0.0 P2 鉴权 endpoint
//
// 提供:
// - GET  /api/auth/code       拿当前 6 位配对码(无则生成,过期则刷新)
// - POST /api/auth/pair       提交 6 位码 → 200 + Set-Cookie + JSON
// - POST /api/auth/logout     撤销当前 session + Clear-Cookie
// - GET  /api/auth/sessions   列出所有 active session(可排除当前)
// - DELETE /api/auth/sessions/:token 撤销某 session
//
// 跑在 main isolate 跟 gridly_server 一起
// 鉴权由 authMiddleware 处理:这 4 个端点本身是 public,其它端点要求 cookie
import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';

import '../auth.dart';

/// 鉴权 endpoint 注册入口(gridly_server 用)
void registerAuthHandlers(
  RouterPlus app,
  PairingCodeStore pairingCode,
  SessionStore sessions,
) {
  // GET /api/auth/code
  app.get('/api/auth/code', (Request request) {
    final code = pairingCode.current();
    return Response.ok(jsonEncode(code.toJson()),
        headers: <String, String>{'Content-Type': 'application/json'});
  });

  // POST /api/auth/pair
  app.post('/api/auth/pair', (Request request) async {
    final body = await request.body.asJson;
    if (body is! Map<String, dynamic>) {
      return Response(400,
          body: jsonEncode(<String, String>{'error': 'invalid_body'}),
          headers: <String, String>{'Content-Type': 'application/json'});
    }
    final input = body['code'] as String?;
    if (input == null || input.length != 6) {
      return Response(400,
          body: jsonEncode(<String, String>{'error': 'invalid_code_format'}),
          headers: <String, String>{'Content-Type': 'application/json'});
    }

    if (!pairingCode.verify(input)) {
      return Response(401,
          body: jsonEncode(<String, String>{'error': 'invalid_or_expired'}),
          headers: <String, String>{'Content-Type': 'application/json'});
    }

    // 配对成功:创建 session + 清掉配对码(防复用)
    final label = (body['label'] as String?)?.trim();
    final session =
        sessions.create(label: (label != null && label.isNotEmpty) ? label : 'Device');
    pairingCode.clear();

    return Response.ok(
      jsonEncode(<String, dynamic>{
        'ok': true,
        'session': session.toJson(),
      }),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Set-Cookie': buildSessionSetCookie(session.token),
      },
    );
  });

  // POST /api/auth/logout
  app.post('/api/auth/logout', (Request request) {
    final cookieHeader = request.headers['Cookie'] ?? '';
    final token = _parseCookie(cookieHeader, LanWebAuth.cookieName);
    if (token != null) {
      sessions.revoke(token);
    }
    return Response(
      200,
      body: jsonEncode(<String, bool>{'ok': true}),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Set-Cookie': buildSessionClearCookie(),
      },
    );
  });

  // GET /api/auth/sessions
  app.get('/api/auth/sessions', (Request request) {
    final cookieHeader = request.headers['Cookie'] ?? '';
    final currentToken = _parseCookie(cookieHeader, LanWebAuth.cookieName);
    final all = sessions.list(excludeToken: currentToken);
    return Response.ok(
      jsonEncode(<String, dynamic>{
        'sessions': all.map((s) => s.toJson()).toList(),
      }),
      headers: <String, String>{'Content-Type': 'application/json'},
    );
  });

  // DELETE /api/auth/sessions/:token
  app.delete('/api/auth/sessions/<token>', (Request request, String token) {
    // 安全:只能撤销非当前 session(防自己误踢自己)
    final cookieHeader = request.headers['Cookie'] ?? '';
    final currentToken = _parseCookie(cookieHeader, LanWebAuth.cookieName);
    if (token == currentToken) {
      return Response(400,
          body: jsonEncode(<String, String>{'error': 'cannot_revoke_current'}),
          headers: <String, String>{'Content-Type': 'application/json'});
    }
    final ok = sessions.revoke(token);
    if (!ok) {
      return Response(404,
          body: jsonEncode(<String, String>{'error': 'session_not_found'}),
          headers: <String, String>{'Content-Type': 'application/json'});
    }
    return Response.ok(jsonEncode(<String, bool>{'ok': true}),
        headers: <String, String>{'Content-Type': 'application/json'});
  });
}

/// Cookie header 解析(从 auth.dart 复制,避免暴露内部 helper)
String? _parseCookie(String header, String name) {
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