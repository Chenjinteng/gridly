// lib/features/add/ui/edit_transaction_page.dart
// 流水编辑全屏页 —— /edit/:id 路由。
//
// 2026-10-11 改:之前流水编辑用 showEditTransactionSheet(modal bottom sheet),
// 键盘弹起时 sheet 内部 AnimatedPadding 会按 viewInsets 把整个 sheet 推上去,
// Numpad 跟着 sheet 上移,不会被键盘覆盖,跟全屏记一笔页行为不一致。
//
// 改全屏路由:跟 /add 同架构(Scaffold + resizeToAvoidBottomInset:false +
// TransactionForm 内部 SafeArea(bottom:false)),键盘弹起时 Numpad 真正被键盘盖住。
// 代价:流水列表会被暂时盖掉,失去"在当前 tab 编辑"的上下文连贯性,但换来
// "全 App Numpad / 键盘行为一致"是 UAT 拍板的方向。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../ledger/application/transactions_providers.dart';
import 'transaction_form.dart';

class EditTransactionPage extends ConsumerWidget {
  const EditTransactionPage({super.key, required this.transactionId});

  /// 路由参数 — path '/edit/:id' 解析出来的 int
  final int transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionByIdProvider(transactionId));
    return Scaffold(
      // 跟 AddTransactionPage 一致:键盘弹起时不重排,Numpad 留在原位被键盘覆盖
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('编辑'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: txAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.s6),
            child: CircularProgressIndicator(),
          ),
        ),
        // 找不到这笔流水(id 错 / 已被删):退回上一页,弹个 SnackBar 提示
        error: (e, _) => Center(child: Text('加载失败:$e')),
        data: (tx) {
          if (tx == null) {
            // 延迟 pop,等用户看到提示再退(用 addPostFrameCallback 避免 build 中 setState)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              showGridlyBanner(
                context,
                '找不到这笔流水,可能已被删除',
                kind: GridlyBannerKind.warning,
              );
              context.pop();
            });
            return const SizedBox.shrink();
          }
          return TransactionForm(
            editTransaction: tx,
            // 保存后 pop 回到调用方(流水页 / 报表 / 首页等)
            onSaved: () => context.pop(),
          );
        },
      ),
    );
  }
}
