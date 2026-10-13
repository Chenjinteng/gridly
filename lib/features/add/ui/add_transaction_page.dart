// lib/features/add/ui/add_transaction_page.dart
// 记一笔页面 —— 全屏 Scaffold + AppBar + TransactionForm。
//
// 表单逻辑全部在 transaction_form.dart,本页只负责"全屏路由 + 顶部关闭按钮"
// 这个壳子;保存后 context.pop() 回到路由栈上一级(根 tab)。
//
// 流水编辑场景同样用全屏路由(/edit/:id,见 lib/features/add/ui/edit_transaction_page.dart),
// 跟本页同架构 —— 2026-10-11 改:之前用 modal sheet 路线因 Numpad 行为不一致被换掉。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import 'transaction_form.dart';

class AddTransactionPage extends StatelessWidget {
  const AddTransactionPage({
    super.key,
    this.editTransaction,
    this.preselectedAssetType,
    this.allowBalance,
    this.accountTypeFilter,
  });

  /// 编辑模式:保留以兼容路由 /add?edit=xxx(目前主要走 sheet,这里极少用)
  final Transaction? editTransaction;

  /// 2026-10-13 P6 commit:预选资产类型
  /// - 短按 + → 'cash_flow'(默认,form 内 accountId 默认选现金段第 1 账户)
  /// - 长按 + → 5 小圆选(investment/benefit/receivable/fixed_asset/other)
  /// - null → 走原 cash_flow 兼容
  final String? preselectedAssetType;

  /// 2026-10-13 P6 UAT 改:是否显示"调拨"段
  /// - null → 默认按 preselectedAssetType 推导:
  ///   - 短按 cash_flow 路径:false(老版,无调拨)
  ///   - 长按 5 段路径:true(保留 3 段,后续精细化时再调整)
  /// - 非 null → 用 caller 的值
  final bool? allowBalance;

  /// 2026-10-13 P6 UAT 改:账户 sheet 按 type 过滤
  /// - null → 不过滤(显示所有)
  /// - 'cash_flow' → 只显示 cash_flow 账户
  /// - 'investment' → 只显示 investment 账户
  final String? accountTypeFilter;

  @override
  Widget build(BuildContext context) {
    // 2026-10-13 P6 UAT:按 preselectedAssetType 推导 allowBalance 默认值
    //   - null 或 'cash_flow'(短按):allowBalance=false(老版,无调拨)
    //   - 其他 5 段(长按):allowBalance=true(保留 3 段,后续再调)
    final effectiveAllowBalance =
        allowBalance ??
        (preselectedAssetType == null || preselectedAssetType == 'cash_flow'
            ? false
            : true);

    // 2026-10-13 P6 UAT:accountTypeFilter 默认 = preselectedAssetType
    //   - 短按 'cash_flow' → 账户 sheet 只显示 cash_flow 账户
    //   - 长按 'investment' → 账户 sheet 只显示 investment 账户
    //   - caller 显式传 null → 不过滤(向后兼容)
    //   - caller 显式传 string → 用 caller 的值(可强制覆盖)
    final effectiveAccountTypeFilter = accountTypeFilter ?? preselectedAssetType;

    return Scaffold(
      // resizeToAvoidBottomInset: false → 系统键盘弹起时不重排 body,
      // 底部的 Numpad 整段留在原位,**被键盘盖住**(这是用户期望行为:
      //   写备注时,记金额用的 Numpad 不需要看 → 让键盘盖住,UI 简洁
      //   写完 / 收键盘,Numpad 自然回来 → 不需要 FocusNode/MediaQuery 检测)
      // 之前三次"键盘弹起时动态隐藏 Numpad"路线(492a068 / f29ca49 / c693df4)
      // 以及 FocusNode 路线(12efb5f)都被推翻:检测逻辑不可靠,
      // 简化成"始终显示 + 键盘自然覆盖"是 2026-10-11 UAT 最终方案。
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('记一笔'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          // pop 回 root navigator,自动回到 shell 当前 tab —— 哪个 tab 点 +
          // 就回哪个,不再强制跳 /home
          onPressed: () => context.pop(),
        ),
      ),
      body: TransactionForm(
        editTransaction: editTransaction,
        preselectedAssetType: preselectedAssetType,
        // 2026-10-13 P6 UAT:传 allowBalance + accountTypeFilter 给 form
        allowBalance: effectiveAllowBalance,
        accountTypeFilter: effectiveAccountTypeFilter,
        // 保存后也 pop(新增 / 编辑统一处理)
        onSaved: () => context.pop(),
      ),
    );
  }
}
