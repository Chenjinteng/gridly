// lib/features/stats/ui/widgets/top_expenses.dart
// 报表页 Top 10 区域 —— 单笔 / 分类 两个 Tab 切换。
// 单笔:每行 = 分类图标 + 名字 + 日期 + 金额(降序前 10)
// 分类:复用 expenseByCategoryProvider,截取前 10,每行 = 图标 + 名字 + 金额 + 占比
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';
import '../../application/stats_providers.dart';

class TopExpenses extends ConsumerWidget {
  const TopExpenses({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s3,
                AppSpacing.s4,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Top 10 支出',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  TabBar(
                    isScrollable: true,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    tabs: const [
                      Tab(text: '单笔'),
                      Tab(text: '分类'),
                    ],
                    labelColor: AppBrand.teal,
                    unselectedLabelColor: AppGray.g600,
                    indicatorColor: AppBrand.teal,
                    dividerHeight: 0,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 400,
              child: const TabBarView(
                physics: NeverScrollableScrollPhysics(),
                children: [
                  _TopList(),
                  _TopByCategory(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopList extends ConsumerWidget {
  const _TopList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topAsync = ref.watch(topExpensesProvider);
    final cats = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return topAsync.when(
      data: (txs) {
        if (txs.isEmpty) {
          return const _Empty('该时段无支出');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          itemCount: txs.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            thickness: 0.5,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          itemBuilder: (context, i) {
            final t = txs[i];
            Category? cat;
            for (final c in cats) {
              if (c.id == t.categoryId) {
                cat = c;
                break;
              }
            }
            final color = cat == null ? AppGray.g400 : Color(cat.color);
            return InkWell(
              onTap: null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: AppRadius.brXs,
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.map[cat?.icon ?? 'category'] ??
                            Icons.category_rounded,
                        color: color,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            cat?.name ?? '未分类',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (t.note != null && t.note!.isNotEmpty)
                            Text(
                              t.note!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppGray.g600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '¥${Formatters.amount(t.amount)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppBrand.teal,
                          ),
                        ),
                        Text(
                          DateFormat('M月d日').format(t.occurredAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppGray.g600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error))),
    );
  }
}

class _TopByCategory extends ConsumerWidget {
  const _TopByCategory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseByCategoryProvider);
    final cats = ref.watch(allCategoriesProvider).valueOrNull ?? const <Category>[];
    return expensesAsync.when(
      data: (data) {
        if (data.isEmpty) {
          return const _Empty('该时段无支出');
        }
        final total = data.fold<double>(0, (s, e) => s + e.amount);
        final top = data.take(10).toList();
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
          itemCount: top.length,
          separatorBuilder: (_, _) => const Divider(
            height: 1,
            thickness: 0.5,
            indent: AppSpacing.s4,
            endIndent: AppSpacing.s4,
          ),
          itemBuilder: (context, i) {
            final e = top[i];
            // CategoryExpense 不带 icon,查 allCategories 拿
            String iconKey = 'category';
            for (final c in cats) {
              if (c.id == e.categoryId) {
                iconKey = c.icon;
                break;
              }
            }
            final color = Color(e.color);
            final pct = (e.amount / total * 100).toStringAsFixed(0);
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: AppRadius.brXs,
                      border: Border.all(
                        color: color.withValues(alpha: 0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      CategoryIcons.map[iconKey] ?? Icons.category_rounded,
                      color: color,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      e.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppGray.g600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    '¥${Formatters.amount(e.amount)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败:$e', style: const TextStyle(color: AppStatus.error))),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: AppGray.g600, fontSize: 13),
      ),
    );
  }
}