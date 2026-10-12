// lib/features/ledger/ui/advanced_filter_page.dart
// 流水页"高级筛选"全屏页 —— 替代 AppBar 弹出的紧凑 modal sheet
//
// 2026-10-13 新建:user UAT 反馈"高级筛选里加上资产条件,要不全屏显示 4 条件一行行"。
// 2026-10-13 第 2 次改:user UAT 反馈"高级筛选需要给一个确认或者搜索的按钮,
//   每种搜索条件不要复用原来底部弹出样式,直接展开式"。
//   - 加 sticky bottom "应用筛选" 按钮(Navigator.pop 关闭,filter 已实时生效)
//   - 4 条件 row 改成"点开展开式"——点 row 在 row 下方 inline 展开选项 list
//     (单选 radio / 多选 checkbox),不再弹底部 modal sheet
//   - 同时只能展开 1 个 row(点别的 row 会自动收起当前 row)
//   - 实时生效(选完 row 的选项立刻更新 provider,跟之前 _FilterSheet 行为一致),
//     "应用筛选" 按钮只是给 user 一个明确的"我筛选好了" 关闭动作
//   - 跟 in-page _FilterBar 3-dropdown 横滚条共存:_FilterBar 快速筛选
//     (3 个常用),_AdvancedFilterPage 完整 4 条件 + 搜索(深度筛选)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../application/transactions_providers.dart';

/// 高级筛选 —— 全屏页(navigator.push 进来)
class AdvancedFilterPage extends ConsumerStatefulWidget {
  const AdvancedFilterPage({super.key});

  @override
  ConsumerState<AdvancedFilterPage> createState() => _AdvancedFilterPageState();
}

class _AdvancedFilterPageState extends ConsumerState<AdvancedFilterPage> {
  late final TextEditingController _searchController;

  /// 当前展开的 section key(null = 全部收起)
  ///   合法值:'type' / 'month' / 'category' / 'asset'
  String? _expanded;

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

  void _toggleSection(String key) {
    setState(() {
      _expanded = _expanded == key ? null : key;
    });
  }

  // ============ label helpers ============

