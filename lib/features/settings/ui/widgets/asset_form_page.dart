// lib/features/settings/ui/widgets/asset_form_page.dart
// 资产/账户 增改表单页 —— 整页版本(2026-10-13 P6 改)
// 跟 CategoryFormSheet 历史结构对齐,本轮重写为全屏 page。
//
// 2026-10-12 P2 commit 加:
//   - 字段:name (1-24 字) + type (4 段 SegmentedButton) + icon (8 选 1 Wrap) +
//     color (16 色调色板 Wrap) + initialBalance (数字输入,可选,默认 0)
//   - 复用 CategoryFormSheet 的 16 色调色板(保持 gridly 视觉系统统一)
//   - 保存:AssetRepository.create() / update(),invalidate assets + balances providers
//   - 关闭:Navigator.pop()
//   - validation:name 不能空 / > 24 字;initialBalance 范围合理(默认 0,负数代表初始欠款)
//
// 2026-10-13 P6 整页重构:
//   - 从 showModalBottomSheet modal sheet 改为 MaterialPageRoute 全屏 page
//   - 原因:页面太长(6 段类型 + 8 icon + 16 调色板 + 期初余额 + 计入开关),sheet 太挤
//   - 弹 sheet 没有明显关闭/返回按钮,user 容易卡死
//   - 改整页后 AppBar 自动有返回箭头 + 右上角"保存"check 图标,操作闭环更清晰
//   - "计入日常流水"行用 AquaSwitch(拟物风)替换 Switch.adaptive,跟 gridly
//     整体 ColorOS Aquamorphic 调性统一,跟"显示金额"开关同款
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/gridly_banner.dart';
import '../../../../core/utils/refresh_providers.dart';
import '../../../../core/widgets/aqua_row_card.dart';
import 'asset_tile.dart';

class AssetFormPage extends ConsumerStatefulWidget {
  const AssetFormPage({super.key, this.existing});
  final Asset? existing;

  @override
  ConsumerState<AssetFormPage> createState() => _AssetFormPageState();
}

