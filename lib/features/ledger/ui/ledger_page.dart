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
import '../../../core/utils/formatters.dart';
import '../../../core/utils/refresh_providers.dart';
import '../../../core/utils/asset_balance_provider.dart';
import '../application/transactions_providers.dart';
import 'advanced_filter_page.dart';
import 'filter_picker_sheets.dart';
import 'widgets/transaction_tile.dart';

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  // 2026-10-13:搜索 TextFieldController 移到 AdvancedFilterPage 自己持有
  //   ledger_page.dart 不再需要 _searchController(搜索逻辑统一在高级筛选页)

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
    super.dispose();
  }

  // 2026-10-13:类型/月份 filter 改成 Set,active 检测走 isNotEmpty
  bool _anyFilterActive(WidgetRef ref) {
    return ref.watch(ledgerTypeFilterProvider).isNotEmpty ||
        ref.watch(ledgerMonthFilterProvider).isNotEmpty ||
        ref.watch(ledgerCategoryFilterProvider).isNotEmpty ||
        ref.watch(ledgerAssetFilterProvider).isNotEmpty ||
        ref.watch(ledgerSearchQueryProvider).isNotEmpty;
  }

  /// 2026-10-13 改为 push 全屏 AdvancedFilterPage
  ///   user UAT 反馈'高级筛选里加上资产条件,要不高级筛选就直接全屏显示,
  ///   把 4 个条件都一行行列出来看看'。
  ///   - 移除 _openFilterSheet / _FilterSheet 旧的 modal sheet 实现
  ///   - 改用 Navigator.push 推全屏页 AdvancedFilterPage(替代)
  ///   - icon 在有任意筛选激活时 tint primary 色(不变)
  void _openAdvancedFilter() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AdvancedFilterPage()));
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
    // 2026-10-13:资产 list 不用再在 ledger_page 里 watch,AdvancedFilterPage 自己 watch
    // 搜索 query(用于 _EmptyState 显示"没找到匹配的"提示)
    final searchQuery = ref.watch(ledgerSearchQueryProvider);

    // 2026-10-13:类型 filter 改 Set<String>,catsForType 走"空 = 全部,非空 = OR"
    final catsForType = typeFilter.isEmpty
        ? allCats
        : allCats.where((c) => typeFilter.contains(c.type)).toList();

    return Scaffold(
      appBar: AppBar(
        // 2026-10-12 P5 follow-up 第 2 次改:搜索 + 过滤合并到 AppBar filter_alt 图标
        //   - 搜索输入框搬到 _FilterSheet 顶部(用户偏好"同操作只保留一个入口")
        //   - 标题固定 '流水',不再切 search field
        title: const Text('流水'),
        actions: [
          // 2026-10-13 改:AppBar 右上角 filter 按钮 → push 全屏 AdvancedFilterPage
          //   4 条件 row-by-row(类型 / 月份 / 分类 / 资产)+ 搜索
          //   icon 在有任意筛选激活时 tint primary 色(不变)
          IconButton(
            icon: Icon(
              Icons.filter_alt_rounded,
              color: _anyFilterActive(ref)
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: _openAdvancedFilter,
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
/// 任意筛选激活(含 高级筛选 设的 资产 / 搜索)时,右侧出现"清空"快捷按钮
///
/// 2026-10-12 P3 follow-up commit:从 4 dropdown(P3 加资产维度)退回 3 dropdown 一行布局。
///   user 反馈"4 个筛选太多长了,按之前的来只占一行就行"。
///   资产 / 搜索 维度搬到 AppBar ⚙️ filter_alt 推入的 AdvancedFilterPage 全屏页(2026-10-13)。
/// 2026-10-13:清空按钮扩到 5 个维度(原 3 个 + 资产 + 搜索),user 反馈
///   "外面这个清空按钮无法清空高级筛选里面的,这个要增加上"。
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

  // 2026-10-13:类型 / 月份 filter 改 Set(支持 高级筛选 多选),
  //   in-page _FilterBar 走单选 picker 时,选'全部' = 空 Set,选具体值 = {value}
  final Set<String> typeFilter;
  final Set<int> monthFilter;
  final Set<int> categoryFilter;
  final List<Category> catsForType;
  final List<int> monthKeys;
  final String Function(int) formatMonthKey;
  final ValueChanged<Set<String>> onTypeChanged;
  final ValueChanged<Set<int>> onMonthChanged;
  final ValueChanged<Set<int>> onCategoryChanged;

  // 2026-10-13:从 getter 改成方法,需要 ref.watch 高级筛选的 资产 / 搜索 provider
  bool _hasActiveFilter(WidgetRef ref) =>
      typeFilter.isNotEmpty ||
      monthFilter.isNotEmpty ||
      categoryFilter.isNotEmpty ||
      ref.watch(ledgerAssetFilterProvider).isNotEmpty ||
      ref.watch(ledgerSearchQueryProvider).isNotEmpty;

  void _clearAll(WidgetRef ref) {
    // 2026-10-13:一键清空所有 5 个筛选(含高级筛选里的 资产 + 搜索),
    //   不只清 in-page _FilterBar 看到的 3 个(类型 / 月份 / 分类)
    ref.read(ledgerTypeFilterProvider.notifier).state = <String>{};
    ref.read(ledgerMonthFilterProvider.notifier).state = <int>{};
    ref.read(ledgerCategoryFilterProvider.notifier).state = <int>{};
    ref.read(ledgerAssetFilterProvider.notifier).state = <int>{};
    ref.read(ledgerSearchQueryProvider.notifier).state = '';
  }

  String _typeLabel() {
    if (typeFilter.isEmpty) return '全部';
    if (typeFilter.length == 1) {
      switch (typeFilter.first) {
        case 'expense':
          return '支出';
        case 'income':
          return '收入';
        case 'balance':
          return '调拨';
      }
    }
    return '已选 ${typeFilter.length} 个';
  }

  String _monthLabel() {
    if (monthFilter.isEmpty) return '全部';
    if (monthFilter.length == 1) {
      return formatMonthKey(monthFilter.first);
    }
    return '已选 ${monthFilter.length} 个月';
  }

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
              active: typeFilter.isNotEmpty,
              onTap: () => _showTypePicker(context),
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: _DropdownField(
              label: '月份',
              value: _monthLabel(),
              active: monthFilter.isNotEmpty,
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
          if (_hasActiveFilter(ref)) ...[
            const SizedBox(width: AppSpacing.s2),
            _ClearButton(onTap: () => _clearAll(ref)),
          ],
        ],
      ),
    );
  }

  // ============ 弹层:类型(单选 — 给 in-page _FilterBar 用) ============
  //   2026-10-13:类型 provider 改 Set<String>,但 in-page _FilterBar 仍是单选
  //   UX(只有一个 dropdown 位)。选'全部' → 空 Set,选具体值 → {value}。
  Future<void> _showTypePicker(BuildContext context) async {
    // 2026-10-13 改:支持 3 个 type(含 balance),跟高级筛选对齐
    final options = <(Object?, String)>[
      (allPicked, '全部'),
      ('expense', '支出'),
      ('income', '收入'),
      ('balance', '调拨'),
    ];
    // 推断 currentValue:空 = null,单选 = 单值,多选 = null(不显示选中态)
    final currentValue = typeFilter.length == 1 ? typeFilter.first : null;
    final selected = await showSingleSelectSheet<String?>(
      context,
      title: '选择类型',
      options: options,
      currentValue: currentValue,
    );
    if (selected == null || selected is SheetDismissed) return;
    if (selected is AllPicked) {
      onTypeChanged(<String>{});
      return;
    }
    onTypeChanged(<String>{selected as String});
  }

  // ============ 弹层:月份(单选 — 给 in-page _FilterBar 用) ============
  //   2026-10-13:月份 provider 改 Set<int>,逻辑同上
  Future<void> _showMonthPicker(BuildContext context) async {
    final options = <(Object?, String)>[
      (allPicked, '全部'),
      ...monthKeys.map((k) => (k, formatMonthKey(k))),
    ];
    final currentValue = monthFilter.length == 1 ? monthFilter.first : null;
    final selected = await showSingleSelectSheet<int?>(
      context,
      title: '选择月份',
      options: options,
      currentValue: currentValue,
    );
    if (selected == null || selected is SheetDismissed) return;
    // 选'全部' → 触发 onMonthChanged(空 Set) 重置
    if (selected is AllPicked) {
      onMonthChanged(<int>{});
      return;
    }
    onMonthChanged(<int>{selected as int});
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
      builder: (ctx) => MultiSelectCategorySheet(
        categories: catsForType,
        initial: categoryFilter,
      ),
    );
    if (selected != null) onCategoryChanged(selected);
  }

  // 2026-10-12 P3 follow-up commit:删 _showAssetPicker(资产筛选 UI 不上,
  //   流水 tile 仍显示账户名作为视觉信息)。
}

