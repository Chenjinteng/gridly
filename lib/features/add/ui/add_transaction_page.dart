// lib/features/add/ui/add_transaction_page.dart
// 记一笔页面 —— 全屏 Scaffold + AppBar + TransactionForm。
//
// 表单逻辑全部在 transaction_form.dart,本页只负责"全屏路由 + 顶部关闭按钮"
// 这个壳子;新增模式保存后 go('/home'),编辑模式保存后留在原页面。
//
// 流水编辑场景不再用本页(用 lib/features/ledger/ui/widgets/edit_transaction_sheet.dart
// 的 showEditTransactionSheet 在当前 tab 弹出 sheet)—— 体验更连贯,保留流水上下文。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import 'transaction_form.dart';

class AddTransactionPage extends StatelessWidget {
  const AddTransactionPage({super.key, this.editTransaction});

  /// 编辑模式:保留以兼容路由 /add?edit=xxx(目前主要走 sheet,这里极少用)
  final Transaction? editTransaction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记一笔'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: TransactionForm(
        editTransaction: editTransaction,
        onSaved: () {
          // 新增模式保存后跳 /home;编辑模式保存后留在原页面
          if (editTransaction == null) {
            context.go('/home');
          }
        },
      ),
    );
  }
}