// lib/web/api_client.dart
// LAN_WEB v2.0.0 P3 web 端 API client
//
// 同源(Chrome 访问 http://<gridly>:8123/)→ cookie 由浏览器自动管理
// (BrowserClient 自带 same-origin cookie 支持,无需手动 Set-Cookie)
// 跨源才需要 CORS 头 + credentials(我们同源不需要,但 middleware 仍加,保险)
import 'dart:convert';
import 'package:http/http.dart' as http;

class WebApiClient {
  WebApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? _defaultBaseUrl();

  final String _baseUrl;

  /// Web 默认同源(window.location.origin);
  /// 桌面 dev mode 直起 server(默认 8123)也用同源
  /// 测试或 staging 可显式传 baseUrl
  static String _defaultBaseUrl() {
    // web 平台无法用 dart:io.Platform,直接交由浏览器决定
    return ''; // 同源时用相对路径 '/api/...'
  }

  /// 健康检查
  Future<Map<String, dynamic>> health() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/health'));
    return _decodeJson(r);
  }

  /// 拿当前 6 位配对码
  Future<String> fetchPairingCode() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/auth/code'));
    final body = _decodeJson(r);
    return body['code'] as String;
  }

  /// 提交 6 位配对码 → server 返 Set-Cookie + JSON
  /// cookie 由浏览器自动存,后续 http 调用自动带
  Future<bool> pairWithCode(String code, {String label = 'Web Client'}) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'label': label}),
    );
    if (r.statusCode == 200) {
      // Set-Cookie 浏览器已自动存,无需手动处理
      return true;
    }
    final body = _decodeJson(r);
    throw ApiException(
      status: r.statusCode,
      errorCode: body['error'] as String? ?? 'unknown',
    );
  }

  /// 注销
  Future<void> logout() async {
    await http.post(Uri.parse('$_baseUrl/api/auth/logout'));
  }

  /// 列已配对设备(排除自己)
  Future<List<Map<String, dynamic>>> listActiveSessions() async {
    final r = await http.get(Uri.parse('$_baseUrl/api/auth/sessions'));
    final body = _decodeJson(r);
    return (body['sessions'] as List).cast<Map<String, dynamic>>();
  }

  /// 撤销某 session(非自己)
  Future<void> revokeSession(String token) async {
    final r = await http.delete(Uri.parse('$_baseUrl/api/auth/sessions/$token'));
    if (r.statusCode != 200) {
      final body = _decodeJson(r);
      throw ApiException(
        status: r.statusCode,
        errorCode: body['error'] as String? ?? 'unknown',
      );
    }
  }

  /// 流水列表
  Future<List<Map<String, dynamic>>> listLedgers({
    int? page,
    int? pageSize,
    String? type,
  }) async {
    final qp = <String, String>{};
    if (page != null) qp['page'] = page.toString();
    if (pageSize != null) qp['pageSize'] = pageSize.toString();
    if (type != null) qp['type'] = type;
    final r = await http.get(
      Uri.parse('$_baseUrl/api/ledgers').replace(queryParameters: qp),
    );
    final body = _decodeJson(r);
    return (body['ledgers'] as List).cast<Map<String, dynamic>>();
  }

  /// 新增流水
  /// [type]: 'expense' | 'income' | 'balance'
  Future<Map<String, dynamic>> createLedger({
    required double amount,
    required String type,
    required int categoryId,
    required DateTime occurredAt,
    String? note,
  }) async {
    final r = await http.post(
      Uri.parse('$_baseUrl/api/ledgers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': amount,
        'type': type,
        'categoryId': categoryId,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'note': ?note,
      }),
    );
    final body = _decodeJson(r);
    return body['ledger'] as Map<String, dynamic>;
  }

  /// 分类列表
  Future<List<Map<String, dynamic>>> listCategories({String? type}) async {
    final qp = <String, String>{};
    if (type != null) qp['type'] = type;
    final r = await http.get(
      Uri.parse('$_baseUrl/api/categories').replace(queryParameters: qp),
    );
    final body = _decodeJson(r);
    return (body['categories'] as List).cast<Map<String, dynamic>>();
  }

  /// 月度汇总
  Future<Map<String, dynamic>> monthlyStats(int year, int month) async {
    final r = await http.get(
      Uri.parse('$_baseUrl/api/stats/monthly')
          .replace(queryParameters: {'year': year.toString(), 'month': month.toString()}),
    );
    return _decodeJson(r);
  }

  Map<String, dynamic> _decodeJson(http.Response r) {
    if (r.statusCode >= 400) {
      try {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        throw ApiException(
          status: r.statusCode,
          errorCode: body['error'] as String? ?? 'unknown',
        );
      } catch (_) {
        throw ApiException(status: r.statusCode, errorCode: 'parse_error');
      }
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }
}

/// 简单异常包装(server 错误码 / HTTP 状态)
class ApiException implements Exception {
  ApiException({required this.status, required this.errorCode});
  final int status;
  final String errorCode;

  @override
  String toString() => 'ApiException($status $errorCode)';
}