/// 2026-10-12 P3 commit 加:多选弹层(资产)—— 跟 MultiSelectCategorySheet 同款结构
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

class _DaySection extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    // 2026-10-14 P18:日结小计排除"不计入流水" record
    //   - 投资 record(cat.type='investment')→ 永远不计入
    //   - source asset.includeInTransactions=false → 不计入
    //   - 跟 monthSummary / tile chip 同步规则
    final allCats = ref.watch(allCategoriesProvider).valueOrNull ?? const [];
    final investmentCatIds = allCats
        .where((c) => c.type == 'investment')
        .map((c) => c.id)
        .toSet();
    final allAssets = ref.watch(allAssetsProvider).valueOrNull ?? const [];
    final excludeAccountIds = allAssets
        .where((a) => !a.includeInTransactions)
        .map((a) => a.id)
        .toSet();
    bool isExcluded(Transaction t) {
      if (investmentCatIds.contains(t.categoryId)) return true;
      if (excludeAccountIds.contains(t.accountId)) return true;
      return false;
    }

    final dailyExpense = transactions
        .where((t) => t.type == 'expense' && !isExcluded(t))
        .fold<double>(0, (sum, t) => sum + t.amount);
    final dailyIncome = transactions
        .where((t) => t.type == 'income' && !isExcluded(t))
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
