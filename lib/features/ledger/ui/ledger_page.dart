// lib/features/ledger/ui/ledger_page.dart
// 流水(读):3 个下拉筛选(类型 / 月份 / 分类)+ 搜索 + 按日分组 ListView + 空状态
// 分类支持多选(OR 关系),弹 modal bottom sheet
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/staggered_fade_in.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/gridly_banner.dart';
import '../../../core/utils/refresh_providers.dart';
import '../application/transactions_providers.dart';
import 'widgets/transaction_tile.dart';

/// Sentinel —— ModalBottomSheet dismiss 时返回,跟"选了全部"区分开
class _SheetDismissed {
  const _SheetDismissed();
}

const _sheetDismissed = _SheetDismissed();

/// Sentinel —— 用户明确点了"全部"项(等价于 reset 到默认值)
class _AllPicked {
  const _AllPicked();
}

const _allPicked = _AllPicked();

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  final _searchController = TextEditingController();
  // 搜索状态(2026-10-12 P5 follow-up 第 2 次改):搜索输入搬到 _FilterSheet 顶部,
  //   不再切 AppBar title;controller 仍由 _LedgerPageState 持有(关闭 sheet
  //   后再次打开保留搜索内容);searching 标志由 ledgerSearchQueryProvider 推导。

  /// 2026-10-12 ColorOS 列表错峰 fade-in:
  ///   - false:首次 build 阶段,所有 tile 走 _StaggeredTile 动画分支,
  ///     按 section 内 index 30ms 递增 fade + 上推 8px,360ms aquaIn
  ///   - true:首次 build 后下一帧翻为 true,filter 切换 / 滚动新 item 不重放
  ///     避免每次 filter 切换都全表 fade(性能 + 视觉都不会)
  bool _appeared = false;

  @override
  void initState() {
    super.initState();
    // 第一帧渲染后立即翻 true,触发一次额外 rebuild,这次 rebuild 走
    // no-animation 分支。新出现的滚动 item 也走 no-animation 分支。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _appeared = true);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 2026-10-12 P5 follow-up 第 2 次改:_toggleSearch 删除,搜索/清空逻辑搬到
  //   _FilterSheet 内的搜索 TextField + 底部"清空筛选"按钮。
  bool _anyFilterActive(WidgetRef ref) {
    return ref.watch(ledgerTypeFilterProvider) != 'all' ||
        ref.watch(ledgerMonthFilterProvider) != null ||
        ref.watch(ledgerCategoryFilterProvider).isNotEmpty ||
        ref.watch(ledgerAssetFilterProvider).isNotEmpty ||
        ref.watch(ledgerSearchQueryProvider).isNotEmpty;
  }

  /// 2026-10-12 P5 follow-up 第 2 次改:打开"搜索 + 筛选"sheet
  ///   - 顶部搜索框(搜备注 / 分类)+ 4 维度 pill
  ///   - AppBar 只留 filter_alt 一个入口,合并搜索避免两个按钮拥挤
  void _openFilterSheet({
    required List<Asset> allAssets,
    required List<Category> catsForType,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) => _FilterSheet(
        searchController: _searchController,
        onSearchChanged: (v) =>
            ref.read(ledgerSearchQueryProvider.notifier).state = v,
        currentType: ref.read(ledgerTypeFilterProvider),
        currentMonth: ref.read(ledgerMonthFilterProvider),
        currentCategory: ref.read(ledgerCategoryFilterProvider),
        currentAsset: ref.read(ledgerAssetFilterProvider),
        catsForType: catsForType,
        monthKeys: _recentMonthKeys(),
        formatMonthKey: _formatMonthKey,
        allAssets: allAssets,
        onTypeChanged: (v) =>
            ref.read(ledgerTypeFilterProvider.notifier).state = v,
        onMonthChanged: (v) =>
            ref.read(ledgerMonthFilterProvider.notifier).state = v,
        onCategoryChanged: (v) =>
            ref.read(ledgerCategoryFilterProvider.notifier).state = v,
        onAssetChanged: (v) =>
            ref.read(ledgerAssetFilterProvider.notifier).state = v,
      ),
    );
  }

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
    final filteredAsync = ref.watch(filteredTransactionsByDayProvider);
    final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final typeFilter = ref.watch(ledgerTypeFilterProvider);
    final monthFilter = ref.watch(ledgerMonthFilterProvider);
    final categoryFilter = ref.watch(ledgerCategoryFilterProvider);
    // 2026-10-12 P5 follow-up 加回:资产 filter(默认空,不参与过滤)
    // 资产列表(给 AppBar filter sheet 用)— 提前 watch
    final allAssetsAsync = ref.watch(allAssetsProvider);
    // 搜索 query(用于 _EmptyState 显示"没找到匹配的"提示)
    final searchQuery = ref.watch(ledgerSearchQueryProvider);

    final catsForType = typeFilter == 'all'
        ? allCats
        : allCats.where((c) => c.type == typeFilter).toList();

    return Scaffold(
      appBar: AppBar(
        // 2026-10-12 P5 follow-up 第 2 次改:搜索 + 过滤合并到 AppBar filter_alt 图标
        //   - 搜索输入框搬到 _FilterSheet 顶部(用户偏好"同操作只保留一个入口")
        //   - 标题固定 '流水',不再切 search field
        title: const Text('流水'),
        actions: [
          // 2026-10-12 P5 follow-up 加:AppBar 右上角 filter 按钮
          //   弹多维筛选 sheet:搜索 + 类型 / 月份 / 分类 / 资产
          //   icon 在有任意筛选激活时 tint primary 色,user 一眼看到"在筛选中"
          IconButton(
            icon: Icon(
              Icons.filter_alt_rounded,
              color: _anyFilterActive(ref)
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => _openFilterSheet(
              allAssets: allAssetsAsync.valueOrNull ?? const [],
              catsForType: catsForType,
            ),
          ),
        ],
      ),
      body: GestureDetector(
        // 点 body 空白处收起键盘(2026-10-11 UAT 反馈):
        //   - 搜备注/分类的 TextField 在 AppBar,聚焦后想退出只能按"完成",
        //     用户希望点 body 任意非输入处也能 unfocus
        // + 同时清掉 openSwipeTileIdProvider(2026-10-11 UAT 反馈):
        //   - 左滑开的 tile 在外面任何地方点击都得收回(避免"卡着")
        //   - 流水 tile 自己有 GestureDetector.onTap 也调 _close,这里再清一次
        //     是冗余但无害;真正的"外部点击关闭"靠 tile 里的 ref.listen 触发
        // - HitTestBehavior.translucent:不拦截子 widget 的点击(下拉 / 流水 tile
        //   自己有 InkWell / GestureDetector 处理 tap),只在没有 child 消费的
        //   位置才落到 onTap
        // - 用 FocusScope 而非 FocusManager:跟 Material / Scaffold 默认
        //   焦点范围对齐,不会误清掉 dialog / sheet 里的 focus
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
          ref.read(openSwipeTileIdProvider.notifier).state = null;
        },
        child: Column(
          children: [
            _FilterBar(
              typeFilter: typeFilter,
              monthFilter: monthFilter,
              categoryFilter: categoryFilter,
              catsForType: catsForType,
              monthKeys: _recentMonthKeys(),
              formatMonthKey: _formatMonthKey,
              onTypeChanged: (v) =>
                  ref.read(ledgerTypeFilterProvider.notifier).state = v,
              onMonthChanged: (v) =>
                  ref.read(ledgerMonthFilterProvider.notifier).state = v,
              onCategoryChanged: (v) =>
                  ref.read(ledgerCategoryFilterProvider.notifier).state = v,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => refreshAllData(ref),
                // AlwaysScrollableScrollPhysics:即使空态/内容不满一屏也能下拉触发刷新
                child: filteredAsync.when(
                  data: (grouped) {
                    if (grouped.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          _EmptyState(searching: searchQuery.isNotEmpty),
                        ],
                      );
                    }
                    final days = grouped.keys.toList()
                      ..sort((a, b) => b.compareTo(a));
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(
                        top: AppSpacing.s2,
                        bottom: AppSpacing.s6,
                      ),
                      itemCount: days.length,
                      itemBuilder: (context, i) {
                        final day = days[i];
                        final txs = grouped[day]!;
                        return _DaySection(
                          day: day,
                          transactions: txs,
                          // 首次进入页面时为所有 tile 触发错峰 fade-in,
                          // _appeared 翻转后(filter 切换 / 滚动)不再重放
                          animateStagger: !_appeared,
                        );
                      },
                    );
                  },
                  loading: () => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: CircularProgressIndicator()),
                    ],
                  ),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(child: Text('加载失败:$e')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选条 —— 3 个 dropdown 按钮横向均分(类型 / 月份 / 分类),点击弹 modal bottom sheet 单选/多选
/// 任意筛选激活时,右侧出现"清空"快捷按钮
///
/// 2026-10-12 P3 follow-up commit:从 4 dropdown(P3 加资产维度)退回 3 dropdown 一行布局。
///   user 反馈"4 个筛选太多长了,按之前的来只占一行就行"。
///   资产维度不上 UI(ledgerAssetFilterProvider 已删,流水 tile 仍显示账户名作为视觉信息)。
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.typeFilter,
    required this.monthFilter,
    required this.categoryFilter,
    required this.catsForType,
    required this.monthKeys,
    required this.formatMonthKey,
    required this.onTypeChanged,
    required this.onMonthChanged,
    required this.onCategoryChanged,
  });

  final String typeFilter;
  final int? monthFilter;
  final Set<int> categoryFilter;
  final List<Category> catsForType;
  final List<int> monthKeys;
  final String Function(int) formatMonthKey;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<Set<int>> onCategoryChanged;

  bool get _hasActiveFilter =>
      typeFilter != 'all' || monthFilter != null || categoryFilter.isNotEmpty;

  void _clearAll(WidgetRef ref) {
    ref.read(ledgerTypeFilterProvider.notifier).state = 'all';
    ref.read(ledgerMonthFilterProvider.notifier).state = null;
    ref.read(ledgerCategoryFilterProvider.notifier).state = <int>{};
  }

  String _typeLabel() {
    switch (typeFilter) {
      case 'expense':
        return '支出';
      case 'income':
        return '收入';
      default:
        return '全部';
    }
  }

  String _monthLabel() =>
      monthFilter == null ? '全部' : formatMonthKey(monthFilter!);

  String _categoryLabel() {
    if (categoryFilter.isEmpty) return '全部';
    if (categoryFilter.length == 1) {
      final id = categoryFilter.first;
      for (final c in catsForType) {
        if (c.id == id) return c.name;
      }
    }
    return '已选 ${categoryFilter.length} 个';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DropdownField(
              label: '类型',
              value: _typeLabel(),
              active: typeFilter != 'all',
              onTap: () => _showTypePicker(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _DropdownField(
              label: '月份',
              value: _monthLabel(),
              active: monthFilter != null,
              onTap: () => _showMonthPicker(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _DropdownField(
              label: '分类',
              value: _categoryLabel(),
              active: categoryFilter.isNotEmpty,
              onTap: () => _showCategoryPicker(context),
            ),
          ),
          // 仅当有任意筛选激活时,显示"清空"按钮,避免挤占默认 UI
          if (_hasActiveFilter) ...[
            const SizedBox(width: AppSpacing.s2),
            _ClearButton(onTap: () => _clearAll(ref)),
          ],
        ],
      ),
    );
  }

  // ============ 弹层:类型(单选) ============
  Future<void> _showTypePicker(BuildContext context) async {
    final options = <(Object?, String)>[
      (_allPicked, '全部'),
      ('expense', '支出'),
      ('income', '收入'),
    ];
    final selected = await _showSingleSelectSheet<String>(
      context,
      title: '选择类型',
      options: options,
      currentValue: typeFilter,
    );
    if (selected == null || selected is _SheetDismissed) return;
    if (selected is _AllPicked) {
      onTypeChanged('all');
      return;
    }
    onTypeChanged(selected as String);
  }

  // ============ 弹层:月份(单选) ============
  Future<void> _showMonthPicker(BuildContext context) async {
    final options = <(Object?, String)>[
      (_allPicked, '全部'),
      ...monthKeys.map((k) => (k, formatMonthKey(k))),
    ];
    final selected = await _showSingleSelectSheet<int?>(
      context,
      title: '选择月份',
      options: options,
      currentValue: monthFilter,
    );
    if (selected == null || selected is _SheetDismissed) return;
    // 选"全部" → 触发 onMonthChanged(null) 重置
    if (selected is _AllPicked) {
      onMonthChanged(null);
      return;
    }
    onMonthChanged(selected as int?);
  }

  // ============ 弹层:分类(多选) ============
  Future<void> _showCategoryPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => _MultiSelectCategorySheet(
        categories: catsForType,
        initial: categoryFilter,
      ),
    );
    if (selected != null) onCategoryChanged(selected);
  }

  // 2026-10-12 P3 follow-up commit:删 _showAssetPicker(资产筛选 UI 不上,
  //   流水 tile 仍显示账户名作为视觉信息)。
}

