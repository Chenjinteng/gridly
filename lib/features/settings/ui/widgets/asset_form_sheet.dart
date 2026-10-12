// lib/features/settings/ui/widgets/asset_form_sheet.dart
// 资产/账户 增改表单 sheet —— 跟 CategoryFormSheet 同结构
//
// 2026-10-12 P2 commit 加:
//   - 字段:name (1-24 字) + type (4 段 SegmentedButton) + icon (8 选 1 Wrap) +
//     color (16 色调色板 Wrap) + initialBalance (数字输入,可选,默认 0)
//   - 复用 CategoryFormSheet 的 16 色调色板(保持 gridly 视觉系统统一)
//   - 保存:AssetRepository.create() / update(),invalidate assets + balances providers
//   - 关闭:Navigator.pop()
//   - validation:name 不能空 / > 24 字;initialBalance 范围合理(默认 0,负数代表初始欠款)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/gridly_banner.dart';
import '../../../../core/utils/refresh_providers.dart';
import 'asset_tile.dart';

class AssetFormSheet extends ConsumerStatefulWidget {
  const AssetFormSheet({super.key, this.existing});
  final Asset? existing;

  @override
  ConsumerState<AssetFormSheet> createState() => _AssetFormSheetState();
}

class _AssetFormSheetState extends ConsumerState<AssetFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late String _type;
  late String _icon;
  late int _color;
  // 2026-10-13 P6 加:资产是否计入日常流水开关(true = 显示在流水页,默认开)
  // 投资 / 福利 / 债权等"非日常"资产,user 关掉它,后面做调拨/理财报表时启用 filter
  late bool _includeInTransactions;
  bool _saving = false;

  /// 8 个资产相关 icon(2026-10-12 P2 收敛到 8 个常用,跟 asset_tile.icons 共享映射)
  /// 顺序按使用频度:钱包 / 银行卡 / 现金 / 储蓄 / 银行 / 房 / 车 / 调拨
  static const _iconKeys = [
    'account_balance_wallet',
    'credit_card',
    'payments',
    'savings',
    'account_balance',
    'home',
    'directions_car',
    'swap_horiz',
  ];

  /// 2026-10-13 P6:资产类型从 4 段改 6 段(去'liability',加'investment' / 'benefit' / 'receivable')
  /// 顺序按日常使用频度:现金 → 投资 → 福利 → 借出 → 不动产 → 其它
  static const _typeSegments = <ButtonSegment<String>>[
    ButtonSegment(
      value: 'cash_flow',
      label: Text('现金流'),
      icon: Icon(Icons.account_balance_wallet_rounded, size: 16),
    ),
    ButtonSegment(
      value: 'investment',
      label: Text('投资'),
      icon: Icon(Icons.trending_up_rounded, size: 16),
    ),
    ButtonSegment(
      value: 'benefit',
      label: Text('福利'),
      icon: Icon(Icons.favorite_rounded, size: 16),
    ),
    ButtonSegment(
      value: 'receivable',
      label: Text('债权'),
      icon: Icon(Icons.handshake_rounded, size: 16),
    ),
    ButtonSegment(
      value: 'fixed_asset',
      label: Text('不动产'),
      icon: Icon(Icons.home_rounded, size: 16),
    ),
    ButtonSegment(
      value: 'other',
      label: Text('其它'),
      icon: Icon(Icons.category_rounded, size: 16),
    ),
  ];

  /// 16 色调色板 — 跟 CategoryFormSheet 同款,保持视觉统一
  static const _colorOptions = <int>[
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
    0xFFEF4444, // 红
    0xFFF5BC1F, // 金
    0xFF3B82F6, // 蓝
    0xFFF59E0B, // 橙
  ];

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _nameController = TextEditingController(text: a?.name ?? '');
    _balanceController = TextEditingController(
      text: a == null || a.initialBalance == 0
          ? ''
          : a.initialBalance.toString(),
    );
    _type = a?.type ?? 'cash_flow';
    _icon = a?.icon ?? 'account_balance_wallet';
    _color = a?.color ?? 0xFF14B8A6; // AppBrand.teal 默认
    // 2026-10-13 P6:老数据可能没有这个字段(默认值兜底 true)
    _includeInTransactions = a?.includeInTransactions ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('名字不能空');
      return;
    }
    if (name.length > 24) {
      _toast('名字太长(最多 24 字)');
      return;
    }
    final balanceText = _balanceController.text.trim();
    final balance = balanceText.isEmpty ? 0.0 : double.tryParse(balanceText);
    if (balance == null) {
      _toast('期初余额格式不对');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(assetRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(
          name: name,
          type: _type,
          icon: _icon,
          color: _color,
          initialBalance: balance,
          includeInTransactions: _includeInTransactions,
        );
      } else {
        await repo.update(
          widget.existing!.copyWith(
            name: name,
            type: _type,
            icon: _icon,
            color: _color,
            initialBalance: balance,
            includeInTransactions: _includeInTransactions,
          ),
        );
      }
      // 广谱 invalidate(包含 asset 列表 + balances map)
      refreshAllData(ref);
      ref.invalidate(allAssetsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast('保存失败:$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    showGridlyBanner(context, msg, kind: GridlyBannerKind.warning);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                widget.existing == null ? '新增账户' : '编辑账户',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 名字
              TextField(
                controller: _nameController,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '如:招行 / 微信 / 公积金',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s3),

              // 类型(6 段 SegmentedButton,2026-10-13 P6 改)
              //   现金流 / 投资 / 福利 / 债权 / 不动产 / 其它
              //   6 段可能在小屏(360px)挤,showSelectedIcon:false 省 ~24px 给 label
              const Text(
                '类型',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.s2),
              SegmentedButton<String>(
                segments: _typeSegments,
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 2026-10-13 P6 加:是否计入流水开关
              //   - 默认 true(常规账户)
              //   - 投资 / 福利 / 债权账户可以关掉
              //   - 当前只存,流水页 filter 暂不动(等调拨 source/target 设计落地再启用)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  color: _includeInTransactions
                      ? Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.06)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: AppRadius.brMd,
                ),
                child: Row(
                  children: [
                    Icon(
                      _includeInTransactions
                          ? Icons.receipt_long_rounded
                          : Icons.archive_rounded,
                      size: 20,
                      color: _includeInTransactions
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '计入日常流水',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _includeInTransactions
                                ? '会出现在流水页和日常收支统计'
                                : '不计入流水(适合投资/福利/债权等账户)',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _includeInTransactions,
                      onChanged: (v) =>
                          setState(() => _includeInTransactions = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 期初余额(可负,代表初始欠款)
              TextField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: '期初余额',
                  hintText: '默认 0;负债可填负数',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 图标(8 选 1)
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
                        AssetTile.icons[k] ??
                            Icons.account_balance_wallet_rounded,
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
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
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
                    backgroundColor: isDark ? AppSecondary.cream : AppBrand.ink,
                    foregroundColor: isDark ? AppBrand.ink : null,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.brLg),
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
