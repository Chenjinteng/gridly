// test/lan_web/p2_edge_cases_test.dart
// LAN_WEB v2.0.0 P2 edge case 测试 —— 补 P2 commit 7 主流程之外的覆盖
//
// 跑法:
//   flutter test test/lan_web/p2_edge_cases_test.dart
//
// 覆盖:
//   A. 鉴权(7)  bad body / missing code / wrong length / logout 幂等 /
//                sessions list / revoke current (400) / revoke fake (404)
//   B. 流水(10) bad id / 404 / missing amount / invalid type /
//                missing categoryId / bad occurredAt / 过滤(4) / pagination
//   C. 分类(4)  POST success / 400 missing name / 400 invalid type / PUT 404
//   D. 统计(3)  monthly 空 / categories 空 / top
//   E. 预算(3)  GET 空 / PUT 缺字段 / PUT overwrite
//   F. 集成(1)  多设备 pair → list 互见 → revoke 一方仍可访问
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/repositories/asset_repository.dart';
import 'package:gridly/core/database/repositories/category_repository.dart';
import 'package:gridly/core/server/gridly_server.dart';

/// 跑 pair 流程 → 返 cookie header 字符串
Future<String> _pairAndGetCookie(http.Client client, Uri base) async {
  final codeResp = await client.get(base.replace(path: '/api/auth/code'));
  final code = (jsonDecode(codeResp.body) as Map<String, dynamic>)['code']
      as String;
  final pairResp = await client.post(
    base.replace(path: '/api/auth/pair'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'code': code, 'label': 'EdgeCase'}),
  );
  expect(pairResp.statusCode, 200, reason: 'pair failed: ${pairResp.body}');
  return RegExp(r'gridly_session=([^;]+)')
      .firstMatch(pairResp.headers['set-cookie']!)!
      .group(1)!;
}

