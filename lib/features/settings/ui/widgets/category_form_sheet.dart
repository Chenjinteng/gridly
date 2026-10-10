// lib/features/settings/ui/widgets/category_form_sheet.dart
// 新增 / 编辑分类的底部表单
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/constants/default_categories.dart';
import '../../../ledger/application/transactions_providers.dart';

class CategoryFormSheet extends ConsumerStatefulWidget {
  const CategoryFormSheet({super.key, this.existing});
  final Category? existing;

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  late final TextEditingController _nameController;
  late String _type;
  late String _icon;
  late int _color;
  bool _saving = false;

  /// v3:扩充到 30+ 个常用场景图标(支出 28 + 收入 6 + 通用 1)
/// 按消费场景分组排版(餐饮 / 交通 / 购物 / 居住 / 通讯 / 医疗 / 教育 /
/// 居家 / 娱乐 / 美妆 / 健身旅行 / 数码 / 收入 / 其他),Wrap 自动换行
static const _iconKeys = [
  // === 餐饮 ===
  'restaurant',
  'local_cafe',
  'local_dining',
  'cake',
  'local_bar',
  // === 交通 ===
  'directions_bus',
  'directions_car',
  'local_taxi',
  'flight',
  'directions_bike',
  // === 购物 ===
  'shopping_bag',
  'shopping_cart',
  'redeem',
  // === 居住 / 居家 ===
  'home',
  'bed',
  'kitchen',
  'cleaning_services',
  'chair',
  'lightbulb',
  // === 通讯 / 数码 ===
  'phone_iphone',
  'wifi',
  'devices',
  'laptop_mac',
  // === 医疗 ===
  'medical_services',
  'local_pharmacy',
  'monitor_heart',
  // === 教育 ===
  'school',
  'menu_book',
  'auto_stories',
  // === 娱乐 ===
  'movie',
  'music_note',
  'headphones',
  'videogame_asset',
  'sports_esports',
  // === 美妆 ===
  'spa',
  'face',
  'content_cut',
  // === 健身 / 旅行 ===
  'fitness_center',
  'hotel',
  'luggage',
  // === 宠物 / 其他 ===
  'pets',
  'more_horiz',
  // === 收入 ===
  'payments',
  'card_giftcard',
  'emoji_events',
  'savings',
  'trending_up',
  'account_balance_wallet',
  'work',
  'replay',
  // === 兜底 ===
  'category',
];

/// v3:16 色 = 12 色调色板 + 4 个高频语义色,避免用户挑不出合适颜色
static const _colorOptions = <int>[
  // 12 色调色板(与 AppCategory.hashPalette 对齐,自定义分类随机分配也用这套)
  0xFFFB923C, // 浅橙
  0xFFEC4899, // 粉
  0xFF06B6D4, // 青
  0xFFA855F7, // 紫
  0xFFD97706, // 棕橙
  0xFFF43F5E, // 玫红
  0xFF6366F1, // 靛
  0xFF14B8A6, // 青绿
  0xFFEAB308, // 柠檬黄
  0xFF84CC16, // 草绿
  0xFF0891B2, // 深青
  0xFF7C3AED, // 深紫
  // 4 个高频语义色(用户常选的"主流"颜色)
  0xFFEF4444, // 红
  0xFFF5BC1F, // 金
  0xFF3B82F6, // 蓝
  0xFFF59E0B, // 橙
];

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameController = TextEditingController(text: c?.name ?? '');
    _type = c?.type ?? 'expense';
    _icon = c?.icon ?? 'circle';
    _color = c?.color ?? _colorOptions.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('名字不能空');
      return;
    }
    if (name.length > 16) {
      _toast('名字太长(最多 16 字)');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(categoryRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(
          name: name,
          icon: _icon,
          color: _color,
          type: _type,
        );
      } else {
        await repo.update(widget.existing!.copyWith(
          name: name,
          icon: _icon,
          color: _color,
          type: _type,
        ));
      }
      ref.invalidate(allCategoriesProvider);
      ref.invalidate(allTransactionsByDayProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('保存失败:$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s4,
          AppSpacing.s3,
          AppSpacing.s4,
          MediaQuery.of(context).viewInsets.bottom + AppSpacing.s4,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              Text(
                widget.existing == null ? '新增分类' : '编辑分类',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 名字
              TextField(
                controller: _nameController,
                maxLength: 16,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),

              // 类型
              const Text(
                '类型',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.s2),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('支出')),
                  ButtonSegment(value: 'income', label: Text('收入')),
                ],
                selected: {_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 图标
              const Text(
                '图标',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.s2),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: _iconKeys.map((k) {
                  final selected = _icon == k;
                  return InkWell(
                    onTap: () => setState(() => _icon = k),
                    borderRadius: AppRadius.brMd,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected
                            ? Color(_color).withValues(alpha: 0.18)
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.brMd,
                        border: Border.all(
                          color: selected ? Color(_color) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        CategoryIcons.map[k],
                        color: selected ? Color(_color) : AppGray.g600,
                        size: 22,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 颜色
              const Text(
                '颜色',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.s2),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: _colorOptions.map((c) {
                  final color = Color(c);
                  final selected = _color == c;
                  return InkWell(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? AppBrand.ink : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s5),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppBrand.ink,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
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
                      : Text(widget.existing == null ? '新增' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
