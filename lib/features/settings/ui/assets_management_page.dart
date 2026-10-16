// lib/features/settings/ui/assets_management_page.dart
// 我的页"资产"全屏路由 —— 增删改查 + 顶部总资产汇总
//
// 2026-10-12 P2 commit 加:
//   - 全屏路由版(类比 budget_management_page),viewInsets 由 Scaffold 处理
//   - 顶部 AssetSummaryCard(总资产 + 6 大类汇总)
//   - 6 段 _Group 按 type 分(流动资金 / 投资 / 福利 / 债权 / 不动产 / 其它,D64.40 cash_flow UI label 改"流动资金"),无资产段不显示标题
//   - AppBar 加号按钮 → AssetFormPage(null) 新增
//   - 点 tile 或编辑 IconButton → AssetFormPage(existing) 编辑
//   - 删除 IconButton → confirmDelete dialog(FK check:被引用流水数 > 0 提示先改)
//   - 底部提示:删除账户时若已被流水引用,会被外键拒绝
//
// 2026-10-13 P6 commit:
//   - AssetFormSheet → AssetFormPage,从 showModalBottomSheet 改 MaterialPageRoute 整页
//   - _showForm 用 fullscreenDialog 过渡,新增/编辑完返回自然
//
// 跟 category_management_page.dart 镜像结构,确保 user 体验一致
//
// 2026-10-16 D64.50 改(user UAT 反馈):
//   - user 反馈"另外,如果'显示金额'这个关闭上的话,即不显示金额时,
//     打开资产管理这个页面也要隐藏所有的资产"
//   - 资产管理页含敏感信息:
//     ① AssetSummaryCard 净资产大字 + 6 段金额 + 末尾总资产小字
//     ② 资产 tile 列表每条 amount(¥-14,675.08 等)
//     ③ 借出/借入的金额
//   - 已有 PrivacyObscure 用在 流水 / 报表 / 交易表单 / 设置 / 关于页(D60.1 UAT 加),
//     资产管理页遗漏没加,user 截图分享或公开场合打开会泄露资产
//   - 修法:body 外面包一层 `PrivacyObscure`:
//     ① `amountVisibilityProvider=true` → 透传,无影响
//     ② `amountVisibilityProvider=false` → 整页盖主题色蒙版 + lock icon + "已隐藏",
//        配合 AbsorbPointer 拦截所有点击(包括 AssetSummaryCard / 资产 tile 列表 /
//        AppBar "+" 新增按钮都收不到 tap),防止借按钮入口跳走
//     ③ 切回 visible=true 时 child 已经 build 过在 tree 里(Stack 保留),
//        toggle 后无闪烁
//   - 不改 GestureDetector(它在外层包 PrivacyObscure 内,visible=false 时
//     AbsorbPointer 吸收 pointer,onTap 自然不触发,不需要额外改)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../../core/utils/open_swipe_id_provider.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/widgets/privacy_obscure.dart';
import 'widgets/asset_summary_card.dart';
import 'widgets/asset_tile.dart';

