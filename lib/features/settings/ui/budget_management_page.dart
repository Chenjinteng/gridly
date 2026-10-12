// lib/features/settings/ui/budget_management_page.dart
// 月度预算配置 —— 全屏页面版
//
// 2026-10-12 commit 106 改:从 showModalBottomSheet(BudgetSheet) 改成全屏路由。
//   user 反馈 BudgetSheet 还有一点掉帧,改成全屏页面后:
//   - viewInsets 由 Scaffold.resizeToAvoidBottomInset 处理(默认 true)
//   - 键盘弹起时只重排当前 Scrollable,不再触发 sheet 容器整体 rebuild
//   - 没有 showModalBottomSheet 弹窗过渡(viewInsets 切换 + 圆角 sheet 入场动画)
//
// 复用 BudgetSheet widget:传 embedded=true 让它去掉顶部小拉手和"月度预算"标题
//   (由 AppBar 提供),viewInsets.bottom 也由 Scaffold 处理
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/budget_sheet.dart';

class BudgetManagementPage extends ConsumerWidget {
  const BudgetManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('月度预算')),
      body: const BudgetSheet(embedded: true),
    );
  }
}
