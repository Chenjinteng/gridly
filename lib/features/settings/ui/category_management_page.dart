// lib/features/settings/ui/category_management_page.dart
// 分类管理:支出 / 收入 两组,可新增/编辑/删除
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: unused_import
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/constants/default_categories.dart';
import '../../ledger/application/transactions_providers.dart';
import 'widgets/category_form_sheet.dart';

class CategoryManagementPage extends ConsumerWidget {
  const CategoryManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增分类',
            onPressed: () => _showForm(context, null),
          ),
        ],
      ),
      body: categoriesAsync.when(
        data: (cats) {
          final expense = cats.where((c) => c.type == 'expense').toList();
          final income = cats.where((c) => c.type == 'income').toList();
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
            children: [
              _Group(
                title: '支出',
                items: expense,
                onEdit: (c) => _showForm(context, c),
                onDelete: (c) => _confirmDelete(context, ref, c),
              ),
              _Group(
                title: '收入',
                items: income,
                onEdit: (c) => _showForm(context, c),
                onDelete: (c) => _confirmDelete(context, ref, c),
              ),
              const SizedBox(height: AppSpacing.s5),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                child: Text(
                  '提示:删除分类时若已被流水引用,会被外键拒绝。请先改这些流水的分类。',
                  style: TextStyle(fontSize: 11, color: AppGray.g600),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败:$e')),
      ),
    );
  }

  void _showForm(BuildContext context, Category? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => CategoryFormSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category c,
  ) async {
    final usage = await ref.read(categoryRepositoryProvider).usageCount(c.id);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除分类?'),
        content: Text(
          '「${c.name}」当前被 $usage 条流水引用。\n'
          '${usage > 0 ? "删除会失败,请先把引用改到其他分类。" : "确认删除?"}',
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
      await ref.read(categoryRepositoryProvider).delete(c.id);
      ref.invalidate(allCategoriesProvider);
      ref.invalidate(allTransactionsByDayProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败:$e')),
        );
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
  final List<Category> items;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onDelete;

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
        ...items.map((c) => _CategoryTile(
              category: c,
              onEdit: () => onEdit(c),
              onDelete: () => onDelete(c),
            )),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.color);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: AppRadius.brMd,
          ),
          child: Icon(
            CategoryIcons.map[category.icon] ?? Icons.category_rounded,
            color: color,
            size: 20,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: category.isSystem
            ? const Text(
                '系统预置',
                style: TextStyle(fontSize: 11, color: AppGray.g600),
              )
            : const Text(
                '自定义',
                style: TextStyle(fontSize: 11, color: AppBrand.teal),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppStatus.error),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