/// 单选弹层(类型 / 月份)—— 选完自动关闭
///
/// ⚠️ 关键修复:用两个 sentinel 严格区分:
///   - _SheetDismissed → barrier dismiss / "关闭"按钮(没操作)
///   - _AllPicked → 用户明确点"全部"(要 reset 到默认值)
///   - 其他 value → 用户点了某个具体选项
/// 选项用 `Object?` 而非 T,因为"全部"用 sentinel 不能跟 T 类型混
Future<Object?> _showSingleSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<(Object?, String)> options,
  required T currentValue,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.s2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 12),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, _sheetDismissed),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final (value, label) = options[i];
                    // 选中态判断:value 是 _allPicked 且 currentValue 是 null
                    final selected =
                        (value is _AllPicked && currentValue == null) ||
                        (value == currentValue);
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                          vertical: AppSpacing.s3,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            if (selected)
                              Icon(
                                Icons.check,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 多选弹层(分类)—— 临时持有选择集合,点"确定"才提交
class _MultiSelectCategorySheet extends StatefulWidget {
  const _MultiSelectCategorySheet({
    required this.categories,
    required this.initial,
  });
  final List<Category> categories;
  final Set<int> initial;

  @override
  State<_MultiSelectCategorySheet> createState() =>
      _MultiSelectCategorySheetState();
}

class _MultiSelectCategorySheetState extends State<_MultiSelectCategorySheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择分类(可多选)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.categories.length,
                itemBuilder: (_, i) {
                  final c = widget.categories[i];
                  final checked = _selected.contains(c.id);
                  final color = Color(c.color);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(c.id);
                      } else {
                        _selected.add(c.id);
                      }
                    }),
                    child: Container(
                      color: checked
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              c.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (checked)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  style: FilledButton.styleFrom(
                    // dark mode 仿 onDark:ink → cream
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                  ),
                  child: Text(
                    _selected.isEmpty ? '显示全部' : '确定(${_selected.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 2026-10-12 P3 commit 加:多选弹层(资产)—— 跟 _MultiSelectCategorySheet 同款结构
///   - 行 item:asset icon chip + name + currentBalance(右对齐)
///   - 选中态:整行背景 tint asset 配色 + check icon
///   - 顶部标题"选择账户(可多选)" + 清空 + 底部"显示全部 / 确定(N)"
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.brMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 清空按钮 —— 仅当有任意筛选激活时出现
class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: AppRadius.brMd,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.close,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            Text(
              '清空',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppBrand.teal.withValues(alpha: 0.1),
              borderRadius: AppRadius.brLg,
            ),
            child: Icon(
              searching ? Icons.search_off_outlined : Icons.inbox_outlined,
              size: 36,
              color: AppBrand.teal,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            searching ? '没找到匹配的流水' : '还没有流水',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: AppSpacing.s1),
          Text(
            searching ? '试试其他筛选条件' : '点中央的"+"记一笔',
            style: const TextStyle(color: AppGray.g600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.transactions,
    required this.animateStagger,
  });
  final DateTime day;
  final List<Transaction> transactions;

  /// true:section 内 tile 按 index 错峰 30ms fade-in(只首次进入页面触发)
  /// false:直接显示(filter 切换 / 滚动新 item 不重放)
  final bool animateStagger;

  @override
  Widget build(BuildContext context) {
    final dailyExpense = transactions
        .where((t) => t.type == 'expense')
        .fold<double>(0, (sum, t) => sum + t.amount);
    final dailyIncome = transactions
        .where((t) => t.type == 'income')
        .fold<double>(0, (sum, t) => sum + t.amount);
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatters.dayHeader(day),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppGray.g600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  if (dailyIncome > 0)
                    Text(
                      '+¥${Formatters.amount(dailyIncome)} ',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppBrand.gold,
                      ),
                    ),
                  if (dailyExpense > 0)
                    Text(
                      '-¥${Formatters.amount(dailyExpense)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppStatus.error,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // 2026-10-12 错峰 fade-in:section 内 tile 按 index 30ms 递增。
        // animateStagger=false 时退化为普通 TransactionTile,无额外开销
        ...transactions.asMap().entries.map(
          (e) => StaggeredFadeIn(
            index: e.key,
            enabled: animateStagger,
            child: TransactionTile(transaction: e.value),
          ),
        ),
      ],
    );
  }
}

