// test/lan_web/p3_static_test.dart
// LAN_WEB v2.0.0 P3 commit 2 静态文件 mount 测试
//
// 验 shelf_static 真能 serve Flutter web build:
// - 拿 temp 目录,写一个最小 index.html + 一个 sub asset
// - 启动 server 时 webDir 指 temp 目录
// - GET / 应返 index.html
// - GET /main.dart.js 应返那个 sub asset
// - GET /<未匹配> 应 fallthrough 到 index.html(SPA 路由)
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/server/gridly_server.dart';

void main() {
  late AppDatabase db;
  late Directory tempWebDir;
  late http.Client client;
  late Uri base;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    pairingCodeStore.clear();
    sessionStore.clear();
    clearRateLimiter();

    // 建一个临时 web 目录 + 2 个文件
    tempWebDir = await Directory.systemTemp.createTemp('gridly_test_web_');
    File(p.join(tempWebDir.path, 'index.html')).writeAsStringSync('''
<!DOCTYPE html>
<html><head><title>Test Web</title></head>
<body><h1>Hello from test</h1></body></html>
''');
    File(p.join(tempWebDir.path, 'main.dart.js')).writeAsStringSync('// fake js');

    // 启动 server 指 temp webDir
    final s = await startGridlyServer(
      db: db,
      port: 0,
      webDir: tempWebDir.path,
    );
    base = Uri.parse('http://127.0.0.1:${s.port}');
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await stopGridlyServer();
    await db.close();
    if (tempWebDir.existsSync()) {
      tempWebDir.deleteSync(recursive: true);
    }
  });

  test('GET / 返 index.html 内容', () async {
    final r = await client.get(base);
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], contains('text/html'));
    expect(r.body, contains('Hello from test'));
  });

  test('GET /main.dart.js 返 sub asset', () async {
    final r = await client.get(base.replace(path: '/main.dart.js'));
    expect(r.statusCode, 200);
    expect(r.body, '// fake js');
  });

  test('GET /<未匹配路径> fallthrough 到 index.html(SPA 路由)', () async {
    final r = await client.get(base.replace(path: '/some/spa/route'));
    // shelf_static 的 defaultDocument 行为:找不到文件就返 index.html
    expect(r.statusCode, 200);
    expect(r.body, contains('Hello from test'));
  });

  test('GET /api/health 不被静态 catch-all 拦截(API 优先)', () async {
    final r = await client.get(base.replace(path: '/api/health'));
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], contains('application/json'));
    final body = r.body;
    expect(body, contains('gridly web'));
  });
}
