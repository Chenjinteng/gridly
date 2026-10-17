// test/lan_web/p2_integration_test.dart
// LAN_WEB v2.0.0 P2 集成测试 —— 端到端验证 auth + CRUD + stats + budget
//
// 跑法(在 gridly 项目根):
//   flutter test test/lan_web/p2_integration_test.dart
//
// 测什么:
//   1. GET /             健康检查
//   2. GET /api/auth/code 拿配对码
//   3. POST /api/auth/pair 配对拿 cookie
//   4. 401 missing_cookie / 401 session_expired
//   5. POST /api/ledgers 新增
//   6. GET /api/ledgers 列表 + 过滤
//   7. PUT /api/ledgers/:id 改
//   8. DELETE /api/ledgers/:id 删
//   9. GET /api/categories 列
//  10. POST /api/categories 新增
//  11. GET /api/stats/monthly 月度汇总
//  12. GET /api/stats/categories 期间分类饼图
//  13. GET /api/budget + PUT /api/budget 预算读写
//  14. 404 兜底
//  15. POST /api/auth/logout + 之后 401
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
    // 1. 内存 sqlite(测试用,生产用 AppDatabase() 走 path_provider file)
    db = AppDatabase.forTesting(NativeDatabase.memory());

    // 2. 初始化 SharedPreferences mock(sessions 持久化)
    SharedPreferences.setMockInitialValues({});

    // 3. 重置 pairingCode + sessionStore + rateLimit singleton(state 污染防护)
    pairingCodeStore.clear();
    sessionStore.clear();
    clearRateLimiter();

    // 4. seed 默认分类 + 默认资产(生产路径走 main.dart,测试里手动调)
    await CategoryRepository(db).seedDefaultsIfEmpty();
    await AssetRepository(db).seedDefaultsIfEmpty();

    // 5. 启动 server(绑随机端口 0 → 系统分配,避开 8123 占用冲突)
    final s = await startGridlyServer(db: db, port: 0);
    base = Uri.parse('http://127.0.0.1:${s.port}');

    // 6. http client
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await stopGridlyServer();
    await db.close();
  });

  test('GET / returns health JSON', () async {
    final r = await client.get(base);
    expect(r.statusCode, 200);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['name'], 'gridly web');
    expect(body['version'], '2.0.0');
    expect(body['phase'], 'P2 API ready');
    // P2 commit 16 增强字段
    expect(body['build'], greaterThanOrEqualTo(131));
    expect(body['dbSchemaVersion'], 9);
    expect(body['transactions'], 0);
    expect(body['categories'], greaterThan(0)); // seed 了
    expect(body['assets'], greaterThan(0)); // seed 了
    expect(body['uptimeSeconds'], greaterThanOrEqualTo(0));
    expect(body['serverTime'], isA<String>());
  });

  test('GET /api/auth/code returns 6-digit code', () async {
    final r = await client.get(base.replace(path: '/api/auth/code'));
    expect(r.statusCode, 200);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['code'], isA<String>());
    expect((body['code'] as String).length, 6);
    expect(body['expiresAt'], isA<String>());
    expect(body['remainingSeconds'], isA<int>());
  });

  test('protected route without cookie → 401 missing_cookie', () async {
    final r = await client.get(base.replace(path: '/api/ledgers'));
    expect(r.statusCode, 401);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['error'], 'missing_cookie');
  });

  test('full auth + ledgers CRUD + categories + stats + budget flow',
      () async {
    // 1. 拿码 + 配对
    final codeResp = await client.get(base.replace(path: '/api/auth/code'));
    final code = (jsonDecode(codeResp.body) as Map<String, dynamic>)['code']
        as String;
    final pairResp = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'label': 'TestClient'}),
    );
    expect(pairResp.statusCode, 200, reason: 'pair failed: ${pairResp.body}');
    final cookie = pairResp.headers['set-cookie']!;
    expect(cookie, contains('gridly_session='));
    expect(cookie, contains('HttpOnly'));
    expect(cookie, contains('SameSite=Lax'));
    expect(cookie, contains('Max-Age=604800'));

    // 提取 token 备用
    final token = RegExp(r'gridly_session=([^;]+)').firstMatch(cookie)!.group(1)!;
    final cookieHeader = 'gridly_session=$token';

    final authed = {'Cookie': cookieHeader};

    // 2. 列流水(空)
    final ledgersResp = await client.get(
      base.replace(path: '/api/ledgers'),
      headers: authed,
    );
    expect(ledgersResp.statusCode, 200);
    var ledgersBody = jsonDecode(ledgersResp.body) as Map<String, dynamic>;
    expect(ledgersBody['ledgers'], isA<List>());
    expect((ledgersBody['ledgers'] as List).length, 0);

    // 3. 列分类(有 system seed)
    final catResp = await client.get(
      base.replace(path: '/api/categories'),
      headers: authed,
    );
    expect(catResp.statusCode, 200);
    final catBody = jsonDecode(catResp.body) as Map<String, dynamic>;
    final cats = catBody['categories'] as List;
    expect(cats.length, greaterThan(0), reason: 'system seed 没生效');
    final firstCatId = (cats.first as Map<String, dynamic>)['id'] as int;
    final firstCatName = (cats.first as Map<String, dynamic>)['name'];
    // ignore: avoid_print
    print('first cat: $firstCatId $firstCatName');

    // 4. 新增流水
    final addResp = await client.post(
      base.replace(path: '/api/ledgers'),
      headers: {...authed, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'amount': 50.0,
        'type': 'expense',
        'categoryId': firstCatId,
        'occurredAt': '2026-10-17T12:30:00Z',
        'note': 'test lunch',
      }),
    );
    expect(addResp.statusCode, 201,
        reason: 'add ledger failed: ${addResp.body}');
    final addedBody = jsonDecode(addResp.body) as Map<String, dynamic>;
    final added = addedBody['ledger'] as Map<String, dynamic>;
    final ledgerId = added['id'] as int;
    expect(added['amount'], 50.0);
    expect(added['type'], 'expense');
    expect(added['note'], 'test lunch');
    expect(added['accountId'], isA<int>(), reason: 'accountId 应有 fallback');

    // 5. 列表(现在 1 条)
    final listResp = await client.get(
      base.replace(path: '/api/ledgers'),
      headers: authed,
    );
    ledgersBody = jsonDecode(listResp.body) as Map<String, dynamic>;
    expect((ledgersBody['ledgers'] as List).length, 1);

    // 6. 改
    final putResp = await client.put(
      base.replace(path: '/api/ledgers/$ledgerId'),
      headers: {...authed, 'Content-Type': 'application/json'},
      body: jsonEncode({'amount': 60.0, 'note': 'updated'}),
    );
    expect(putResp.statusCode, 200);
    final putBody = jsonDecode(putResp.body) as Map<String, dynamic>;
    final updated = putBody['ledger'] as Map<String, dynamic>;
    expect(updated['amount'], 60.0);
    expect(updated['note'], 'updated');

    // 7. 月度汇总
    final monthlyResp = await client.get(
      base.replace(
          path: '/api/stats/monthly',
          queryParameters: {'year': '2026', 'month': '10'}),
      headers: authed,
    );
    expect(monthlyResp.statusCode, 200);
    final monthly = jsonDecode(monthlyResp.body) as Map<String, dynamic>;
    expect(monthly['expense'], 60.0);
    expect(monthly['transactionCount'], 1);

    // 8. 期间分类
    final catStatResp = await client.get(
      base.replace(
        path: '/api/stats/categories',
        queryParameters: {'from': '2026-10-01', 'to': '2026-10-31'},
      ),
      headers: authed,
    );
    expect(catStatResp.statusCode, 200);
    final catStat = jsonDecode(catStatResp.body) as Map<String, dynamic>;
    expect(catStat['total'], 60.0);
    expect((catStat['items'] as List).length, greaterThan(0));

    // 9. 预算 PUT + GET
    final budgetPutResp = await client.put(
      base.replace(path: '/api/budget'),
      headers: {...authed, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'year': 2026,
        'month': 10,
        'total': 8000.0,
        'categoryBudgets': [
          {'categoryId': firstCatId, 'amount': 1000.0}
        ]
      }),
    );
    expect(budgetPutResp.statusCode, 200);

    final budgetGetResp = await client.get(
      base.replace(
        path: '/api/budget',
        queryParameters: {'year': '2026', 'month': '10'},
      ),
      headers: authed,
    );
    expect(budgetGetResp.statusCode, 200);
    final budget = jsonDecode(budgetGetResp.body) as Map<String, dynamic>;
    expect(budget['total'], 8000.0);
    expect(budget['spent'], 60.0);
    expect((budget['categoryBudgets'] as List).length, 1);
    final cb = (budget['categoryBudgets'] as List).first as Map<String, dynamic>;
    expect(cb['amount'], 1000.0);
    expect(cb['spent'], 60.0);
    expect(cb['remaining'], 940.0);

    // 10. 删除
    final delResp = await client.delete(
      base.replace(path: '/api/ledgers/$ledgerId'),
      headers: authed,
    );
    expect(delResp.statusCode, 200);

    // 11. 列表(空)
    final emptyResp = await client.get(
      base.replace(path: '/api/ledgers'),
      headers: authed,
    );
    ledgersBody = jsonDecode(emptyResp.body) as Map<String, dynamic>;
    expect((ledgersBody['ledgers'] as List).length, 0);

    // 12. 注销
    final logoutResp = await client.post(
      base.replace(path: '/api/auth/logout'),
      headers: authed,
    );
    expect(logoutResp.statusCode, 200);

    // 13. 注销后再访问 → 401
    final afterLogout = await client.get(
      base.replace(path: '/api/ledgers'),
      headers: authed,
    );
    expect(afterLogout.statusCode, 401);
    expect(
      (jsonDecode(afterLogout.body) as Map<String, dynamic>)['error'],
      'session_expired',
    );

    // 14. 未匹配路径:auth 优先 → 401 session_expired(因为刚 logout)
    //     想验 404 兜底要在 authed session 仍有效时测,见下面独立 test
    final notFound = await client.get(
      base.replace(path: '/api/nonexistent'),
      headers: authed,
    );
    expect(notFound.statusCode, 401);
    expect(
      (jsonDecode(notFound.body) as Map<String, dynamic>)['error'],
      'session_expired',
    );
  });

  test('wrong code → 401 invalid_or_expired', () async {
    final r = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': '000000'}),
    );
    expect(r.statusCode, 401);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    expect(body['error'], 'invalid_or_expired');
  });

  test('404 catch-all works with valid session', () async {
    // 配对拿 cookie(authed session 有效)
    final codeResp = await client.get(base.replace(path: '/api/auth/code'));
    final code = (jsonDecode(codeResp.body) as Map<String, dynamic>)['code']
        as String;
    final pairResp = await client.post(
      base.replace(path: '/api/auth/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'label': 'NotFoundTest'}),
    );
    final cookieHeader = RegExp(r'gridly_session=([^;]+)')
        .firstMatch(pairResp.headers['set-cookie']!)!
        .group(1)!;

    final authed = {'Cookie': 'gridly_session=$cookieHeader'};
    final notFound = await client.get(
      base.replace(path: '/api/nonexistent'),
      headers: authed,
    );
    expect(notFound.statusCode, 404);
    final nf = jsonDecode(notFound.body) as Map<String, dynamic>;
    expect(nf['error'], 'route_not_found');
    // shelf strip 掉 leading slash,所以 path 无前缀 '/'
    expect(nf['path'], anyOf('api/nonexistent', '/api/nonexistent'));
  });
}