/// 2026-10-12 P5 follow-up 加:AppBar filter 按钮 → 多维筛选 sheet
///   - 4 维度 pill:类型 / 月份 / 分类 / 资产,各点开弹对应 picker sheet
///   - 顶部"筛选"标题 + 关闭按钮,底部"清空"快捷按钮
///   - 不持有 state,只是 current* + on*Changed 透传,跟 _FilterBar 同模式
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.searchController,
    required this.onSearchChanged,
    required this.currentType,
    required this.currentMonth,
    required this.currentCategory,
    required this.currentAsset,
    required this.catsForType,
    required this.monthKeys,
    required this.formatMonthKey,
    required this.allAssets,
    required this.onTypeChanged,
    required this.onMonthChanged,
    required this.onCategoryChanged,
    required this.onAssetChanged,
  });

  // 2026-10-12 P5 follow-up 第 2 次改:搜索输入也搬到 sheet 顶部(用户偏好
  //   "漏斗=高级过滤入口,搜索也进去"),controller 来自 _LedgerPageState,
  //   关闭 sheet 再打开保留搜索内容;onChanged 直接写 ledgerSearchQueryProvider。
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String currentType;
  final int? currentMonth;
  final Set<int> currentCategory;
  final Set<int> currentAsset;
  final List<Category> catsForType;
  final List<int> monthKeys;
  final String Function(int) formatMonthKey;
  final List<Asset> allAssets;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<Set<int>> onCategoryChanged;
  final ValueChanged<Set<int>> onAssetChanged;

  bool get _hasAnyFilter =>
      searchController.text.isNotEmpty ||
      currentType != 'all' ||
      currentMonth != null ||
      currentCategory.isNotEmpty ||
      currentAsset.isNotEmpty;

  String _typeLabel() {
    switch (currentType) {
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

  String _monthLabel() =>
      currentMonth == null ? '全部' : formatMonthKey(currentMonth!);

  String _categoryLabel() {
    if (currentCategory.isEmpty) return '全部';
    if (currentCategory.length == 1) {
      final id = currentCategory.first;
      for (final c in catsForType) {
        if (c.id == id) return c.name;
      }
    }
    return '已选 ${currentCategory.length} 个';
  }

  String _assetLabel() {
    if (currentAsset.isEmpty) return '全部';
    if (currentAsset.length == 1) {
      final id = currentAsset.first;
      for (final a in allAssets) {
        if (a.id == id) return a.name;
      }
    }
    return '已选 ${currentAsset.length} 个';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 搜索框(2026-10-12 P5 follow-up 第 2 次改:从 AppBar 搬到 sheet 顶部,
            //   AppBar 只留 filter_alt 一个入口)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s2,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: InputDecoration(
                  hintText: '搜备注 / 分类',
                  hintStyle: const TextStyle(color: AppGray.g400, fontSize: 14),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppGray.g600,
                  ),
                  // 输入框清除按钮(右侧 ✕)— 仅在有文字时显示
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppGray.g600,
                          ),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
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
            // 标题行
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '筛选',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 4 个维度 pill(类型 / 月份 / 分类 / 资产)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                children: [
                  _FilterSheetField(
                    icon: Icons.category_outlined,
                    label: '类型',
                    value: _typeLabel(),
                    active: currentType != 'all',
                    onTap: () => _pickType(context),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  _FilterSheetField(
                    icon: Icons.calendar_today_outlined,
                    label: '月份',
                    value: _monthLabel(),
                    active: currentMonth != null,
                    onTap: () => _pickMonth(context),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  _FilterSheetField(
                    icon: Icons.local_offer_outlined,
                    label: '分类',
                    value: _categoryLabel(),
                    active: currentCategory.isNotEmpty,
                    onTap: () => _pickCategory(context),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  _FilterSheetField(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '资产',
                    value: _assetLabel(),
                    active: currentAsset.isNotEmpty,
                    onTap: () => _pickAsset(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 底部"清空"按钮(仅当有任意筛选激活时显示)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s2,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _hasAnyFilter
                      ? () {
                          // 2026-10-12 P5 follow-up 第 2 次改:清空也清搜索 query + controller
                          searchController.clear();
                          onSearchChanged('');
                          onTypeChanged('all');
                          onMonthChanged(null);
                          onCategoryChanged(<int>{});
                          onAssetChanged(<int>{});
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                  ),
                  child: const Text(
                    '清空筛选',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickType(BuildContext context) async {
    final options = <(Object?, String)>[
      (_allPicked, '全部'),
      ('expense', '支出'),
      ('income', '收入'),
      ('balance', '调拨'),
    ];
    final selected = await _showSingleSelectSheet<String>(
      context,
      title: '选择类型',
      options: options,
      currentValue: currentType,
    );
    if (selected == null || selected is _SheetDismissed) return;
    if (selected is _AllPicked) {
      onTypeChanged('all');
      return;
    }
    onTypeChanged(selected as String);
  }

  Future<void> _pickMonth(BuildContext context) async {
    final options = <(Object?, String)>[
      (_allPicked, '全部'),
      ...monthKeys.map((k) => (k, formatMonthKey(k))),
    ];
    final selected = await _showSingleSelectSheet<int?>(
      context,
      title: '选择月份',
      options: options,
      currentValue: currentMonth,
    );
    if (selected == null || selected is _SheetDismissed) return;
    if (selected is _AllPicked) {
      onMonthChanged(null);
      return;
    }
    onMonthChanged(selected as int?);
  }

  Future<void> _pickCategory(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _MultiSelectCategorySheet(
        categories: catsForType,
        initial: currentCategory,
      ),
    );
    if (selected != null) onCategoryChanged(selected);
  }

  Future<void> _pickAsset(BuildContext context) async {
    if (allAssets.isEmpty) {
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
      builder: (_) =>
          _MultiSelectAssetSheet(assets: allAssets, initial: currentAsset),
    );
    if (selected != null) onAssetChanged(selected);
  }
}

/// sheet 内的单行筛选维度 pill(icon + label + value + 激活态)
class _FilterSheetField extends StatelessWidget {
  const _FilterSheetField({
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
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s3,
        ),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.brMd,
          border: Border.all(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.4)
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
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

/// 2026-10-12 P5 follow-up 加:多选弹层(资产)—— 跟 _MultiSelectCategorySheet 同款结构
///   - 行 item:asset icon chip + name + 选中态:整行背景 tint + check icon
class _MultiSelectAssetSheet extends StatefulWidget {
  const _MultiSelectAssetSheet({required this.assets, required this.initial});
  final List<Asset> assets;
  final Set<int> initial;

  @override
  State<_MultiSelectAssetSheet> createState() => _MultiSelectAssetSheetState();
}

class _MultiSelectAssetSheetState extends State<_MultiSelectAssetSheet> {
  late Set<int> _selected;

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

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: AppGray.g400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '选择账户(可多选)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  TextButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(_selected.clear),
                    child: const Text('清空'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.assets.length,
                itemBuilder: (_, i) {
                  final a = widget.assets[i];
                  final checked = _selected.contains(a.id);
                  final color = Color(a.color);
                  return InkWell(
                    onTap: () => setState(() {
                      if (checked) {
                        _selected.remove(a.id);
                      } else {
                        _selected.add(a.id);
                      }
                    }),
                    child: Container(
                      color: checked
                          ? color.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: AppRadius.brXs,
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                                width: 0.5,
                              ),
                            ),
                            child: Icon(
                              _iconFor(a.icon),
                              color: color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Expanded(
                            child: Text(
                              a.name,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (checked)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                AppSpacing.s3,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, _selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
                  ),
                  child: Text(
                    _selected.isEmpty ? '显示全部' : '确定(${_selected.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
