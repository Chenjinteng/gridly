// lib/core/server/handlers/json_helpers.dart
// LAN_WEB v2.0.0 P2 共享 JSON 序列化 / 响应工具
//
// 跨 handler 复用:toJson、jsonOk、jsonCreated、jsonError
import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';

import '../../database/app_database.dart'; // AppDatabase + Category/Asset 数据类(re-export via .g.dart)

/// Transaction → JSON
Map<String, dynamic> ledgerToJson(Transaction t) => <String, dynamic>{
      'id': t.id,
      'amount': t.amount,
      'type': t.type,
      'categoryId': t.categoryId,
      'occurredAt': t.occurredAt.toIso8601String(),
      'note': t.note,
      'accountId': t.accountId,
      'destinationAccountId': t.destinationAccountId,
      'createdAt': t.createdAt.toIso8601String(),
      'updatedAt': t.updatedAt.toIso8601String(),
    };

/// Category → JSON
/// Category.color 是 IntColumn(ARGB 32-bit),web 端自己 int → hex
Map<String, dynamic> categoryToJson(Category c) => <String, dynamic>{
      'id': c.id,
      'name': c.name,
      'type': c.type,
      'color': c.color,           // int (ARGB)
      'icon': c.icon,
      'sortOrder': c.sortOrder,
      'isSystem': c.isSystem,     // P2:系统预置分类标记(原 isDefault 改名)
    };

/// Asset → JSON
/// Asset.color 是 IntColumn(ARGB 32-bit)
Map<String, dynamic> assetToJson(Asset a) => <String, dynamic>{
      'id': a.id,
      'name': a.name,
      'type': a.type,
      'color': a.color,                          // int (ARGB)
      'icon': a.icon,
      'initialBalance': a.initialBalance,
      'includeInTransactions': a.includeInTransactions,
      'isDefault': a.isDefault,                  // cash_flow 段默认账户
      'actAsCashFlow': a.actAsCashFlow,          // receivable 段充当现金流
      'isLender': a.isLender,                    // receivable 段借出/借入
      'displayOrder': a.displayOrder,
    };

/// 200 OK + JSON
Response jsonOk(Object body) => Response.ok(
      jsonEncode(body),
      headers: <String, String>{'Content-Type': 'application/json'},
    );

/// 201 Created + JSON
Response jsonCreated(Object body) => Response(
      201,
      body: jsonEncode(body),
      headers: <String, String>{'Content-Type': 'application/json'},
    );

/// 错误响应(status + {error: code})
Response jsonError(int status, String code) => Response(
      status,
      body: jsonEncode(<String, String>{'error': code}),
      headers: <String, String>{'Content-Type': 'application/json'},
    );