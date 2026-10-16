// lib/features/settings/ui/widgets/budget_sheet.dart
// 月度预算设置底部表单
//   - 上半:总额度(SharedPreferences)
//   - 下半:分类预算列表(数据库 CategoryBudgets 表)
//     - 已配置子额度的分类:显示子额度 + 进度条 + 撤销按钮
//     - 未配置子额度的分类:显示 + 号 → 弹 input → 输子额度 → 保存
//     - 顶部共享池提示:总额度 - 已配置总和 = 共享池,未配置分类共享
//
// 2026-10-12 commit 92 加分类预算 UI(对应 commit 90 + 91 的数据 / provider 层)
//   - 整体提交:点底部'保存预算'统一提交所有变更
//   - 校验:已配置子额度总和 ≤ 总额度,超出时提示并阻止提交
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/budget_provider.dart';
import '../../../../core/utils/refresh_providers.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/show_app_modal_sheet.dart';
import '../../../../shared/constants/default_categories.dart';

class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key, this.embedded = false});

  /// commit 106 加:是否为嵌入到全屏 page 内(去掉 sheet 容器)。
  ///   - false(默认):原 sheet 行为 — 顶部小拉手、底部 viewInsets padding
  ///   - true:嵌入到 BudgetManagementPage 内 — 不要小拉手,viewInsets 由 Scaffold 处理
  final bool embedded;

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  late final TextEditingController _totalController;

  /// 待保存的子额度变更(categoryId → amount)
  ///   - 0 = 删除该分类的子额度(回到共享池)
  ///   - > 0 = 设置 / 更新该分类的子额度
  ///   - null = 该分类未变更(用原值)
  final Map<int, double> _pendingBudgets = {};

  /// commit 101 加:显式 X 删除的分类。
  ///   bug:之前 `_pendingBudgets.remove(catId)` 让 row 立刻消失,但保存时
  ///   `_save()` 遍历 `_pendingBudgets` 找 `value <= 0` 的进 `toDelete` 列表,
  ///   而该 catId 已不在 map,所以 DB 中的记录永远不会删 → 下次重新点开
  ///   overviewLoaded 加载 → row 又出现。
  ///   修法:X 删除时同时 add 到 `_pendingDeletions`,`_save` 优先遍历此集合。
  final Set<int> _pendingDeletions = {};

  /// 是否加载完 budgetOverview(决定了能否显示分类列表)
  bool _overviewLoaded = false;
  bool _saving = false;

  /// commit 99 加:刚 picker 选中的分类 → 列表 row mount 后自动聚焦 + 弹键盘,
  ///   让用户直接输入子额度(避免弹 amount dialog)。
  int? _focusedCatId;

  @override
  void initState() {
    super.initState();
    final current = ref.read(monthlyBudgetProvider);
    _totalController = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _totalController.dispose();
    super.dispose();
  }

  /// 当前生效的子额度(优先 _pendingBudgets,fallback 原值)
  double _effectiveAmount(CategoryBudgetSummary item) {
    final pending = _pendingBudgets[item.category.id];
    if (pending != null) return pending;
    return item.amount;
  }

  /// 是否有"配置中"的变更(用于编辑状态 UI)
  bool _isConfigured(CategoryBudgetSummary item) => _effectiveAmount(item) > 0;

  /// 已配置子额度总和(按 effective 计算)
  double _totalAllocated(List<CategoryBudgetSummary> items) {
    return items
        .where((i) => _isConfigured(i))
        .fold<double>(0.0, (sum, i) => sum + _effectiveAmount(i));
  }

  /// 从已添加列表移除某分类(同时记录到 pendingDeletions 让保存时真删 DB)
  /// commit 101 改:之前只 `_pendingBudgets.remove`,row 立刻消失但 DB 不删,
  ///   下次进来 overviewLoaded 加载回 _pendingBudgets → row 又出现
  void _removeCategory(Category category) {
    setState(() {
      _pendingBudgets.remove(category.id);
      _pendingDeletions.add(category.id);
    });
  }

  /// 计算还能添加几个分类(总支出分类 - 已添加)
  int _availableToAddCount(BudgetOverview overview) {
    return overview.items
        .where((i) => !_pendingBudgets.containsKey(i.category.id))
        .length;
  }

  /// 弹分类 picker(只显示未添加的)→ 选一个 → 直接加入列表(row 内自带输入框)
  /// commit 99 改:之前 picker → 弹 amount dialog → 输入,弹窗动画 + 自绘 Dialog
  ///   layout 在低端机会掉帧。改回 picker → 直接在 row 内 TextField 输入,
  ///   节省一次弹窗动画,row widget 也从 bar / 已花数字 / 进度条精简到
  ///   "icon + 名字 + 输入框 + 删除",整体 rebuild 开销小,不再掉帧。
  Future<void> _openCategoryPicker(
    BuildContext context,
    BudgetOverview overview,
  ) async {
    final available = overview.items
        .where((i) => !_pendingBudgets.containsKey(i.category.id))
        .map((i) => i.category)
        .toList();
    if (available.isEmpty) return;

    final picked = await showAppModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => _BudgetCategoryPickerSheet(categories: available),
    );
    if (picked == null) return;
    if (!context.mounted) return;

    // 选完分类 → 直接加入 pending(初始 0),并标记需要自动聚焦 + 弹键盘
    setState(() {
      _pendingBudgets[picked.id] = 0;
      _focusedCatId = picked.id;
    });
  }

  /// 提交所有变更
  Future<void> _save() async {
    final total = double.tryParse(_totalController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      // 1) 保存总额度
      await ref.read(monthlyBudgetProvider.notifier).set(total);

      // 2) 保存所有 pending 的分类子额度
      final repo = ref.read(categoryBudgetRepositoryProvider);
      final now = DateTime.now();
      // 收集需要删除的:
      //   - _pendingDeletions(显式 X 删除,commit 101 加 ——
      //     row 立刻消失但保存时要真删 DB,否则下次进来又会回来)
      //   - _pendingBudgets 中 value <= 0(用户清空输入框)
      final toDelete = <int>{
        ..._pendingDeletions,
        ..._pendingBudgets.entries.where((e) => e.value <= 0).map((e) => e.key),
      };
      // 收集需要 upsert 的(categoryId → amount)
      final toUpsert = _pendingBudgets.entries
          .where((e) => e.value > 0)
          .toList();

      for (final id in toDelete) {
        await repo.delete(categoryId: id, year: now.year, month: now.month);
      }
      for (final entry in toUpsert) {
        await repo.upsert(
          categoryId: entry.key,
          year: now.year,
          month: now.month,
          amount: entry.value,
        );
      }

      // commit 101:清空 _pendingDeletions,避免下次保存重复删
      _pendingDeletions.clear();

      refreshAllData(ref);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      // commit 101 改:之前只清总额度,DB 中本月所有 categoryBudgets
      //   还在 → 下次点开 BudgetSheet,overviewLoaded 从 DB 加载 → row 又出现
      //   修法:同时把 DB 中本月所有分类子额度删了
      await ref.read(monthlyBudgetProvider.notifier).set(0);
      final repo = ref.read(categoryBudgetRepositoryProvider);
      final now = DateTime.now();
      final existing = await repo.byMonth(now.year, now.month);
      for (final catId in existing.keys) {
        await repo.delete(categoryId: catId, year: now.year, month: now.month);
      }
      // 清 pending state(下次进入 BudgetSheet 时不会基于旧 state 复活)
      _pendingBudgets.clear();
      _pendingDeletions.clear();
      _totalController.clear();
      refreshAllData(ref);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final key = BudgetMonthKey(now.year, now.month);
    final overviewAsync = ref.watch(budgetOverviewForMonthProvider(key));

    return SafeArea(
      child: Padding(
        // commit 106 改:embedded 模式(全屏 page 内)不要 viewInsets.bottom,
        //   让 Scaffold 的 resizeToAvoidBottomInset 处理;sheet 模式保留原逻辑
        padding: widget.embedded
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s3,
              )
            : EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                MediaQuery.of(context).viewInsets.bottom + AppSpacing.s4,
              ),
        // SingleChildScrollView 包裹:键盘弹起 viewInsets.bottom 增加时,
        //   sheet 可用高度被压缩 → 原来 Column(mainAxisSize.min)固定不可滚动,
        //   会触发 BOTTOM OVERFLOWED BY N PIXELS 错误。这里允许内容超出时滚动,
        //   同时保留顶部小拉手(始终可见)和底部按钮跟随滚动。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // commit 106 改:embedded 模式(全屏 page)无顶部小拉手
              if (!widget.embedded)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.s3),
                    decoration: BoxDecoration(
                      color: AppGray.g400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              // commit 106 改:embedded 模式不显示"月度预算"标题(由 AppBar 提供)
              if (!widget.embedded) ...[
                const Text(
                  '月度预算',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.s1),
                const Text(
                  '设置总额度后可给具体分类配置子额度;未配置分类共享剩余池。',
                  style: TextStyle(fontSize: 12, color: AppGray.g600),
                ),
                const SizedBox(height: AppSpacing.s4),
              ],
              // 总额度输入
              TextField(
                controller: _totalController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [const _AmountInputFormatter()],
                decoration: const InputDecoration(
                  labelText: '预算总额度',
                  prefixText: '¥ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              // 分类预算列表
              overviewAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                  child: Text(
                    '加载分类失败:$e',
                    style: const TextStyle(color: AppStatus.error),
                  ),
                ),
                data: (overview) {
                  if (!_overviewLoaded) {
                    _overviewLoaded = true;
                    // 初始化 _pendingBudgets(从 overview.items 加载现有子额度)
                    // 不放 initState 因为 initState 时 ref.read overview 还没就绪
                    for (final item in overview.items) {
                      if (item.isConfigured) {
                        _pendingBudgets[item.category.id] = item.amount;
                      }
                    }
                  }
                  final total =
                      double.tryParse(_totalController.text.trim()) ??
                      overview.totalBudget;
                  final allocated = _totalAllocated(overview.items);
                  final overAllocated = total > 0 && allocated > total;
                  final poolRemaining = (total - allocated).clamp(
                    0.0,
                    double.infinity,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 共享池提示
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3,
                          vertical: AppSpacing.s2,
                        ),
                        decoration: BoxDecoration(
                          color: overAllocated
                              ? AppStatus.error.withValues(alpha: 0.1)
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: overAllocated
                                ? AppStatus.error
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              overAllocated
                                  ? Icons.warning_amber_rounded
                                  : Icons.account_balance_wallet_outlined,
                              size: 16,
                              color: overAllocated
                                  ? AppStatus.error
                                  : AppBrand.teal,
                            ),
                            const SizedBox(width: AppSpacing.s2),
                            Expanded(
                              child: Text(
                                total <= 0
                                    ? '请先设置总额度'
                                    : overAllocated
                                    ? '已分配 ¥${Formatters.amount(allocated)} 超出总额度 ¥${Formatters.amount(total)}'
                                    : '已分配 ¥${Formatters.amount(allocated)} · 剩余 ¥${Formatters.amount(poolRemaining)} 共享给未配置分类',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: overAllocated
                                      ? AppStatus.error
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s3),
                      // 分类列表 —— 只显示已添加的(按需)
                      // commit 94 改:之前列表遍历 overview.items(全部分类),
                      //   user 反馈"分类太多,只需要按需增加我要分配的分类"
                      //   改为遍历 _pendingBudgets.entries(只显示已添加的),
                      //   底部"+ 添加分类"按钮按需弹出分类 picker
                      if (_pendingBudgets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.s3,
                          ),
                          child: Center(
                            child: Text(
                              '未配置子额度 · 点下方"+ 添加分类"按需配置',
                              style: TextStyle(
                                color: AppGray.g600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._pendingBudgets.entries.map((entry) {
                          final catId = entry.key;
                          // 从 overview 查 Category info
                          final item = overview.items
                              .where((i) => i.category.id == catId)
                              .firstOrNull;
                          if (item == null) return const SizedBox.shrink();
                          return _CategoryBudgetRow(
                            key: ValueKey(catId),
                            category: item.category,
                            initialAmount: entry.value,
                            // commit 99:刚 picker 选中的 row 自动聚焦 + 弹键盘,
                            //   用户不用再点一下输入框
                            autofocus: catId == _focusedCatId,
                            onAmountChanged: (v) {
                              setState(() {
                                _pendingBudgets[catId] = v;
                              });
                              // 只聚焦一次,聚焦后清掉标记
                              if (catId == _focusedCatId) {
                                _focusedCatId = null;
                              }
                            },
                            onRemove: () => _removeCategory(item.category),
                          );
                        }),
                      // + 添加分类 按钮(只在还有未添加分类时显示)
                      if (_availableToAddCount(overview) > 0) ...[
                        const SizedBox(height: AppSpacing.s2),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _openCategoryPicker(context, overview),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                              '添加分类(剩 ${_availableToAddCount(overview)} 个可选)',
                            ),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.brLg,
                              ),
                              foregroundColor: AppBrand.teal,
                              side: const BorderSide(
                                color: AppBrand.teal,
                                width: 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s2,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s4),
                      // 保存 / 清除
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (_saving || overAllocated) ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: isDark
                                ? AppSecondary.cream
                                : AppBrand.ink,
                            foregroundColor: isDark ? AppBrand.ink : null,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s3,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.brLg,
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppBrand.gold,
                                  ),
                                )
                              : Text(overAllocated ? '已分配超出总额度' : '保存预算'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s2),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _saving ? null : _clear,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: AppRadius.brLg,
                            ),
                            foregroundColor: AppStatus.error,
                            side: const BorderSide(
                              color: AppStatus.error,
                              width: 1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s3,
                            ),
                          ),
                          child: const Text('清除预算'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单分类预算行:icon + 分类名 + 子额度输入框 + 删除按钮
///
/// commit 99 重构(精简掉一半内容):
///   - 之前:LinearProgressIndicator(bar) + 已花数字 + 进度条 + +/编辑/撤销 3 个按钮
///   - 现在:只剩 icon + 名字 + TextField(子额度) + 删除按钮
///   - 之前是 StatelessWidget,弹 dialog 时 BudgetSheet 整体 rebuild → row 重新
///     layout bar / 进度 / 数字 → 低端机掉帧
///   - 现在是 StatefulWidget 自己管 TextEditingController + FocusNode,
///     onChanged 只调 parent 的 onAmountChanged(轻量 setState),widget tree 轻,
///     不再掉帧
///
/// user 原话(2026-10-12):
///   "其实不需要显示横向的条,也不需要显示已经花了多少,只需要有一个输入框,
///    一个删除按钮就行,连编辑按钮都不需要,在输入框输入完就直接点击保存预算就行"
class _CategoryBudgetRow extends StatefulWidget {
  const _CategoryBudgetRow({
    super.key,
    required this.category,
    required this.initialAmount,
    required this.autofocus,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final Category category;
  final double initialAmount;

  /// commit 99 加:刚 picker 选中的 row 自动聚焦 + 弹键盘,user 直接输入子额度
  final bool autofocus;
  final ValueChanged<double> onAmountChanged;
  final VoidCallback onRemove;

  @override
  State<_CategoryBudgetRow> createState() => _CategoryBudgetRowState();
}

class _CategoryBudgetRowState extends State<_CategoryBudgetRow> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.initialAmount > 0
          ? widget.initialAmount.toStringAsFixed(0)
          : '',
    );
    _focusNode = FocusNode();
    // postFrameCallback 保证 row 已 mounted + layout 完成后才 requestFocus,
    //   直接在 initState 调 focus 在某些场景会触发 assertion
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.category.color);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      child: Row(
        children: [
          // icon(分类色块 + 缩略 icon,跟 stats widget 风格一致)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              CategoryIcons.map[widget.category.icon] ?? Icons.category_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          // 分类名
          Expanded(
            child: Text(
              widget.category.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          // 子额度输入框 — 输完直接点底部"保存预算"统一提交
          SizedBox(
            width: 130,
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [const _AmountInputFormatter()],
              decoration: InputDecoration(
                prefixText: '¥ ',
                prefixStyle: TextStyle(color: AppGray.g600, fontSize: 13),
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                hintText: '0',
                hintStyle: TextStyle(color: AppGray.g400),
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              onChanged: (text) {
                final v = double.tryParse(text.trim()) ?? 0;
                widget.onAmountChanged(v);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: '移除该分类',
            onPressed: widget.onRemove,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

/// 预算/记账公用金额输入 formatter:7 位整数 + 小数点 + 2 位小数 = 9999999.99
///
/// 不允许负号(预算/支出场景都是正数)
class _AmountInputFormatter extends TextInputFormatter {
  const _AmountInputFormatter();

  static const _maxIntegerDigits = 7;
  static const _maxFractionDigits = 2;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text)) {
      return oldValue;
    }
    final dotIdx = text.indexOf('.');
    if (dotIdx == -1) {
      if (text.length > _maxIntegerDigits) return oldValue;
    } else {
      if (dotIdx > _maxIntegerDigits) return oldValue;
      final fracLen = text.length - dotIdx - 1;
      if (fracLen > _maxFractionDigits) return oldValue;
    }
    return newValue;
  }
}

/// 分类 picker(只显示未添加的支出分类)
///   commit 94 加:从 BudgetSheet 弹,选完回到 BudgetSheet 弹 amount 输入
class _BudgetCategoryPickerSheet extends StatelessWidget {
  const _BudgetCategoryPickerSheet({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 拉手
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.s3),
                decoration: BoxDecoration(
                  color: AppGray.g400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Text(
                '选择要分配额度的分类',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: categories.length,
                itemBuilder: (ctx, i) {
                  final c = categories[i];
                  return InkWell(
                    onTap: () => Navigator.pop(context, c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s4,
                        vertical: AppSpacing.s3,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(c.color).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              CategoryIcons.map[c.icon] ??
                                  Icons.category_rounded,
                              size: 18,
                              color: Color(c.color),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Text(c.name, style: const TextStyle(fontSize: 14)),
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
  }
}
