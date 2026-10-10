// lib/features/ledger/ui/widgets/edit_transaction_sheet.dart
// 流水编辑 sheet —— 在当前 tab 弹出(showModalBottomSheet)编辑窗口,
// 不跳全屏页面,保留流水列表可见,符合 user "直接在当前 tab 编辑"的诉求。
//
// 内部复用 lib/features/add/ui/transaction_form.dart 的 TransactionForm,
// 通过 onSaved 回调决定保存后行为:此处只是 dismiss sheet,不跳路由。
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../add/ui/transaction_form.dart';

/// 弹出流水编辑 sheet
Future<void> showEditTransactionSheet(
  BuildContext context,
  Transaction transaction,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      // 用 Navigator.pop dismiss 当前 modal,sheet 关闭后 user 回到 /ledger 看到刷新后的流水
      return TransactionForm(
        editTransaction: transaction,
        onSaved: () => Navigator.of(sheetContext).pop(),
      );
    },
  );
}