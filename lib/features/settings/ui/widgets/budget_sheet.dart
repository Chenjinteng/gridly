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
import '../../../../shared/constants/default_categories.dart';

class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key});

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

  /// 是否加载完 budgetOverview(决定了能否显示分类列表)
  bool _overviewLoaded = false;
  bool _saving = false;

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

  /// 添加/更新某分类的子额度
  void _setCategoryBudget(Category category, double amount) {
    setState(() {
      if (amount <= 0) {
        _pendingBudgets[category.id] = 0; // 标记删除
      } else {
        _pendingBudgets[category.id] = amount;
      }
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
      // 收集需要删除的(categoryId → 0)
      final toDelete = _pendingBudgets.entries
          .where((e) => e.value <= 0)
          .map((e) => e.key)
          .toList();
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

      refreshAllData(ref);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await ref.read(monthlyBudgetProvider.notifier).set(0);
      _totalController.clear();
      refreshAllData(ref);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 弹 number input → 返回 amount;取消返回 null
  Future<double?> _askAmount(
    BuildContext context, {
    required double initial,
  }) async {
    final ctrl = TextEditingController(
      text: initial > 0 ? initial.toStringAsFixed(0) : '',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('设置子额度'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [const _AmountInputFormatter()],
            decoration: const InputDecoration(
              labelText: '子额度金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text.trim());
                if (v != null && v >= 0) Navigator.pop(ctx, v);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final key = BudgetMonthKey(now.year, now.month);
    final overviewAsync = ref.watch(budgetOverviewForMonthProvider(key));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s3,
          AppSpacing.s4,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.s4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部小拉手
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
                            : Theme.of(context).colorScheme.surfaceContainerLow,
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
                    // 分类列表
                    ConstrainedBox(
                      // 限制分类列表高度,太多分类时 sheet 内部滚动
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: overview.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final item = overview.items[i];
                          return _CategoryBudgetRow(
                            item: item,
                            effective: _effectiveAmount(item),
                            configured: _isConfigured(item),
                            poolRemaining: poolRemaining,
                            totalBudget: total,
                            onAdd: () async {
                              final v = await _askAmount(context, initial: 0);
                              if (v != null) {
                                _setCategoryBudget(item.category, v);
                              }
                            },
                            onEdit: () async {
                              final v = await _askAmount(
                                context,
                                initial: _effectiveAmount(item),
                              );
                              if (v != null) {
                                _setCategoryBudget(item.category, v);
                              }
                            },
                            onClear: () => _setCategoryBudget(item.category, 0),
                          );
                        },
                      ),
                    ),
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
    );
  }
}

/// 单分类预算行:icon + name + 子额度 / 进度条 / + 号
class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({
    required this.item,
    required this.effective,
    required this.configured,
    required this.poolRemaining,
    required this.totalBudget,
    required this.onAdd,
    required this.onEdit,
    required this.onClear,
  });

  final CategoryBudgetSummary item;
  final double effective;
  final bool configured;
  final double poolRemaining;
  final double totalBudget;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(item.category.color);
    final spent = item.spent;
    final progress = effective > 0 ? (spent / effective).clamp(0.0, 1.5) : 0.0;
    final over = effective > 0 && spent > effective;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
      child: Row(
        children: [
          // icon
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              CategoryIcons.map[item.category.icon] ?? Icons.category_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          // name + 进度
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.category.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (configured)
                      Text(
                        '¥${Formatters.amount(effective, withUnit: false)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: over ? AppStatus.error : scheme.onSurface,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                if (configured) ...[
                  // 已配置:显示进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: AppGray.g200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        over ? AppStatus.error : AppBrand.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    over
                        ? '已花 ¥${Formatters.amount(spent, withUnit: false)} / 超出'
                        : '已花 ¥${Formatters.amount(spent, withUnit: false)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: over ? AppStatus.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  // 未配置:显示共享池 + 已花
                  Text(
                    totalBudget > 0
                        ? '共享剩余池 ¥${Formatters.amount(poolRemaining, withUnit: false)} · 已花 ¥${Formatters.amount(spent, withUnit: false)}'
                        : '设置总额度后可分配子额度',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          // 操作按钮:+ / 编辑 / 撤销
          if (configured)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: '撤销子额度(回到共享池)',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: '编辑子额度',
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 22),
              tooltip: '设置子额度',
              onPressed: onAdd,
              color: AppBrand.teal,
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
