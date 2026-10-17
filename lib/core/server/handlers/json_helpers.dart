// lib/core/server/handlers/json_helpers.dart
// LAN_WEB v2.0.0 P2 共享 JSON 序列化 / 响应工具
//
// 跨 handler 复用:toJson、jsonOk、jsonCreated、jsonError
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../database/app_database.dart';
import '../../database/tables/assets.dart';
import '../../database/tables/categories.dart';

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
Map<String, dynamic> categoryToJson(Category c) => <String, dynamic>{
      'id': c.id,
      'name': c.name,
      'type': c.type,
      'color': c.color,
      'icon': c.icon,
      'sortOrder': c.sortOrder,
      'isDefault': c.isDefault,
    };

/// Asset → JSON
Map<String, dynamic> assetToJson(Asset a) => <String, dynamic>{
      'id': a.id,
      'name': a.name,
      'type': a.type,
      'color': a.color,
      'icon': a.icon,
      'initialBalance': a.initialBalance,
      'includeInTransactions': a.includeInTransactions,
      'isDefault': a.isDefault,
      'displayOrder': a.displayOrder,
      'actAsCashFlow': a.actAsCashFlow,
      'note': a.note,
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