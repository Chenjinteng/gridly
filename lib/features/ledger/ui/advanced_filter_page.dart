// lib/features/ledger/ui/advanced_filter_page.dart
// 流水页"高级筛选"全屏页 —— 替代 AppBar 弹出的紧凑 modal sheet
//
// 2026-10-13 新建:user UAT 反馈"高级筛选里加上资产条件,要不全屏显示 4 条件一行行"。
// 2026-10-13 第 2 次改:加 sticky bottom "应用筛选" 按钮 + 4 条件 inline 展开。
// 2026-10-13 第 3 次改:user UAT 反馈"高级筛选里面的所有都可以进行多选,
//   并且 inline 需要像 coloros 一样上一些下拉的丝滑动画"。
//   - 4 条件全部多选(类型/月份/分类/资产)— 类型从 String 改 Set<String>,
//     月份从 int? 改 Set<int>(provider 同步升级,filter 逻辑走 OR)
//   - 类型列表去掉"全部"选项(空 Set = 全部),改 checkbox 风格
//   - 月份列表去掉"全部"选项(空 Set = 全部),改 checkbox 风格
//   - inline 展开加 ColorOS 风格动画:AnimatedSize 320ms easeOutCubic +
//     列表项 30ms 错峰 fade-in + 内容 8px 上推下滑入
//   - 同时间只展开 1 个 row(tap 别的 row 自动收起当前 row,带 240ms 反向动画)
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

  // ============ label helpers(全部支持 Set 多选)============

  String _typeLabel() {
    final s = ref.watch(ledgerTypeFilterProvider);
    if (s.isEmpty) return '全部';
    if (s.length == 1) {
      switch (s.first) {
        case 'expense':
          return '支出';
        case 'income':
          return '收入';
        case 'balance':
          return '调拨';
      }
    }
    return '已选 ${s.length} 项';
  }

  String _monthLabel() {
    final s = ref.watch(ledgerMonthFilterProvider);
    if (s.isEmpty) return '全部';
    if (s.length == 1) {
      final k = s.first;
      return '${k ~/ 100} 年 ${k % 100} 月';
    }
    return '已选 ${s.length} 个月';
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
        ref.read(ledgerTypeFilterProvider).isNotEmpty ||
        ref.read(ledgerMonthFilterProvider).isNotEmpty ||
        ref.read(ledgerCategoryFilterProvider).isNotEmpty ||
        ref.read(ledgerAssetFilterProvider).isNotEmpty;
  }

  void _clearAll() {
    _searchController.clear();
    ref.read(ledgerSearchQueryProvider.notifier).state = '';
    ref.read(ledgerTypeFilterProvider.notifier).state = <String>{};
    ref.read(ledgerMonthFilterProvider.notifier).state = <int>{};
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

  // ============ 各条件多选 toggle(空 Set = 全部)============

  void _toggleType(String value) {
    final cur = {...ref.read(ledgerTypeFilterProvider)};
    if (cur.contains(value)) {
      cur.remove(value);
    } else {
      cur.add(value);
    }
    ref.read(ledgerTypeFilterProvider.notifier).state = cur;
  }

  void _toggleMonth(int value) {
    final cur = {...ref.read(ledgerMonthFilterProvider)};
    if (cur.contains(value)) {
      cur.remove(value);
    } else {
      cur.add(value);
    }
    ref.read(ledgerMonthFilterProvider.notifier).state = cur;
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

    // 2026-10-13:类型 filter 改 Set<String>,catsForType 走"空 = 全部,非空 = OR"
    final catsForType = typeFilter.isEmpty
        ? allCats
        : allCats.where((c) => typeFilter.contains(c.type)).toList();

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
          // ============ 类型 row(多选,空 = 全部)============
          _SectionHeader(
            icon: Icons.category_outlined,
            label: '类型',
            value: _typeLabel(),
            active: typeFilter.isNotEmpty,
            expanded: _expanded == 'type',
            onTap: () => _toggleSection('type'),
          ),
          _ExpandableList(
            expanded: _expanded == 'type',
            child: _CheckboxOptionList<String>(
              options: const [
                ('expense', '支出'),
                ('income', '收入'),
                ('balance', '调拨'),
              ],
              selected: typeFilter,
              onToggle: _toggleType,
            ),
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 月份 row(多选,空 = 全部)============
          _SectionHeader(
            icon: Icons.calendar_today_outlined,
            label: '月份',
            value: _monthLabel(),
            active: monthFilter.isNotEmpty,
            expanded: _expanded == 'month',
            onTap: () => _toggleSection('month'),
          ),
          _ExpandableList(
            expanded: _expanded == 'month',
            child: _CheckboxOptionList<int>(
              options: _recentMonthKeys()
                  .map((k) => (k, '${k ~/ 100} 年 ${k % 100} 月'))
                  .toList(),
              selected: monthFilter,
              onToggle: _toggleMonth,
            ),
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 分类 row(多选)============
          _SectionHeader(
            icon: Icons.local_offer_outlined,
            label: '分类',
            value: _categoryLabel(catsForType),
            active: categoryFilter.isNotEmpty,
            expanded: _expanded == 'category',
            onTap: () => _toggleSection('category'),
          ),
          _ExpandableList(
            expanded: _expanded == 'category',
            child: _CheckboxCategoryList(
              categories: catsForType,
              selected: categoryFilter,
              onToggle: _toggleCategory,
            ),
          ),
          const Divider(
            height: 1,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          // ============ 资产 row(多选)============
          _SectionHeader(
            icon: Icons.account_balance_wallet_outlined,
            label: '资产',
            value: _assetLabel(allAssets),
            active: assetFilter.isNotEmpty,
            expanded: _expanded == 'asset',
            onTap: () => _toggleSection('asset'),
          ),
          _ExpandableList(
            expanded: _expanded == 'asset',
            child: _CheckboxAssetList(
              assets: allAssets,
              selected: assetFilter,
              onToggle: _toggleAsset,
            ),
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
// 行 widget:section header(可点开展开) + AnimatedRotation chevron
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
            // 2026-10-13:chevron 旋转 + 同时透明度 1.0(展开时强调)
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
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
// ColorOS 风格 inline 展开容器
//   - AnimatedSize 高度 0 ↔ 内容高度,320ms easeOutCubic(比 M3 长,水感)
//   - ClipRect 防止内容溢出
//   - 用 AnimatedSlide 8px 上推下滑入(模拟下拉)
//
// ListView 内部子项用 _StaggeredItem 包 30ms 错峰 fade-in(总 ≤200ms),
// 模拟 ColorOS 列表项进场
// ============================================================================

class _ExpandableList extends StatelessWidget {
  const _ExpandableList({required this.expanded, required this.child});
  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: expanded
            ? AnimatedSlide(
                offset: Offset.zero,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 280),
                  child: child,
                ),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

// ============================================================================
// 多选通用 list(类型 / 月份)— 纯文字 checkbox
//   复用 _CheckboxTile
// ============================================================================

class _CheckboxOptionList<T> extends StatelessWidget {
  const _CheckboxOptionList({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<(T, String)> options;
  final Set<T> selected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (var i = 0; i < options.length; i++)
              _StaggeredItem(
                index: i,
                child: _CheckboxTile(
                  key: ValueKey('opt-${options[i].$1}'),
                  checked: selected.contains(options[i].$1),
                  label: options[i].$2,
                  onTap: () => onToggle(options[i].$1),
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
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (var i = 0; i < categories.length; i++)
              _StaggeredItem(
                index: i,
                child: _CheckboxTile(
                  key: ValueKey('cat-opt-${categories[i].id}'),
                  checked: selected.contains(categories[i].id),
                  color: Color(categories[i].color),
                  label: categories[i].name,
                  onTap: () => onToggle(categories[i].id),
                ),
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
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          children: [
            for (var i = 0; i < assets.length; i++)
              _StaggeredItem(
                index: i,
                child: _CheckboxTile(
                  key: ValueKey('asset-opt-${assets[i].id}'),
                  checked: selected.contains(assets[i].id),
                  color: Color(assets[i].color),
                  icon: _iconFor(assets[i].icon),
                  label: assets[i].name,
                  onTap: () => onToggle(assets[i].id),
                ),
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
// checkbox 风格单行(reuse 给类型 / 月份 / 分类 / 资产)
//   - 左 checked icon(实心 ✓ / 空心 ○)
//   - 中 icon(可选,资产)/ color dot(分类)+ label
//   - 选中态整行 tint 资产/分类配色 0.08
// ============================================================================

class _CheckboxTile extends StatelessWidget {
  const _CheckboxTile({
    super.key,
    required this.checked,
    required this.label,
    required this.onTap,
    this.color,
    this.icon,
  });

  final bool checked;
  final Color? color;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: checked ? tint.withValues(alpha: 0.08) : Colors.transparent,
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
                  color: tint.withValues(alpha: 0.12),
                  borderRadius: AppRadius.brXs,
                  border: Border.all(
                    color: tint.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Icon(icon, color: tint, size: 16),
              ),
            ] else if (color != null) ...[
              const SizedBox(width: AppSpacing.s3),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: tint,
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

// ============================================================================
// 错峰进场 item — 30ms × index delay,240ms fade-in + 8px 上推
//   模拟 ColorOS 列表项"水流式" 进场
// ============================================================================

class _StaggeredItem extends StatefulWidget {
  const _StaggeredItem({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<_StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04), // 8/200 = 4% down → slide up
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    // 30ms 错峰 delay,模拟逐项进场
    Future.delayed(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