  String _typeLabel() {
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

  String _monthLabel() {
    final m = ref.watch(ledgerMonthFilterProvider);
    if (m == null) return '全部';
    final y = m ~/ 100;
    final mo = m % 100;
    return '$y 年 $mo 月';
  }

  String _categoryLabel(List<Category> catsForType) {
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

  String _assetLabel(List<Asset> allAssets) {
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

  // ============ active 检测 + 清空 ============

  bool _anyFilterActive() {
    return _searchController.text.isNotEmpty ||
        ref.read(ledgerTypeFilterProvider) != 'all' ||
        ref.read(ledgerMonthFilterProvider) != null ||
        ref.read(ledgerCategoryFilterProvider).isNotEmpty ||
        ref.read(ledgerAssetFilterProvider).isNotEmpty;
  }

  void _clearAll() {
    _searchController.clear();
    ref.read(ledgerSearchQueryProvider.notifier).state = '';
    ref.read(ledgerTypeFilterProvider.notifier).state = 'all';
    ref.read(ledgerMonthFilterProvider.notifier).state = null;
    ref.read(ledgerCategoryFilterProvider.notifier).state = <int>{};
    ref.read(ledgerAssetFilterProvider.notifier).state = <int>{};
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

  // ============ 各条件的选择器(单选 / 多选 inline list) ============

  void _selectType(String value) {
    ref.read(ledgerTypeFilterProvider.notifier).state = value;
  }

  void _selectMonth(int? value) {
    ref.read(ledgerMonthFilterProvider.notifier).state = value;
  }

  void _toggleCategory(int id) {
    final cur = {...ref.read(ledgerCategoryFilterProvider)};
    if (cur.contains(id)) {
      cur.remove(id);
    } else {
      cur.add(id);
    }
    ref.read(ledgerCategoryFilterProvider.notifier).state = cur;
  }

  void _toggleAsset(int id) {
    final cur = {...ref.read(ledgerAssetFilterProvider)};
    if (cur.contains(id)) {
      cur.remove(id);
    } else {
      cur.add(id);
    }
    ref.read(ledgerAssetFilterProvider.notifier).state = cur;
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
            onPressed: _anyFilterActive() ? _clearAll : null,
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
          // ============ 类型 row(单选) ============
          _SectionHeader(
            icon: Icons.category_outlined,
            label: '类型',
            value: _typeLabel(),
            active: typeFilter != 'all',
            expanded: _expanded == 'type',
            onTap: () => _toggleSection('type'),
          ),
          if (_expanded == 'type')
            _RadioOptionList<String>(
              options: const [
                ('all', '全部'),
                ('expense', '支出'),
                ('income', '收入'),
                ('balance', '调拨'),
              ],
              currentValue: typeFilter,
              onSelect: (v) => _selectType(v),
            ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 月份 row(单选) ============
          _SectionHeader(
            icon: Icons.calendar_today_outlined,
            label: '月份',
            value: _monthLabel(),
            active: monthFilter != null,
            expanded: _expanded == 'month',
            onTap: () => _toggleSection('month'),
          ),
          if (_expanded == 'month')
            _RadioOptionList<int?>(
              options: <(int?, String)>[
                (null, '全部'),
                ..._recentMonthKeys().map((k) => (k, _formatMonthKey(k))),
              ],
              currentValue: monthFilter,
              onSelect: (v) => _selectMonth(v),
            ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 分类 row(多选) ============
          _SectionHeader(
            icon: Icons.local_offer_outlined,
            label: '分类',
            value: _categoryLabel(catsForType),
            active: categoryFilter.isNotEmpty,
            expanded: _expanded == 'category',
            onTap: () => _toggleSection('category'),
          ),
          if (_expanded == 'category')
            _CheckboxCategoryList(
              categories: catsForType,
              selected: categoryFilter,
              onToggle: _toggleCategory,
            ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 资产 row(多选) ============
          _SectionHeader(
            icon: Icons.account_balance_wallet_outlined,
            label: '资产',
            value: _assetLabel(allAssets),
            active: assetFilter.isNotEmpty,
            expanded: _expanded == 'asset',
            onTap: () => _toggleSection('asset'),
          ),
          if (_expanded == 'asset')
            _CheckboxAssetList(
              assets: allAssets,
              selected: assetFilter,
              onToggle: _toggleAsset,
            ),
          const Divider(height: 1),
          // 底部留空,避免列表被应用按钮遮挡
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s2,
            AppSpacing.s4,
            AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 0.5,
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: theme.brightness == Brightness.dark
                    ? AppSecondary.cream
                    : AppBrand.ink,
                foregroundColor: theme.brightness == Brightness.dark
                    ? AppBrand.ink
                    : null,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
              ),
              child: const Text(
                '应用筛选',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 行 widget:section header(可点开展开)
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: (active || expanded)
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
              color: (active || expanded)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s3),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: (active || expanded)
                    ? FontWeight.w600
                    : FontWeight.w500,
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
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 单选 list(类型 / 月份)
//   - 每行 radio 风格,选中态 primary
//   - 展开时 inline 出现,高度自适应内容(最多 ~280px 后内部滚)
// ============================================================================

class _RadioOptionList<T> extends StatelessWidget {
  const _RadioOptionList({
    required this.options,
    required this.currentValue,
    required this.onSelect,
  });

  final List<(T, String)> options;
  final T currentValue;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (final (value, label) in options)
              InkWell(
                onTap: () => onSelect(value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        value == currentValue
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: value == currentValue
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: value == currentValue
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: value == currentValue
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 多选 list(分类)—— 带 category color dot
// ============================================================================

class _CheckboxCategoryList extends StatelessWidget {
  const _CheckboxCategoryList({
    required this.categories,
    required this.selected,
    required this.onToggle,
  });

  final List<Category> categories;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (categories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Text(
          '当前类型下没有可选分类',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (final c in categories)
              _CheckboxTile(
                key: ValueKey('cat-opt-${c.id}'),
                checked: selected.contains(c.id),
                color: Color(c.color),
                label: c.name,
                onTap: () => onToggle(c.id),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 多选 list(资产)—— 带 asset icon chip
// ============================================================================

class _CheckboxAssetList extends StatelessWidget {
  const _CheckboxAssetList({
    required this.assets,
    required this.selected,
    required this.onToggle,
  });

  final List<Asset> assets;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (assets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Text(
          '还没有账户,请到"我的 > 资产"新建',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (final a in assets)
              _CheckboxTile(
                key: ValueKey('asset-opt-${a.id}'),
                checked: selected.contains(a.id),
                color: Color(a.color),
                icon: _iconFor(a.icon),
                label: a.name,
                onTap: () => onToggle(a.id),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String iconKey) {
    switch (iconKey) {
      case 'credit_card':
        return Icons.credit_card_rounded;
      case 'savings':
        return Icons.savings_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'account_balance':
        return Icons.account_balance_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'directions_car':
        return Icons.directions_car_rounded;
      case 'swap_horiz':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }
}

// ============================================================================
// checkbox 风格单行(reuse 给分类 / 资产)
//   - 左 checked icon(实心 ✓ / 空心 ○)
//   - 中 icon(可选,资产)/ color dot(分类)+ label
//   - 选中态整行 tint 资产/分类配色 0.08
// ============================================================================

class _CheckboxTile extends StatelessWidget {
  const _CheckboxTile({
    super.key,
    required this.checked,
    required this.color,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final bool checked;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: checked ? color.withValues(alpha: 0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: checked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
            if (icon != null) ...[
              const SizedBox(width: AppSpacing.s3),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brXs,
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ] else ...[
              const SizedBox(width: AppSpacing.s3),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  color: checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
