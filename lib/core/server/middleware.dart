// lib/core/server/middleware.dart
// LAN_WEB v2.0.0 P2 polish:404 catch-all + 500 error handler + body size limit + CORS + rate limit
//
// 全部在 shelf Pipeline 里 addMiddleware,统一处理
// - errorHandler:try/catch 包裹,任何未捕获异常 → 500 JSON(不暴露 stack trace)
// - catchAllHandler:未匹配路由 → 404 JSON(替代默认的 HTML 404 页面)
// - bodySizeLimit:Content-Length > N → 413(防 OOM + DoS);无 header 不检查
// - cors:OPTIONS 预检 204;其它响应 echo Origin(P3 web UI 跨源)
// - rateLimit:每 session token 60 req/sec 滑窗;超返 429
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// P2 拍板:单次 body 最大 1 MB(本机记账类 API 远用不到这么大,
/// 顶 1MB 够传最长的 note + 几十个 budget category;1MB+ 多半是 DoS)
const int kMaxBodyBytes = 1 * 1024 * 1024; // 1 MB

/// P2 拍板:每 session token / 匿名 IP 1 秒 60 req(LAN 正常用户 1-2 req/s,留足 headroom)
const int kRateLimitPerSecond = 60;

/// 500 error handler
///
/// 包裹内部 handler,任何 throw 都被捕获并返 500 JSON。
/// 错误 stack 走 debugPrint(只 dev 模式可见),**不**回给 web(避免 stack trace 泄漏)。
Middleware errorHandler() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } catch (e, st) {
        debugPrint('[lan_web] unhandled error on ${request.method} ${request.url.path}: $e\n$st');
        return Response(
          500,
          body: jsonEncode(<String, String>{'error': 'internal_error'}),
          headers: <String, String>{'Content-Type': 'application/json'},
        );
      }
    };
  };
}

/// 404 catch-all handler
///
/// 在所有路由注册完后调 `app.all('/<path|.*>', ...)`(shelf router 支持 catch-all 正则)
/// 任何未匹配路径 → 404 JSON(替代默认 HTML 页面,browser 看 JSON 友好)
Handler catchAllHandler() {
  return (Request request) {
    return Response(
      404,
      body: jsonEncode(<String, String>{
        'error': 'route_not_found',
        'method': request.method,
        'path': request.url.path,
      }),
      headers: <String, String>{'Content-Type': 'application/json'},
    );
  };
}

/// CORS middleware
///
/// 给所有响应加 `Access-Control-Allow-*` headers,支持浏览器跨源请求(P3 Web UI)。
///
/// 设计:
/// - OPTIONS 预检请求直接 204 返,不进入 auth/routing(预检不应被鉴权)
/// - 其它请求 echo back Origin(因为 LAN_WEB 配对码只服务同 WiFi,无需严格 origin 白名单)
/// - 允许 credentials(cookie gridly_session),所以 Allow-Origin 不能 `*`,要回具体 origin
/// - 缓存预检 1 小时(3600s),避免每个 POST 都触发 OPTIONS
Middleware cors() {
  return (Handler inner) {
    return (Request request) async {
      final origin = request.headers['Origin'] ?? '';

      // 1. OPTIONS 预检:直接 204 返
      if (request.method == 'OPTIONS') {
        return Response(
          204,
          headers: <String, String>{
            'Access-Control-Allow-Origin': origin,
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers':
                'Content-Type, Cookie, X-Requested-With',
            'Access-Control-Allow-Credentials': 'true',
            'Access-Control-Max-Age': '3600',
            if (origin.isNotEmpty) 'Vary': 'Origin',
          },
        );
      }

      // 2. 其它请求:加 CORS headers 到响应
      final resp = await inner(request);
      if (origin.isNotEmpty) {
        // resp.headers 是 unmodifiable;用 change() 拿新 Response
        final updated = <String, String>{
          ...resp.headers,
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Credentials': 'true',
          'Vary': 'Origin',
        };
        return resp.change(headers: updated);
      }
      return resp;
    };
  };
}

