// lib/core/server/middleware.dart
// LAN_WEB v2.0.0 P2 polish:404 catch-all + 500 error handler
//
// 全部在 shelf Pipeline 里 addMiddleware,统一处理
// - errorHandler:try/catch 包裹,任何未捕获异常 → 500 JSON(不暴露 stack trace)
// - catchAllHandler:未匹配路由 → 404 JSON(替代默认的 HTML 404 页面)
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_plus/shelf_plus.dart';

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