void main() {
  late AppDatabase db;
  late http.Client client;
  late Uri base;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    pairingCodeStore.clear();
    sessionStore.clear(); // 清 in-memory cache,避免跨测试 session 污染
    clearRateLimiter(); // 滑窗计数器清零,避免之前测试的 60 req/s 残留
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

  // ========================= A. 鉴权 =========================

  group('A. 鉴权 edge cases', () {
    test('A1: POST /api/auth/pair with empty body → 400 invalid_body', () async {
      final r = await client.post(
        base.replace(path: '/api/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: '',
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'invalid_body',
      );
    });

    test('A2: POST /api/auth/pair with missing code → 400', () async {
      final r = await client.post(
        base.replace(path: '/api/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'label': 'NoCode'}),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        anyOf('invalid_code_format', 'invalid_body'),
      );
    });

    test('A3: POST /api/auth/pair with code wrong length → 400', () async {
      final r = await client.post(
        base.replace(path: '/api/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': '12345'}),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'invalid_code_format',
      );
    });

    test('A4: POST /api/auth/logout without cookie → 200 幂等', () async {
      final r = await client.post(base.replace(path: '/api/auth/logout'));
      expect(r.statusCode, 200);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['ok'],
        true,
      );
    });

    test('A5: GET /api/auth/sessions 列出当前外的 sessions', () async {
      final cookie = await _pairAndGetCookie(client, base);
      final r = await client.get(
        base.replace(path: '/api/auth/sessions'),
        headers: {'Cookie': 'gridly_session=$cookie'},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      // 当前只有自己一个 session,排除后应为空
      expect((body['sessions'] as List).length, 0);
    });

    test('A6: DELETE 当前 session → 400 cannot_revoke_current', () async {
      final cookie = await _pairAndGetCookie(client, base);
      final r = await client.delete(
        base.replace(path: '/api/auth/sessions/$cookie'),
        headers: {'Cookie': 'gridly_session=$cookie'},
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'cannot_revoke_current',
      );
    });

    test('A7: DELETE 不存在 token → 404 session_not_found', () async {
      final cookie = await _pairAndGetCookie(client, base);
      final fake = 'a' * 32;
      final r = await client.delete(
        base.replace(path: '/api/auth/sessions/$fake'),
        headers: {'Cookie': 'gridly_session=$cookie'},
      );
      expect(r.statusCode, 404);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'session_not_found',
      );
    });
  });

  // ========================= B. 流水 =========================

  group('B. 流水 edge cases', () {
    Future<String> authedSession() async {
      final c = await _pairAndGetCookie(client, base);
      return 'gridly_session=$c';
    }

    Future<int> createExpense(String cookie, {double amount = 50}) async {
      // 拿第一个 cash_flow 分类
      final catResp = await client.get(
        base.replace(
          path: '/api/categories',
          queryParameters: {'type': 'expense'},
        ),
        headers: {'Cookie': cookie},
      );
      final cid = ((jsonDecode(catResp.body) as Map<String, dynamic>)
              ['categories'] as List)
          .first['id'] as int;
      final add = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': amount,
          'type': 'expense',
          'categoryId': cid,
          'occurredAt': '2026-10-17T12:30:00Z',
        }),
      );
      return (jsonDecode(add.body) as Map<String, dynamic>)['ledger']['id']
          as int;
    }

    test('B1: GET /api/ledgers/<id> non-int → 400 invalid_id', () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(path: '/api/ledgers/abc'),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'invalid_id',
      );
    });

    test('B2: GET /api/ledgers/<id> 不存在 → 404 ledger_not_found',
        () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(path: '/api/ledgers/99999'),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 404);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'ledger_not_found',
      );
    });

    test('B3: POST /api/ledgers missing amount → 400 missing_amount',
        () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'expense',
          'categoryId': 1,
          'occurredAt': '2026-10-17T12:30:00Z',
        }),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'missing_amount',
      );
    });

    test('B4: POST /api/ledgers invalid type → 400 invalid_type', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': 10,
          'type': 'investment', // POST 不接受(只有 PUT/特殊可)
          'categoryId': 1,
          'occurredAt': '2026-10-17T12:30:00Z',
        }),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'invalid_type',
      );
    });

    test('B5: POST /api/ledgers missing categoryId → 400', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': 10,
          'type': 'expense',
          'occurredAt': '2026-10-17T12:30:00Z',
        }),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'missing_categoryId',
      );
    });

    test('B6: POST /api/ledgers bad occurredAt → 400', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': 10,
          'type': 'expense',
          'categoryId': 1,
          'occurredAt': 'not-a-date',
        }),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'missing_or_invalid_occurredAt',
      );
    });

    test('B7: GET /api/ledgers?type=expense 过滤', () async {
      final cookie = await authedSession();
      await createExpense(cookie);
      final r = await client.get(
        base.replace(
          path: '/api/ledgers',
          queryParameters: {'type': 'expense'},
        ),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final ledgers = body['ledgers'] as List;
      expect(ledgers.length, 1);
      expect(ledgers.first['type'], 'expense');
    });

    test('B8: GET /api/ledgers?keyword=lunch note like 过滤', () async {
      final cookie = await authedSession();
      // 拿 cat + 加带 note 的流水
      final catResp = await client.get(
        base.replace(
          path: '/api/categories',
          queryParameters: {'type': 'expense'},
        ),
        headers: {'Cookie': cookie},
      );
      final cid = ((jsonDecode(catResp.body) as Map<String, dynamic>)
              ['categories'] as List)
          .first['id'] as int;
      await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': 30,
          'type': 'expense',
          'categoryId': cid,
          'occurredAt': '2026-10-17T12:30:00Z',
          'note': 'lunch with team',
        }),
      );
      await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': 5,
          'type': 'expense',
          'categoryId': cid,
          'occurredAt': '2026-10-17T13:00:00Z',
          'note': 'coffee',
        }),
      );
      final r = await client.get(
        base.replace(
          path: '/api/ledgers',
          queryParameters: {'keyword': 'lunch'},
        ),
        headers: {'Cookie': cookie},
      );
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect((body['ledgers'] as List).length, 1);
      expect((body['ledgers'] as List).first['note'], 'lunch with team');
    });

    test('B9: GET /api/ledgers?page&pageSize 分页', () async {
      final cookie = await authedSession();
      for (var i = 0; i < 3; i++) {
        await createExpense(cookie, amount: 10 + i.toDouble());
      }
      final p1 = await client.get(
        base.replace(
          path: '/api/ledgers',
          queryParameters: {'page': '1', 'pageSize': '2'},
        ),
        headers: {'Cookie': cookie},
      );
      final p2 = await client.get(
        base.replace(
          path: '/api/ledgers',
          queryParameters: {'page': '2', 'pageSize': '2'},
        ),
        headers: {'Cookie': cookie},
      );
      expect(
          (jsonDecode(p1.body) as Map<String, dynamic>)['ledgers'].length, 2);
      expect(
          (jsonDecode(p2.body) as Map<String, dynamic>)['ledgers'].length, 1);
    });

    test('B10: PUT/DELETE 不存在 id → 404', () async {
      final cookie = await authedSession();
      final put = await client.put(
        base.replace(path: '/api/ledgers/99999'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'amount': 10}),
      );
      expect(put.statusCode, 404);
      final del = await client.delete(
        base.replace(path: '/api/ledgers/99999'),
        headers: {'Cookie': cookie},
      );
      expect(del.statusCode, 404);
    });
  });

  // ========================= C. 分类 =========================

  group('C. 分类 edge cases', () {
    Future<String> authedSession() async {
      final c = await _pairAndGetCookie(client, base);
      return 'gridly_session=$c';
    }

    test('C1: POST /api/categories success', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/categories'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': '自定义测试',
          'type': 'expense',
          'icon': 'pets',
          'color': 0xFF94A3B8,
        }),
      );
      expect(r.statusCode, 201);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final cat = body['category'] as Map<String, dynamic>;
      expect(cat['name'], '自定义测试');
      expect(cat['type'], 'expense');
      expect(cat['isSystem'], false);
    });

    test('C2: POST /api/categories missing name → 400', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/categories'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'expense'}),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'missing_name',
      );
    });

    test('C3: POST /api/categories invalid type → 400', () async {
      final cookie = await authedSession();
      final r = await client.post(
        base.replace(path: '/api/categories'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'X', 'type': 'invalid_type'}),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'invalid_type',
      );
    });

    test('C4: PUT /api/categories/<id> 404 + success', () async {
      final cookie = await authedSession();
      // 先建一个
      final add = await client.post(
        base.replace(path: '/api/categories'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': '改前', 'type': 'expense'}),
      );
      final cid =
          (jsonDecode(add.body) as Map<String, dynamic>)['category']['id']
              as int;
      // 改
      final put = await client.put(
        base.replace(path: '/api/categories/$cid'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': '改后', 'icon': 'pets'}),
      );
      expect(put.statusCode, 200);
      expect(
        (jsonDecode(put.body) as Map<String, dynamic>)['category']['name'],
        '改后',
      );
      // 不存在
      final notFound = await client.put(
        base.replace(path: '/api/categories/99999'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'name': 'X'}),
      );
      expect(notFound.statusCode, 404);
    });
  });

  // ========================= D. 统计 =========================

  group('D. 统计 edge cases', () {
    Future<String> authedSession() async {
      final c = await _pairAndGetCookie(client, base);
      return 'gridly_session=$c';
    }

    test('D1: /stats/monthly 无数据 → 全 0', () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(
            path: '/api/stats/monthly',
            queryParameters: {'year': '2026', 'month': '1'}),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['income'], 0);
      expect(body['expense'], 0);
      expect(body['balance'], 0);
      expect(body['transactionCount'], 0);
    });

    test('D2: /stats/categories 无数据 → empty items', () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(
          path: '/api/stats/categories',
          queryParameters: {'from': '2026-01-01', 'to': '2026-01-31'},
        ),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['total'], 0);
      expect((body['items'] as List).length, 0);
    });

    test('D3: /stats/top with limit', () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(
          path: '/api/stats/top',
          queryParameters: {
            'from': '2026-01-01',
            'to': '2026-12-31',
            'limit': '5',
          },
        ),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect((body['items'] as List).length, lessThanOrEqualTo(5));
    });
  });

  // ========================= E. 预算 =========================

  group('E. 预算 edge cases', () {
    Future<String> authedSession() async {
      final c = await _pairAndGetCookie(client, base);
      return 'gridly_session=$c';
    }

    test('E1: GET /api/budget 无数据 → total 0, empty categoryBudgets',
        () async {
      final cookie = await authedSession();
      final r = await client.get(
        base.replace(
            path: '/api/budget',
            queryParameters: {'year': '2026', 'month': '1'}),
        headers: {'Cookie': cookie},
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['total'], 0);
      expect((body['categoryBudgets'] as List).length, 0);
    });

    test('E2: PUT /api/budget 缺字段 → 400', () async {
      final cookie = await authedSession();
      final r = await client.put(
        base.replace(path: '/api/budget'),
        headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
        body: jsonEncode({'year': 2026}),
      );
      expect(r.statusCode, 400);
      expect(
        (jsonDecode(r.body) as Map<String, dynamic>)['error'],
        'missing_year_month_or_total',
      );
    });

    test('E3: PUT /api/budget 二次调用覆盖', () async {
      final cookie = await authedSession();
      for (final t in [5000.0, 8000.0]) {
        final r = await client.put(
          base.replace(path: '/api/budget'),
          headers: {'Cookie': cookie, 'Content-Type': 'application/json'},
          body: jsonEncode({'year': 2026, 'month': 5, 'total': t}),
        );
        expect(r.statusCode, 200);
      }
      final get = await client.get(
        base.replace(
            path: '/api/budget',
            queryParameters: {'year': '2026', 'month': '5'}),
        headers: {'Cookie': cookie},
      );
      expect(
        (jsonDecode(get.body) as Map<String, dynamic>)['total'],
        8000.0,
      );
    });
  });

  // ========================= F. 集成:多设备 =========================

  group('F. 多设备 pair + revoke 集成', () {
    test('F1: 2 设备 pair → 互见 → 一方 revoke 另一方仍可访问', () async {
      // 设备 A
      final cookieA = await _pairAndGetCookie(client, base);
      // 设备 B(重新拿码 → 配对)
      final codeResp2 = await client.get(base.replace(path: '/api/auth/code'));
      final code2 = (jsonDecode(codeResp2.body) as Map<String, dynamic>)
          ['code'] as String;
      final pairB = await client.post(
        base.replace(path: '/api/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code2, 'label': 'Device B'}),
      );
      final tokenB = RegExp(r'gridly_session=([^;]+)')
          .firstMatch(pairB.headers['set-cookie']!)!
          .group(1)!;
      final cookieB = 'gridly_session=$tokenB';

      // A 视角:list sessions 看到 B
      final aList = await client.get(
        base.replace(path: '/api/auth/sessions'),
        headers: {'Cookie': 'gridly_session=$cookieA'},
      );
      final aSessions = (jsonDecode(aList.body)
          as Map<String, dynamic>)['sessions'] as List;
      expect(aSessions.length, 1);
      expect((aSessions.first as Map<String, dynamic>)['label'], 'Device B');

      // A revoke B
      final revoke = await client.delete(
        base.replace(path: '/api/auth/sessions/$tokenB'),
        headers: {'Cookie': 'gridly_session=$cookieA'},
      );
      expect(revoke.statusCode, 200);

      // B 仍能访问(被 revoke 不影响自己)
      final bCheck = await client.get(
        base.replace(path: '/api/auth/sessions'),
        headers: {'Cookie': cookieB},
      );
      expect(bCheck.statusCode, 200);
    });
  });

  // ========================= G. body size limit =========================

  group('G. body size limit', () {
    test('G1: 2MB body → 413 body_too_large', () async {
      final big = 'x' * (2 * 1024 * 1024); // 2 MB
      final r = await client.post(
        base.replace(path: '/api/ledgers'),
        headers: {'Content-Type': 'application/json'},
        body: big,
      );
      expect(r.statusCode, 413);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body['error'], 'body_too_large');
    });

    test('G2: 100KB body 正常处理(走完 handler 路径)', () async {
      // 100KB 不算大,正常走 400 invalid_body(body 不是 JSON)
      // 用 public endpoint /api/auth/pair(避免 auth 401 干扰验 body 路径)
      final ok = 'x' * (100 * 1024);
      final r = await client.post(
        base.replace(path: '/api/auth/pair'),
        headers: {'Content-Type': 'application/json'},
        body: ok,
      );
      // body 解析失败 → 400(走 tryReadJsonMap 路径)
      expect(r.statusCode, 400);
    });
  });

  // ========================= H. CORS preflight =========================

  group('H. CORS preflight', () {
    test('H1: OPTIONS /api/auth/code 预检 → 204 + Allow-Origin echo', () async {
      final r = await client.send(http.Request('OPTIONS',
              base.replace(path: '/api/auth/code'))
          ..headers['Origin'] = 'http://localhost:3000'
          ..headers['Access-Control-Request-Method'] = 'GET');
      expect(r.statusCode, 204);
      expect(
        r.headers['access-control-allow-origin'],
        'http://localhost:3000',
      );
      expect(r.headers['access-control-allow-credentials'], 'true');
      expect(r.headers['access-control-max-age'], '3600');
    });

    test('H2: 实际请求带 Origin → 响应带 Allow-Origin echo', () async {
      final r = await client.get(
        base.replace(path: '/'),
        headers: {'Origin': 'http://localhost:3000'},
      );
      expect(r.statusCode, 200);
      expect(
        r.headers['access-control-allow-origin'],
        'http://localhost:3000',
      );
      expect(r.headers['access-control-allow-credentials'], 'true');
    });

    test('H3: 不带 Origin → 不加 CORS 头(curl/原生命令行场景)', () async {
      final r = await client.get(base.replace(path: '/'));
      expect(r.statusCode, 200);
      // 没 Origin 就没 Allow-Origin
      expect(r.headers.containsKey('access-control-allow-origin'), false);
    });
  });

  // ========================= R. rate limit =========================

  group('R. rate limit', () {
    test('R1: 70 req in 1 sec → 至少 1 个 429 rate_limited', () async {
      // 公共端点 + 无 cookie 走 "anonymous" bucket,默认 60/s
      int rate429 = 0;
      for (var i = 0; i < 70; i++) {
        final r = await client.get(base.replace(path: '/'));
        if (r.statusCode == 429) rate429++;
      }
      // 60/s 限制,70 req 至少 10 个应超限
      expect(rate429, greaterThanOrEqualTo(1),
          reason: '70 req 应触发至少 1 次 429');
    });

    test('R2: 429 响应带 Retry-After + limit + windowSeconds', () async {
      // 跑满一次限流拿 429
      for (var i = 0; i < 70; i++) {
        await client.get(base.replace(path: '/'));
      }
      // 第 71 次必超
      final r = await client.get(base.replace(path: '/'));
      if (r.statusCode == 429) {
        expect(r.headers['retry-after'], '1');
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(body['error'], 'rate_limited');
        expect(body['limit'], '60');
        expect(body['windowSeconds'], '1');
      } else {
        // 如果没超 60(可能上一次清空了),skip 严格断言
        // 但我们刚刚 setUp 清了 + 跑了 70,所以必超
        fail('应该返 429 但拿到 ${r.statusCode}');
      }
    });
  });
}