/// Body size limit middleware
///
/// 1. 看 Content-Length header,> 1MB 直接 413
/// 2. 真实读 body 后若 > 1MB 仍返 413(防 spoof header;HTTP/1.1 chunked 不带 CL 也能挡)
/// 3. 小 body 透传给 inner(GET/HEAD 跳过)
Middleware bodySizeLimit({int maxBytes = kMaxBodyBytes}) {
  return (Handler inner) {
    return (Request request) async {
      // GET / HEAD / DELETE 通常无 body,跳过
      if (request.method == 'GET' ||
          request.method == 'HEAD' ||
          request.method == 'OPTIONS') {
        return inner(request);
      }

      // 1. Content-Length 头检查(早返,省读 body)
      final cl = request.headers['Content-Length'];
      if (cl != null) {
        final n = int.tryParse(cl);
        if (n != null && n > maxBytes) {
          return Response(
            413,
            body: jsonEncode(<String, String>{
              'error': 'body_too_large',
              'limitBytes': maxBytes.toString(),
            }),
            headers: <String, String>{'Content-Type': 'application/json'},
          );
        }
      }

      // 2. 读 body 后再量一次(chunked 无 CL 仍可挡)
      final raw = await request.readAsString();
      if (raw.length > maxBytes) {
        return Response(
          413,
          body: jsonEncode(<String, String>{
            'error': 'body_too_large',
            'limitBytes': maxBytes.toString(),
          }),
          headers: <String, String>{'Content-Type': 'application/json'},
        );
      }

      // 3. 重包装 request(body 已被 read 完,这里把 read 过的 string 重新塞回)
      //    用 change 改 body:shelf 的 Request.change 支持改 body
      return inner(request.change(body: raw));
    };
  };
}

/// Rate limit middleware
///
/// 简单滑窗实现(每 key 维护 1 秒内的 hit 时间戳):
/// - key = session token(从 cookie 解析)或 'anonymous'(无 cookie)
/// - 1 秒内超过 [maxPerSecond] 次 → 429
/// - 跨测试 / 跨 server 重启 in-memory 状态会丢(可接受,见 commit 14 doc)
///
/// 不在 body size 之前(超限也不浪费 bandwidth),
/// 但在 auth 之后(我们用 session token 作 key,auth 后才确定身份)。
/// 实际上为了不让限流影响 OPTIONS 预检,放在 cors() 之后。
class _RateLimiter {
  final Map<String, List<DateTime>> _hits = {};

  /// 记录一次 hit,超限返 false
  bool allow(String key) {
    final now = DateTime.now();
    final hits = _hits.putIfAbsent(key, () => <DateTime>[]);
    // drop 1 秒前
    hits.removeWhere((t) => now.difference(t).inMilliseconds > 1000);
    if (hits.length >= kRateLimitPerSecond) return false;
    hits.add(now);
    return true;
  }

  /// 清理(测试用)
  void clear() => _hits.clear();
}

/// 全局单例(测试用 clear)
final _RateLimiter _rateLimiter = _RateLimiter();

/// 测试用:清空 rate limit 状态
void clearRateLimiter() => _rateLimiter.clear();

/// 从 Cookie header 解析 gridly_session 的 token
String? _sessionTokenFromCookie(String cookieHeader) {
  if (cookieHeader.isEmpty) return null;
  for (final part in cookieHeader.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq == -1) continue;
    if (trimmed.substring(0, eq) == 'gridly_session') {
      return trimmed.substring(eq + 1);
    }
  }
  return null;
}

Middleware rateLimit() {
  return (Handler inner) {
    return (Request request) async {
      // OPTIONS 预检不限流(避免 CORS 失败)
      if (request.method == 'OPTIONS') return inner(request);

      // key = session token 或 'anonymous'
      final cookie = request.headers['Cookie'] ?? '';
      final token = _sessionTokenFromCookie(cookie) ?? 'anonymous';

      if (!_rateLimiter.allow(token)) {
        return Response(
          429,
          body: jsonEncode(<String, String>{
            'error': 'rate_limited',
            'limit': kRateLimitPerSecond.toString(),
            'windowSeconds': '1',
          }),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Retry-After': '1',
          },
        );
      }
      return inner(request);
    };
  };
}