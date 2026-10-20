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
//
// 2026-10-12 修:取消 Hero flight。之前试过 tile → AppBar 右侧 36x36 块承接
// (Commit 10),用户反馈 "图标飞到右上角了" — AppBar 右侧不该有这个 36x36
// 块,破坏 AppBar 简洁。最终决定:不做 Hero flight。点 tile 进编辑时,只剩
// 路由从底上推 480ms(Commit 2),form 直接显示,chip 内 icon 走自己样式,
// 不再有"飞行"动作。
//
// 2026-10-20 D64.84 补:按这笔流水的**分类**推导该用哪个记一笔表单
//
//   背景(user 2026-10-20 UAT 截图):流水页 → 投资记录(投资收益)左滑点「编辑」
//   → 打开的却是「支出 / 收入 / 调拨」的 cash_flow 表单,不是「投入 / 收益 /
//   调拨」的投资表单。
//
//   根因:本页只传了 editTransaction,没传 preselectedAssetType,而
//   TransactionForm 的 _isInvestmentContext / _isReceivableContext 全靠
//   widget.preselectedAssetType 判定 → 一律落到 cash_flow 分支。
//   (D64.84/D64.85 在 form 里写的"投资记录编辑 pre-fill 映射"因此是**死代码**
//    —— 那两个 commit 只改了 transaction_form.dart,没改本页。)
//
//   用错表单保存的数据风险:
//     ① type='balance' 的记录(投入 / 调拨)→ cash_flow 的 _needsDualAccount
//        = false → destForSave = null → **转入账户被丢弃**
//     ② 分类选择器出现 → user 可能把分类换成普通分类 → 记录脱离投资口径
//     ③ 债务记录 type='lend_out' 不在 cashFlowSegments 里 → toggle 无选中态
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../ledger/application/transactions_providers.dart';
import 'transaction_form.dart';

class EditTransactionPage extends ConsumerWidget {
  const EditTransactionPage({super.key, required this.transactionId});

  /// 路由参数 — path '/edit/:id' 解析出来的 int
  final int transactionId;

  /// 分类 type → 记一笔场景(跟 TransactionForm.preselectedAssetType 同协议)
  ///
  /// 依据是**分类**而不是账户 —— 分类决定这笔记录的语义(要不要分类选择器、
  /// 哪几个 toggle 段、DB type 怎么映射);账户类型只决定 picker 的可选范围。
  /// 例:信用卡消费走 cash_flow 支出段(D59),cat.type='expense' → cash_flow ✓
  static String _sceneForCategory(String? catType) {
    switch (catType) {
      case 'investment':
        return 'investment';
      case 'liability':
        return 'receivable';
      case 'benefit':
        return 'benefit';
      case 'other':
        return 'other';
      default:
        // expense / income / adjust(余额调整)→ 日常现金表单
        return 'cash_flow';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txAsync = ref.watch(transactionByIdProvider(transactionId));
    // D64.84:分类决定场景 → 场景决定表单长什么样
    final catsAsync = ref.watch(allCategoriesProvider);
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
          // D64.84:分类还没加载完就先转圈 —— 绝不能先用 cash_flow 建表单,
          //   再把 preselectedAssetType 换成 investment(表单 State 的 initState
          //   不会重跑,intent 会停在错的段)
          final cats = catsAsync.valueOrNull;
          if (cats == null) {
            return const Center(child: CircularProgressIndicator());
          }
          Category? cat;
          for (final c in cats) {
            if (c.id == tx.categoryId) {
              cat = c;
              break;
            }
          }
          final scene = _sceneForCategory(cat?.type);
          return TransactionForm(
            editTransaction: tx,
            // D64.84:告诉表单这笔记录属于哪个场景(投资 / 债务 / 福利 / 其它)
            preselectedAssetType: scene,
            // 跟记一笔页同协议(accountTypeFilter 默认 = preselectedAssetType)
            accountTypeFilter: scene,
            // D64.84:分类名 —— 表单靠它区分「亏损」(投资收益+expense,可规范化)
            // 和「真费用」(投资费用+expense,必须保持原样)
            editCategoryName: cat?.name,
            // 保存后 pop 回到调用方(流水页 / 报表 / 首页等)
            onSaved: () => context.pop(),
          );
        },
      ),
    );
  }
}
