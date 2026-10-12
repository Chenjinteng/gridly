// lib/features/ledger/ui/advanced_filter_page.dart
// 流水页"高级筛选"全屏页 —— 替代 AppBar 弹出的紧凑 modal sheet
//
// 2026-10-13 新建:user UAT 反馈"高级筛选里加上资产条件,要不全屏显示 4 条件一行行"。
//   设计:
//     - AppBar 入口 ⚙️ filter_alt → 推全屏页(navigator.push),不用 modal sheet
//     - 顶部搜索框(搜备注/分类),实时写入 ledgerSearchQueryProvider
//     - 4 个条件 row-by-row:类型 / 月份 / 分类 / 资产,每行 tap 弹底部 modal sheet picker
//     - 每行右侧显示当前值(label) + chevron_right,激活态 tint primary
//     - AppBar 右上"清空"按钮一键清所有筛选
//     - 实时生效(跟之前 _FilterSheet 行为一致),不需"应用"按钮
//     - 跟 in-page _FilterBar 3-dropdown 横滚条共存:_FilterBar 快速筛选
//       (3 个常用),_AdvancedFilterPage 完整 4 条件 + 搜索(深度筛选)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../../../core/utils/gridly_banner.dart';
import '../application/transactions_providers.dart';
import 'filter_picker_sheets.dart';

/// 高级筛选 —— 全屏页(navigator.push 进来)
class AdvancedFilterPage extends ConsumerStatefulWidget {
  const AdvancedFilterPage({super.key});

  @override
  ConsumerState<AdvancedFilterPage> createState() => _AdvancedFilterPageState();
}

