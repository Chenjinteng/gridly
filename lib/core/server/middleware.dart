// lib/core/server/middleware.dart
// LAN_WEB v2.0.0 P2 polish:404 catch-all + 500 error handler + body size limit
//
// 全部在 shelf Pipeline 里 addMiddleware,统一处理
// - errorHandler:try/catch 包裹,任何未捕获异常 → 500 JSON(不暴露 stack trace)
// - catchAllHandler:未匹配路由 → 404 JSON(替代默认的 HTML 404 页面)
// - bodySizeLimit:Content-Length > N → 413(防 OOM + DoS);无 header 不检查
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

/// P2 拍板:单次 body 最大 1 MB(本机记账类 API 远用不到这么大,
/// 顶 1MB 够传最长的 note + 几十个 budget category;1MB+ 多半是 DoS)
const int kMaxBodyBytes = 1 * 1024 * 1024; // 1 MB

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