class _AssetFormPageState extends ConsumerState<AssetFormPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late String _type;
  late String _icon;
  late int _color;
  // 2026-10-13 P6 加:资产是否计入日常流水开关(true = 显示在流水页,默认开)
  // 投资 / 福利 / 债权等"非日常"资产,user 关掉它,后面做调拨/理财报表时启用 filter
  late bool _includeInTransactions;
  // 2026-10-15 D61 加:receivable 段"充当现金流"开关
  //   - 只对 receivable 段有义:花呗/白条/信用卡等可消费债务 → 开,记一笔 cash_flow 支出能选
  //   - 车贷/房贷/借款等不可消费债务 → 关,只走 receivable 段调拨还款
  //   - 非 receivable 段恒为 false(切 type 时清零)
  late bool _actAsCashFlow;
  // 2026-10-16 D64.58 加:receivable 段"借出"开关(默认 false = 借入)
  //   - true:借出账户(我是债权人,余额为正,例如借给老王)
  //   - false:借入账户(我是负债方,余额为负,例如花呗/车贷/房贷/借款)
  //   - 非 receivable 段恒为 false(form 切 type 时清零)
  //   - 本次 D64.58 只做 label 落地(form toggle UI + DB 列);后续 D64.59+
  //     展开"基于 isLender 的进一步分析"(transaction_form 默认值联动 /
  //     AssetTile 显示借出 chip / AssetSummaryCard receivable 拆分 /
  //     LiabilitiesDashboard 加应收卡)
  late bool _isLender;
  // 2026-10-13 P7 加:cash_flow 段"日常流水默认账户"标记
  //   - 只有 cash_flow 段才有意义(其他段 IsDefaultCard 不显示)
  //   - save 后会调 setDefaultForCashFlow(id) 保证单例
  late bool _isDefault;
  bool _saving = false;

  /// 2026-10-14 D48 续:icon 池扁平列表,不分组
  ///   - 之前 D48 第一版做了 8 组分组 + 子 label,user 反馈"图标不需要分类,不用指导用户"
  ///   - 改成扁平 Wrap,user 自己挑,系统不引导
  ///   - 顺序按日常使用频度:通用支付 → 支付品牌 → 资产 → 投资 → 加密 → 票务 → 保险 → 福利
  ///   - key 命名:material 走裸名(走 AssetTile.icons),brand:/crypto: 走前缀
  ///     (走 AssetTile.brandIcons)
  ///   - 渲染统一 AssetTile.renderIcon(),自动判别 Icon / Container
  static const _iconKeys = [
    // 通用钱包 / 支付 / 现金(9)
    'account_balance_wallet',
    'wallet',
    'payments',
    'credit_card',
    'savings',
    'account_balance',
    'currency_yen',
    'attach_money',
    'monetization_on',
    // 支付品牌(6:alipay / wechat / apple_pay / google_pay / epay / unionpay)
    'brand:alipay',
    'brand:wechat',
    'apple_pay',
    'brand:google_pay',
    'brand:epay',
    'brand:unionpay',
    // 资产类型(4)
    'home',
    'directions_car',
    'landscape',
    'apartment',
    // 投资 / 股票 / 债券(5)
    'trending_up',
    'candlestick_chart',
    'show_chart',
    'receipt_long',
    'assessment',
    // 加密货币(3:btc / eth / usdt)
    'crypto:btc',
    'crypto:eth',
    'crypto:usdt',
    // 票务 / 充值 / 餐饮 / 兑换(8)
    'card_giftcard',
    'confirmation_number',
    'theater_comedy',
    'restaurant',
    'redeem',
    'flight',
    'train',
    'local_activity',
    // 保险 / 保障(4)
    'health_and_safety',
    'shield',
    'security',
    'verified',
    // 福利 / 借出 / 其它(4)
    'favorite',
    'handshake',
    'swap_horiz',
    'category',
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
    // 2026-10-13 P7:includeInTransactions 按 type 推导默认值
    //   - 新增模式 + cash_flow → true(银行/钱包默认会记账)
    //   - 新增模式 + 其他 type → false(投资/福利/债权默认不进,2026-10-13 user 要求)
    //   - 编辑模式 → 用已有值
    final isCashFlow = (_type == 'cash_flow');
    _includeInTransactions = a?.includeInTransactions ?? isCashFlow;
    // 2026-10-13 P7:isDefault 默认 false,seed "现金" 通过 default_assets.dart 主动置 true
    _isDefault = a?.isDefault ?? false;
    // 2026-10-15 D61:actAsCashFlow 初始化
    //   - 新增模式 + receivable → false(花呗/白条/车贷/房贷都默认关,user 主动开)
    //   - 新增模式 + 其它 type → false(此字段只对 receivable 有义,其它 type 永远是 false)
    //   - 编辑模式 → 用已有值(用户已设定)
    _actAsCashFlow = a?.actAsCashFlow ?? false;
    // 2026-10-16 D64.58:isLender 初始化
    //   - 新增模式 + receivable → false(默认"借入",即我是负债方)
    //   - 新增模式 + 其它 type → false(此字段只对 receivable 有义,其它 type 永远是 false)
    //   - 编辑模式 → 用已有值(用户已设定)
    _isLender = a?.isLender ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  /// D72 加:编辑资产"期初余额"时,如果用户输入 ≠ 旧 currentBalance,
  /// 自动生成一笔 type='balance' 流水(amount = oldCurrent - newInit)抹平差值,
  /// 让 newCurrent = newInit。背景:
  ///   - bug:之前 update() 直接覆盖 initialBalance,导致 newCurrent = newInit + delta,
  ///     user 改余额"平账"几毛一块时,流水 delta 大会让资产变负。
  ///   - 修法:用 type='balance' 流水(不算月度收支,只动资产)补足差值,
  ///     cat='余额调整'(isSystem=true, UI 隐藏,启动 seed 兜底)。
  ///   - 公式:newCurrent = newInit + (delta + adj)
  ///     设 newCurrent = newInit(用户期望) → adj = -delta = oldInit - oldCurrent
  ///   - 容差:差值 < 0.005 元(半分钱)算浮点误差,跳过流水(避免无意义 0.00 ~ 0.004 噪音)。
  ///   - 注意:必须在 update asset.initialBalance 之前调,否则 oldCurrent 重新算会变。
  Future<void> _maybeCreateBalanceAdjust({
    required Asset existing,
    required double newInit,
  }) async {
    final oldCurrent = await ref.read(assetBalanceProvider(existing.id).future);
    final oldInit = existing.initialBalance;
    // adj 让 newCurrent = newInit:adj = oldInit - oldCurrent = -delta
    final adjustment = oldInit - oldCurrent;
    if (adjustment.abs() < 0.005) return; // 浮点容差

    final cat = await ref.read(categoryRepositoryProvider).findByName('余额调整');
    if (cat == null) {
      // 极端兜底:启动 seed 没跑(或被 user 删了"余额调整"),弹 toast 不阻塞保存,
      // user 看到再去"我的 → 备份还原"重置或手动加流水。
      _toast('缺少"余额调整"分类,请重启 App 或联系开发者');
      return;
    }
    await ref.read(transactionRepositoryProvider).add(
      amount: adjustment,
      type: 'balance',
      categoryId: cat.id,
      occurredAt: DateTime.now(),
      note: '余额调整',
      accountId: existing.id,
    );
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
    // (2026-10-13 P6 改:上限校验下放到 inputFormatter,实时拒绝超过
    //  9,999,999.99 的输入,这里不再弹 toast 提示)
    setState(() => _saving = true);
    try {
      final repo = ref.read(assetRepositoryProvider);
      // 2026-10-13 P7:是否要把这条 cash_flow 标为"日常流水默认账户"
      // - 切到非 cash_flow 段时,IsDefaultCard 不显示,_isDefault 永远 false,这里不进
      // - 保证 cash_flow 段单例(由 repo.setDefaultForCashFlow 维护)
      final markDefault = _isDefault && _type == 'cash_flow';
      late final int savedId;
      if (widget.existing == null) {
        savedId = await repo.create(
          name: name,
          type: _type,
          icon: _icon,
          color: _color,
          initialBalance: balance,
          includeInTransactions: _includeInTransactions,
          isDefault: markDefault,
          // 2026-10-15 D61:receivable 段"充当现金流"开关
          //   - 非 receivable 段 _actAsCashFlow 永远是 false(form 切 type 时已清零)
          actAsCashFlow: _actAsCashFlow,
          // 2026-10-16 D64.58:receivable 段"借出"开关
          //   - 非 receivable 段 _isLender 永远是 false(form 切 type 时已清零)
          isLender: _isLender,
        );
      } else {
        // D72:先调 balance adjust(在 update initialBalance 之前,oldCurrent 才正确)
        await _maybeCreateBalanceAdjust(
          existing: widget.existing!,
          newInit: balance,
        );
        final updated = widget.existing!.copyWith(
          name: name,
          type: _type,
          icon: _icon,
          color: _color,
          initialBalance: balance,
          includeInTransactions: _includeInTransactions,
          isDefault: markDefault,
          // 2026-10-15 D61:同新增,所有 type 都传(非 receivable 段切到时已清零)
          actAsCashFlow: _actAsCashFlow,
          // 2026-10-16 D64.58:同新增,所有 type 都传(非 receivable 段切到时已清零)
          isLender: _isLender,
        );
        await repo.update(updated);
        savedId = updated.id;
      }
      // 2026-10-13 P7:打开默认账户时调 setDefaultForCashFlow
      // 保证 cash_flow 段同时只有 1 只 isDefault=true(批量清掉老默认 + 开启新默认)
      // 解决 race,确保单例
      if (markDefault) {
        await repo.setDefaultForCashFlow(savedId);
      }
      // 广谱 invalidate(包含 asset 列表 + balances map)
      refreshAllData(ref);
      ref.invalidate(allAssetsProvider);
      if (mounted) context.pop();
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
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    // 2026-10-15 D64.20 改:本页面从 raw Navigator.push 改为 context.push('/settings/assets/edit', extra: existing)
    //   (app_router.dart 里走的 go_router 路线),所以不再需要 D64.18 加的 PopScope
    //   拦截 back 键 —— go_router 自动处理路由 pop,Navigator.pop 改 context.pop。
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑账户' : '新增账户'),
          actions: [
            // 右上角"保存"按钮(2026-10-13 P6 整页重构后,AppBar 替代底部 FilledButton)
            IconButton(
              tooltip: '保存',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s3,
              AppSpacing.s4,
              AppSpacing.s5,
            ),
            children: [
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

              // 类型(2026-10-13 P6 第 5 次改:外层大圆角 card + 单列 radio
              //   - 第 4 版的 ListView + Divider 散开,user 反馈"用圆角矩形更柔和"
              //   - 改 ColorOS 14 Aquamorphic Card-Styled Layout 标准
              //   - 6 行包裹在 1 个 16px 圆角大 card 内,选中行 tint 0.10
              //   2026-10-13 P7:onPick 同步重置 _isDefault(切走 cash_flow 强制清掉默认标记)
              const _SectionLabel('类型'),
              const SizedBox(height: AppSpacing.s2),
              _TypeRadioList(
                value: _type,
                onPick: (v) => setState(() {
                  _type = v;
                  // 切到非 cash_flow 段 → 默认账户开关无意义,清掉避免存脏数据
                  if (v != 'cash_flow') _isDefault = false;
                  // 2026-10-15 D61:切到非 receivable 段 → 充当现金流开关无意义,清掉
                  //   (此字段只对 receivable 段有义,其它 type 永远是 false)
                  if (v != 'receivable') _actAsCashFlow = false;
                  // 2026-10-16 D64.58:切到非 receivable 段 → 借出开关无意义,清掉
                  //   (此字段只对 receivable 段有义,其它 type 永远是 false)
                  if (v != 'receivable') _isLender = false;
                }),
              ),
              const SizedBox(height: AppSpacing.s4),

              // 2026-10-13 P7:默认账户开关(仅 cash_flow 显示)
              //   - 切换用户最常用的现金账户为"日常流水默认",记一笔默认选中
              //   - 非 cash_flow 段记一笔不会选中,该开关无意义,隐藏避免误操作
              if (_type == 'cash_flow') ...[
                const _SectionLabel('默认'),
                const SizedBox(height: AppSpacing.s2),
                AquaRowCard(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  icon: _isDefault
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  iconColor: _isDefault
                      // D71.2:跟随 palette(浅粉 → 亮粉,默认 → 金黄)
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.onSurfaceVariant,
                  title: '设为默认账户',
                  subtitle: _isDefault
                      ? '记一笔时优先选中这条账户'
                      : '关闭后,其他现金账户可设为默认',
                ),
                const SizedBox(height: AppSpacing.s4),
              ],

              // 2026-10-13 P6 第 6 次改:计入日常流水
              //   - user UAT:样式很奇怪,参考 settings_page.dart 的"显示金额"按钮
              //   - 改 AquaSwitch(拟物风,44x26,带外发光 + thumb 阴影)替换 Switch.adaptive
              //   - 整行用 16px 圆角 card 包裹,跟类型 card 风格统一(Aquamorphic Card-Styled)
              //   - leading icon + 主标 + 副标(11sp 灰)+ trailing AquaSwitch
              //   - 跟"显示金额"开关 ListTile 风格完全一致
              const _SectionLabel('日常'),
              const SizedBox(height: AppSpacing.s2),
              AquaRowCard(
                value: _includeInTransactions,
                onChanged: (v) => setState(() => _includeInTransactions = v),
                icon: _includeInTransactions
                    ? Icons.sync_alt_rounded
                    : Icons.sync_disabled_rounded,
                iconColor: theme.colorScheme.onSurfaceVariant,
                title: '计入日常流水',
                subtitle: _includeInTransactions
                    ? '会显示在流水页'
                    : '不会显示在流水页(投资/福利/债权等)',
              ),
              const SizedBox(height: AppSpacing.s4),

              // 2026-10-15 D61:充当现金流开关(仅 receivable 段显示)
              //   - user UAT 反馈:"债务这里的属性还需要增加一个按钮,就是'充当现金流'",
              //   区分"花呗/白条等可消费债务"(可作 cash_flow 支出 source)
              //   vs"车贷/房贷等不可消费债务"(只能在 receivable 段调拨还款)。
              //   - 只有开启了"充当现金流"的 receivable 账户才在记一笔 cash_flow 支出 picker 里出现
              //   - 非 receivable 段此开关无意义,隐藏避免误操作(同 IsDefaultCard 套路)
              if (_type == 'receivable') ...[
                AquaRowCard(
                  value: _actAsCashFlow,
                  onChanged: (v) => setState(() => _actAsCashFlow = v),
                  icon: _actAsCashFlow
                      ? Icons.credit_card_rounded
                      : Icons.credit_card_off_rounded,
                  iconColor: _actAsCashFlow
                      ? AppStatus.warning
                      : theme.colorScheme.onSurfaceVariant,
                  title: '充当现金流',
                  subtitle: _actAsCashFlow
                      ? '记一笔支出时可选这条账户(花呗/白条/信用卡等可消费债务)'
                      : '仅在债务段调拨还款用(车贷/房贷/借款等不可消费债务)',
                ),
                const SizedBox(height: AppSpacing.s4),
                // 2026-10-16 D64.58:借出开关(仅 receivable 段显示)
                //   - user UAT 反馈:"还需要为债务的资产类型增加一个开关,
                //     默认是借入,打开的时候是借出,就是应对借给老王的这种债权人情况,
                //     先有 label,然后才能做进一步的分析"
                //   - 默认 false = 借入(我是负债方,余额为负,花呗/车贷/房贷/借款)
                //   - 打开 true = 借出(我是债权人,余额为正,例如借给老王)
                //   - 放在 AquaRowCard 之后,跟 receivable 段 toggle 风格统一
                //   - 本次 D64.58 只做 label 落地;后续 D64.59+ 才展开联动
                AquaRowCard(
                  value: _isLender,
                  onChanged: (v) => setState(() => _isLender = v),
                  icon: Icons.handshake_rounded,
                  iconColor: _isLender
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  title: '借出',
                  subtitle: _isLender
                      ? '我是债权人,余额为正(例如借给老王)'
                      : '我是负债方,余额为负(例如花呗/车贷/房贷/借款)',
                ),
                const SizedBox(height: AppSpacing.s4),
              ],

              // 期初余额(可负,代表初始欠款)
              // 2026-10-13 P6 改:
              //   - inputFormatter 实时拒绝超过 9,999,999.99 的输入(超过不让进)
              //   - 输入框下面红字提示"上限 9,999,999.99"作为说明(永远显示)
              //   - _save() 不再校验上限(inputFormatter 已经卡住,重复了)
              const _SectionLabel('期初余额'),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.\-]')),
                  _BalanceLimitFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: '默认 0;负债可填负数',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              // 2026-10-13 P6:输入框下面红字"上限 9,999,999.99"提示
              // 跟 inputFormatter 联动:超过不让进,所以红字只是说明性提示
              const Padding(
                padding: EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  '上限 9,999,999.99',
                  style: TextStyle(fontSize: 11, color: AppStatus.error),
                ),
              ),
              const SizedBox(height: AppSpacing.s3),

              // 图标(2026-10-14 D48 续:扁平 Wrap,43 个 icon 不分类)
              //   - 之前分组 + 子 label,user 反馈"图标不需要分类,不用指导用户"
              //   - 改成扁平 Wrap,user 自己挑
              //   - 走 AssetTile.renderIcon() 统一入口(material + brand 自动判别)
              const _SectionLabel('图标'),
              const SizedBox(height: AppSpacing.s2),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: _iconKeys.map((k) {
                  final selected = _icon == k;
                  final isBrand = AssetTile.isBrandKey(k);
                  return InkWell(
                    onTap: () => setState(() => _icon = k),
                    borderRadius: AppRadius.brMd,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        // brand chip 已有品牌背景,picker 底色用 surfaceContainerLow
                        // 避免双重色块冲突
                        color: !isBrand && selected
                            ? Color(_color).withValues(alpha: 0.18)
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: AppRadius.brMd,
                        border: Border.all(
                          color: selected ? Color(_color) : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      // brand chip 内部渲染:不再套 tint,让品牌色透出来
                      child: isBrand
                          ? AssetTile.renderIcon(k, size: 28)
                          : Icon(
                              AssetTile.icons[k] ??
                                  Icons.account_balance_wallet_rounded,
                              color: selected ? Color(_color) : AppGray.g600,
                              size: 22,
                            ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.s1),

              // 颜色
              const _SectionLabel('颜色'),
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
                        // D71.2:选中边框跟随 palette(粉色 → 深紫红)
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.inverseSurface
                              : Colors.transparent,
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

              // 编辑模式才显示"删除账户"按钮(2026-10-13 P6 加,整页后才有空间)
              if (isEdit) ...[
                const SizedBox(height: AppSpacing.s3),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _confirmDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('删除账户'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppStatus.error,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s3,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }

  Future<void> _confirmDelete() async {
    final a = widget.existing!;
    final repo = ref.read(assetRepositoryProvider);
    // 引用计数:被多少条流水引用? > 0 提示先改
    final txCount = await repo.usageCount(a.id);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账户'),
        content: Text(
          txCount > 0
              ? '「${a.name}」已被 $txCount 条流水引用,删除会失败。\n建议先把这些流水的账户改成其他账户,再来删除。'
              : '确定删除「${a.name}」吗?此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppStatus.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.delete(a.id);
      refreshAllData(ref);
      ref.invalidate(allAssetsProvider);
      if (mounted) {
        context.pop(); // 关闭 form page
      }
    } catch (e) {
      if (mounted) _toast('删除失败:$e');
    }
  }
}

/// section label(2026-10-13 P6 整页后,各 section 用统一 label 风格)
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ============================================================================
// 类型单选 card(2026-10-13 P6 第 5 次改):
//   - user UAT:类型选择区用圆角矩形更柔和,看 ColorOS 14 Aquamorphic 标准
//   - ColorOS Card-Styled Layout:整组 6 行包裹在 1 个大圆角 card 内
//   - 外层 16px 圆角矩形(brLg) + 1px outlineVariant + surfaceContainerLow 底色
//   - clipBehavior 让选中行 tint 在圆角处被正确裁剪
//   - 内 6 行 Material + InkWell 紧贴,行间 1px outlineVariant hairline (alpha 0.35, indent 56)
//   - 选中行:type 配色 0.10 整行 tint(被外层圆角裁剪)
// ============================================================================

class _TypeRadioList extends StatelessWidget {
  const _TypeRadioList({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  /// 2026-10-14 D47:6 段类型配置统一走 AppSegment 集中数据源
  ///   - 之前硬编码 icon / color / label 三元组 + _colorFor switch,跟资产页 / 报表不一致
  ///   - user 反馈:'这里的颜色图标要与新增账户里面的保持一致'
  ///     + '报表 / 资产管理页面 / 新增资产页面的都不一样,你再统一一下图标和颜色'
  ///   - 修:全部走 AppSegment.iconFor / labelFor / colorFor,删 _colorFor switch
  ///   - 跨 3 页(报表 / 资产页 / 新增账户)视觉一致,改一处生效全部
  static const _order = [
    'cash_flow',
    'investment',
    'benefit',
    'receivable',
    'fixed_asset',
    'other',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 外层大圆角矩形 card(ColorOS 14 Aquamorphic Card-Styled Layout)
    // - 16px 圆角(brLg) + 1px outlineVariant + surfaceContainerLow 底色
    // - clipBehavior 让选中行的 tint 底色在圆角处被正确裁剪
    // - 内 6 行紧贴 Column,行间 1px outlineVariant hairline (indent 56 = icon 32 + padding 24)
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _order.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.only(left: 56),
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            _TypeRadioRow(
              typeKey: _order[i],
              label: AppSegment.labelFor(_order[i]),
              icon: AppSegment.iconFor(_order[i]),
              selected: value == _order[i],
              color: AppSegment.colorFor(_order[i]),
              onTap: () => onPick(_order[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个类型 radio row(card 内 1 行)
/// 风格:icon chip (左,32px 圆) + label (主标,15sp) + radio (右,22px)
/// 选中行:整行底色 type tint 0.10(被外层 card 圆角裁剪)
class _TypeRadioRow extends StatelessWidget {
  const _TypeRadioRow({
    required this.typeKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String typeKey;
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 选中行:整行底色 type tint 0.10(被外层 card 圆角裁剪)
    // 未选行:透明(继承外层 card 的 surfaceContainerLow)
    return Material(
      color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
            child: Row(
              children: [
                // icon chip(32px 圆形,Aquamorphic 圆滑水珠感)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: AppSpacing.s3),
                // label(主标)
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? color : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                // radio(右对齐,自定义外观贴合 type 配色)
                _TypeRadio(selected: selected, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 自定义 radio(单选圈)
/// - 选中:实心 type 配色 + 中心白 check
/// - 未选:outline 边框 + 中心空白
class _TypeRadio extends StatelessWidget {
  const _TypeRadio({required this.selected, required this.color});
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : theme.colorScheme.outline,
          width: 2,
        ),
        color: selected ? color : Colors.transparent,
      ),
      child: selected
          ? const Center(
              child: Icon(Icons.check, color: Colors.white, size: 14),
            )
          : null,
    );
  }
}

/// 2026-10-13 P6 加:期初余额 inputFormatter
/// - 超过 9,999,999.99 的输入实时拒绝(不让进 TextField)
/// - 解析失败(null)也拒绝(防止 "1.2.3" / "abc" 之类垃圾)
/// - 负号 / 小数点中间态允许(用户在打字过程中)
/// - 跟 transaction_form 流水金额上限一致(app 定位个人记账)
class _BalanceLimitFormatter extends TextInputFormatter {
  static const double _maxAbs = 9999999.99;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // 中间态:用户正在打负号或小数点,允许通过
    if (text == '-' ||
        text == '.' ||
        text == '-.' ||
        text.endsWith('-') ||
        text.endsWith('.')) {
      return newValue;
    }

    // 解析
    final v = double.tryParse(text);
    if (v == null) return oldValue; // 解析失败(如 "1.2.3" 多小数点)→ 拒绝
    if (v.abs() > _maxAbs) return oldValue; // 超限 → 拒绝

    return newValue;
  }
}
