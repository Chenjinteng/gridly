// test/lan_web/p2_persistence_test.dart
// LAN_WEB v2.0.0 P2 持久化测试 —— 验 session 跨 server 重启有效
//
// 场景:模拟 app 重启
//   1. 启动 server + pair 拿 token T1
//   2. 停 server
//   3. 重新启动 server(load() 应从 SharedPreferences 重读 sessions)
//   4. 用 T1 调受保护端点 → 应 200
//   5. 验 revoked session 重启后仍 revoked(load 会重读状态)
//
// 跑法:
//   flutter test test/lan_web/p2_persistence_test.dart
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/asset_repository.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/server/gridly_server.dart';

void main() {
  late AppDatabase db;
  late http.Client client;
  late Uri base;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 单 test 内部模拟"app 重启":
    // - setUp 启动 server(load() 从 mock prefs 读空 sessions)
    // - test body 里 pair 写 prefs
    // - test body 里 restart server(load() 再读 prefs,看到 pair 过的 session)
    // - 同 test 内 SharedPreferences mock 状态保留,无需重置
    // SharedPreferences.setMockInitialValues({}) 隐式触发 binding init,
    //   这样 startGridlyServer 内部 SharedPreferences.getInstance 不会抛
    SharedPreferences.setMockInitialValues({});
    pairingCodeStore.clear();
    sessionStore.clear();
    clearRateLimiter();
    await CategoryRepository(db).seedDefaultsIfEmpty();
    await AssetRepository(db).seedDefaultsIfEmpty();
    final s = await startGridlyServer(db: db, port: 0);
    base = Uri.parse('http://127.0.0.1:${s.port}');
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await stopGridlyServer();
    await db.close();
  });

  test('P1: pair → restart server → 用旧 token 仍能访问', () async {
    // 1. 首次启动时 pair
    final codeResp = await client.get(base.replace(path: '/api/auth/code'));
    final code = (jsonDecode(codeResp.body) as Map<String, dynamic>)['code']
        as String;
    final pair = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'label': 'PersistTest'}),
    );
    expect(pair.statusCode, 200);
    final token = RegExp(r'gridly_session=([^;]+)')
        .firstMatch(pair.headers['set-cookie']!)!
        .group(1)!;
    final cookie = 'gridly_session=$token';

    // 2. 验 token 有效
    final check1 = await client.get(
      base.replace(path: '/api/ledgers'),
      headers: {'Cookie': cookie},
    );
    expect(check1.statusCode, 200);

    // 3. 模拟 app 重启:停 server + 重启(load() 会从 SharedPreferences 重读)
    await stopGridlyServer();
    sessionStore.clear(); // 清 in-memory cache 让 load() 走 reload 路径
    final s2 = await startGridlyServer(db: db, port: 0);
    final base2 = Uri.parse('http://127.0.0.1:${s2.port}');
    // 注意:base2 是新端口(base 还指向旧 server,但 server 已停)
    // 用 base2 走后续请求

    // 4. 用旧 token 访问(端口变了,token 没变)
    final check2 = await client.get(
      base2.replace(path: '/api/ledgers'),
      headers: {'Cookie': cookie},
    );
    expect(check2.statusCode, 200, reason: '重启后旧 token 应仍有效');
  });

  test('P2: revoke → restart → 旧 token 仍 401', () async {
    // 1. pair 2 个 session
    final code1 = ((jsonDecode(
                (await client.get(base.replace(path: '/api/auth/code'))).body)
            as Map<String, dynamic>)['code'])
        as String;
    final pairA = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code1, 'label': 'Device A'}),
    );
    final tokenA = RegExp(r'gridly_session=([^;]+)')
        .firstMatch(pairA.headers['set-cookie']!)!
        .group(1)!;

    // 拿新码 + pair B
    final code2 = ((jsonDecode(
                (await client.get(base.replace(path: '/api/auth/code'))).body)
            as Map<String, dynamic>)['code'])
        as String;
    final pairB = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code2, 'label': 'Device B'}),
    );
    final tokenB = RegExp(r'gridly_session=([^;]+)')
        .firstMatch(pairB.headers['set-cookie']!)!
        .group(1)!;

    // 2. A revoke B
    final revoke = await client.delete(
      base.replace(path: '/api/auth/sessions/$tokenB'),
      headers: {'Cookie': 'gridly_session=$tokenA'},
    );
    expect(revoke.statusCode, 200);

    // 3. 模拟重启
    await stopGridlyServer();
    sessionStore.clear();
    final s2 = await startGridlyServer(db: db, port: 0);
    final base2 = Uri.parse('http://127.0.0.1:${s2.port}');

    // 4. B 旧 token 重启后访问 PROTECTED 端点 → 应 401
    //    (注意:/api/auth/sessions 是 public 的,返回除自己外的 sessions 列表,不算)
    final checkB = await client.get(
      base2.replace(path: '/api/ledgers'),
      headers: {'Cookie': 'gridly_session=$tokenB'},
    );
    expect(checkB.statusCode, 401);
    expect(
      (jsonDecode(checkB.body) as Map<String, dynamic>)['error'],
      'session_expired',
    );

    // 5. A 旧 token 重启后访问 protected 端点 → 仍有效
    final checkA = await client.get(
      base2.replace(path: '/api/ledgers'),
      headers: {'Cookie': 'gridly_session=$tokenA'},
    );
    expect(checkA.statusCode, 200);
  });
}