class _AdvancedFilterPageState extends ConsumerState<AdvancedFilterPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    // 初始值取自当前 provider(从 ledger_page.dart 跳过来时已有 filter active)
    _searchController = TextEditingController(
      text: ref.read(ledgerSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _anyFilterActive(WidgetRef ref) {
    return _searchController.text.isNotEmpty ||
        ref.read(ledgerTypeFilterProvider) != 'all' ||
        ref.read(ledgerMonthFilterProvider) != null ||
        ref.read(ledgerCategoryFilterProvider).isNotEmpty ||
        ref.read(ledgerAssetFilterProvider).isNotEmpty;
  }

  String _typeLabel(WidgetRef ref) {
    switch (ref.watch(ledgerTypeFilterProvider)) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      case 'balance':
        return '调拨';
      default:
        return '全部';
    }
  }

  String _monthLabel(WidgetRef ref) {
    final m = ref.watch(ledgerMonthFilterProvider);
    if (m == null) return '全部';
    final y = m ~/ 100;
    final mo = m % 100;
    return '$y 年 $mo 月';
  }

  String _categoryLabel(WidgetRef ref, List<Category> catsForType) {
    final cs = ref.watch(ledgerCategoryFilterProvider);
    if (cs.isEmpty) return '全部';
    if (cs.length == 1) {
      final id = cs.first;
      for (final c in catsForType) {
        if (c.id == id) return c.name;
      }
    }
    return '已选 ${cs.length} 个';
  }

  String _assetLabel(WidgetRef ref, List<Asset> allAssets) {
    final as = ref.watch(ledgerAssetFilterProvider);
    if (as.isEmpty) return '全部';
    if (as.length == 1) {
      final id = as.first;
      for (final a in allAssets) {
        if (a.id == id) return a.name;
      }
    }
    return '已选 ${as.length} 个';
  }

  void _clearAll() {
    _searchController.clear();
    ref.read(ledgerSearchQueryProvider.notifier).state = '';
    ref.read(ledgerTypeFilterProvider.notifier).state = 'all';
    ref.read(ledgerMonthFilterProvider.notifier).state = null;
    ref.read(ledgerCategoryFilterProvider.notifier).state = <int>{};
    ref.read(ledgerAssetFilterProvider.notifier).state = <int>{};
  }

  // ============ 4 条件 picker 触发 ============

  Future<void> _pickType(List<Category> catsForType) async {
    final options = <(Object?, String)>[
      (allPicked, '全部'),
      ('expense', '支出'),
      ('income', '收入'),
      ('balance', '调拨'),
    ];
    final selected = await showSingleSelectSheet<String>(
      context,
      title: '选择类型',
      options: options,
      currentValue: ref.read(ledgerTypeFilterProvider),
    );
    if (selected == null || selected is SheetDismissed) return;
    if (selected is AllPicked) {
      ref.read(ledgerTypeFilterProvider.notifier).state = 'all';
      return;
    }
    ref.read(ledgerTypeFilterProvider.notifier).state = selected as String;
  }

  Future<void> _pickMonth() async {
    final monthKeys = _recentMonthKeys();
    final options = <(Object?, String)>[
      (allPicked, '全部'),
      ...monthKeys.map((k) => (k, _formatMonthKey(k))),
    ];
    final selected = await showSingleSelectSheet<int?>(
      context,
      title: '选择月份',
      options: options,
      currentValue: ref.read(ledgerMonthFilterProvider),
    );
    if (selected == null || selected is SheetDismissed) return;
    if (selected is AllPicked) {
      ref.read(ledgerMonthFilterProvider.notifier).state = null;
      return;
    }
    ref.read(ledgerMonthFilterProvider.notifier).state = selected as int?;
  }

  Future<void> _pickCategory(List<Category> catsForType) async {
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => MultiSelectCategorySheet(
        categories: catsForType,
        initial: ref.read(ledgerCategoryFilterProvider),
      ),
    );
    if (selected != null) {
      ref.read(ledgerCategoryFilterProvider.notifier).state = selected;
    }
  }

  Future<void> _pickAsset(List<Asset> allAssets) async {
    if (allAssets.isEmpty) {
      if (!mounted) return;
      showGridlyBanner(
        context,
        '还没有账户,请先到"我的 > 资产"新建',
        kind: GridlyBannerKind.info,
      );
      return;
    }
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => MultiSelectAssetSheet(
        assets: allAssets,
        initial: ref.read(ledgerAssetFilterProvider),
      ),
    );
    if (selected != null) {
      ref.read(ledgerAssetFilterProvider.notifier).state = selected;
    }
  }

  // ============ 月份 helper ============

  /// 最近 12 个月(含本月),按时间倒序
  static List<int> _recentMonthKeys() {
    final now = DateTime.now();
    final list = <int>[];
    var y = now.year;
    var m = now.month;
    for (var i = 0; i < 12; i++) {
      list.add(y * 100 + m);
      m--;
      if (m == 0) {
        m = 12;
        y--;
      }
    }
    return list;
  }

  static String _formatMonthKey(int key) {
    final y = key ~/ 100;
    final m = key % 100;
    return '$y 年 $m 月';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final typeFilter = ref.watch(ledgerTypeFilterProvider);
    final monthFilter = ref.watch(ledgerMonthFilterProvider);
    final categoryFilter = ref.watch(ledgerCategoryFilterProvider);
    final assetFilter = ref.watch(ledgerAssetFilterProvider);
    final allAssetsAsync = ref.watch(allAssetsProvider);
    final allAssets = allAssetsAsync.valueOrNull ?? const <Asset>[];

    final catsForType = typeFilter == 'all'
        ? allCats
        : allCats.where((c) => c.type == typeFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('高级筛选'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _anyFilterActive(ref) ? _clearAll : null,
            child: const Text('清空'),
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s2,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) =>
                  ref.read(ledgerSearchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: '搜备注 / 分类',
                hintStyle: const TextStyle(color: AppGray.g400, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppGray.g600,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppGray.g600,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(ledgerSearchQueryProvider.notifier).state =
                              '';
                        },
                      ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s2,
                  vertical: AppSpacing.s2,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.brMd,
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.brMd,
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          // 4 条件 row-by-row
          _FilterRow(
            icon: Icons.category_outlined,
            label: '类型',
            value: _typeLabel(ref),
            active: typeFilter != 'all',
            onTap: () => _pickType(catsForType),
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          _FilterRow(
            icon: Icons.calendar_today_outlined,
            label: '月份',
            value: _monthLabel(ref),
            active: monthFilter != null,
            onTap: _pickMonth,
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          _FilterRow(
            icon: Icons.local_offer_outlined,
            label: '分类',
            value: _categoryLabel(ref, catsForType),
            active: categoryFilter.isNotEmpty,
            onTap: () => _pickCategory(catsForType),
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          _FilterRow(
            icon: Icons.account_balance_wallet_outlined,
            label: '资产',
            value: _assetLabel(ref, allAssets),
            active: assetFilter.isNotEmpty,
            onTap: () => _pickAsset(allAssets),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

/// 高级筛选页内的单行 condition(row by row)
///   - 左 icon + label
///   - 中间 value(选中态 tint primary)
///   - 右 chevron_right
///   - active 态:整行背景 tint primary 0.04
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s4,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s3),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