class AssetsManagementPage extends ConsumerWidget {
  const AssetsManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetsAsync = ref.watch(allAssetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showForm(context, null),
          ),
        ],
      ),
      body: PrivacyObscure(
        // D64.50:资产管理页加 PrivacyObscure(详见顶部注释),
        //   跟 stats_page / ledger_page / about_page 同样模式
        child: GestureDetector(
          // D64.42:资产 tile 也用 SwipeToActions 滑动操作,
          //   body 加 transparent GestureDetector,点空白处清 openSwipeIdProvider
          //   让"正在开的 tile 自动收回"(跟 ledger_page 同样模式)
          //   - HitTestBehavior.translucent:不拦截子 widget 的 tap
          //     (asset tile 自身 SwipeToActions.onTap 仍正常触发)
          //   - 真正的"外部点击关闭"靠 SwipeToActions 内的 ref.listen 检测
          //     provider 变 null 自动 spring 回 0
          behavior: HitTestBehavior.translucent,
          onTap: () => ref.read(openSwipeIdProvider.notifier).state = null,
          child: assetsAsync.when(
            data: (assets) {
              // 2026-10-13 P6:4 段 → 6 段分组(去'负债',加'投资/福利/债权')
              // 顺序按日常查看频度排:流动资金 → 投资 → 福利 → 债权 → 不动产 → 其它(D64.40)
              final cash = assets.where((a) => a.type == 'cash_flow').toList();
              final invest = assets
                  .where((a) => a.type == 'investment')
                  .toList();
              final benefit = assets.where((a) => a.type == 'benefit').toList();
              final recv = assets.where((a) => a.type == 'receivable').toList();
              final fixed = assets
                  .where((a) => a.type == 'fixed_asset')
                  .toList();
              final other = assets.where((a) => a.type == 'other').toList();
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                children: [
                  const AssetSummaryCard(),
                  const SizedBox(height: AppSpacing.s4),
                  if (cash.isNotEmpty)
                    _Group(
                      // D64.40:从 "现金流" 改 "流动资金"
                      title: '流动资金',
                      items: cash,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (invest.isNotEmpty)
                    _Group(
                      title: '投资',
                      items: invest,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (benefit.isNotEmpty)
                    _Group(
                      title: '福利',
                      items: benefit,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (recv.isNotEmpty)
                    _Group(
                      // 2026-10-14 D51 v2 改:user 反馈"负债"改"债务",口语更直观
                      // "负债"是法律会计词,用户日常用"债务"
                      title: '债务',
                      items: recv,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (fixed.isNotEmpty)
                    _Group(
                      title: '不动产',
                      items: fixed,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (other.isNotEmpty)
                    _Group(
                      title: '其它',
                      items: other,
                      onEdit: (a) => _showForm(context, a),
                      onDelete: (a) => _confirmDelete(context, ref, a),
                    ),
                  if (assets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.s4,
                        AppSpacing.s6,
                        AppSpacing.s4,
                        AppSpacing.s5,
                      ),
                      child: Center(
                        child: Text(
                          '还没有账户,点右上角 + 新建第一个',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.s4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                    child: Text(
                      '提示:删除账户时若已被流水引用,会被外键拒绝。请先把这些流水的账户改到其他地方。',
                      style: TextStyle(fontSize: 11, color: AppGray.g600),
                    ),
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败:$e')),
          ),
        ),
      ),
    );
  }

  void _showForm(BuildContext context, Asset? existing) {
    // 2026-10-13 P6:从 showModalBottomSheet 改为 MaterialPageRoute 整页
    // - 页面太长(6 段类型 + 8 icon + 16 调色板 + 期初余额 + 计入开关),sheet 太挤
    // - sheet 没有明显关闭/返回按钮,user 容易卡死
    // - 整页后 AppBar 自动有返回箭头 + 右上角"保存"check,操作闭环
    //
    // 2026-10-15 D64.20 改:Navigator.push → context.push('/settings/assets/edit', extra: existing)
    //   - 原因:raw Navigator.push 把 AssetFormPage 推到 shell sub-navigator,
    //     go_router 的 _findCurrentNavigator 找不到(canPop 因 PopScope 返 false)
    //     → Android 返回键直接退 app(见 D64.20 commit message)。
    //   - 改走 go_router 路线,AssetFormPage 在 root navigator 栈上,back 键正确路由。
    //   - 同时删除 D64.18 加的 PopScope 兜底,不再需要。
    context.push('/settings/assets/edit', extra: existing);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Asset a,
  ) async {
    final usage = await ref.read(assetRepositoryProvider).usageCount(a.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账户?'),
        content: Text(
          '「${a.name}」当前被 $usage 条流水引用。\n'
          '${usage > 0 ? "删除会失败,请先把引用改到其他账户。" : "确认删除?"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          if (usage == 0)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppStatus.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(assetRepositoryProvider).delete(a.id);
      refreshAllData(ref);
      ref.invalidate(allAssetsProvider);
      ref.invalidate(assetBalancesProvider);
      ref.invalidate(assetBalanceProvider);
      if (context.mounted) {
        showGridlyBanner(context, '已删除', kind: GridlyBannerKind.success);
      }
    } catch (e) {
      if (context.mounted) {
        showGridlyBanner(context, '删除失败:$e', kind: GridlyBannerKind.error);
      }
    }
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });
  final String title;
  final List<Asset> items;
  final ValueChanged<Asset> onEdit;
  final ValueChanged<Asset> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s3,
            AppSpacing.s4,
            AppSpacing.s1,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...items.map(
          (a) => AssetTile(
            asset: a,
            onEdit: () => onEdit(a),
            onDelete: () => onDelete(a),
          ),
        ),
      ],
    );
  }
}
