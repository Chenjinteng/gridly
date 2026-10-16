// lib/features/settings/ui/widgets/asset_tile.dart
// 我的页"资产"section 列表 tile —— 单个资产展示
//
// 2026-10-12 P2 commit 加:
//   - 跟 category_management_page 的 _CategoryTile 同款风格(Container 卡片 + ListTile)
//   - leading:icon chip(账户色块)
//   - title:name
//   - subtitle:type chip + 余额(余额从 assetBalanceProvider 取)
//   - trailing:[编辑][删除] IconButton(同 CategoryTile)
//   - 点 tile 整体也可触发编辑,跟 CategoryTile onEdit 一致
//
// 2026-10-13 P6 第 2 次改(UAT 反馈):
//   - subtitle 拆 2 行:
//     - 第一行:type chip + 计入/不计入 chip(用户明确要"像现金流 chip 一样显示")
//     - 第二行:金额独立一行(用户说金额长时给更多空间)
//   - 计入流水 chip = 主题黄(AppBrand.gold);不计入 = 灰色(AppGray.g600)
//   - 金额 0.00 用主题灰(AppGray.g400),"无数据"状态更明显
//   - 删 title 末尾的 archive icon(include chip 在 subtitle 已经有更明显显示)
// 2026-10-13 P7 第 3 次改(UAT 反馈):加"默认"chip
//   - 仅 cash_flow 段且 isDefault=true 时,在 subtitle 第一行插入"默认" chip
//   - 位置:type chip 之后(语义高亮,"默认账户"是比"是否计入"更突出的状态)
//   - 配色:AppBrand.gold(跟 _IsDefaultCard + 计入 chip 同款,视觉语言统一)
//   - 配合 Assets.isDefault 字段(3309b23),user 在资产 form 开启默认后,资产列表一眼能看到"哪条是默认"
// 2026-10-16 D64.41 改(UAT 反馈):
//   - 截图反馈"现金"账户 tile 第一行 3 chip(流动资金 + 默认 + 计入流水)
//     + 2 个 trailing icon 总宽超 ListTile 可用宽度,触发 `RIGHT OVERFLOWED BY 71 PIXELS`
//   - 修法:subtitle 第一行 chips Row → Wrap(chips 多时换行)
//     - spacing: 6(水平间距,跟原 Row SizedBox(width:6) 一致)
//     - runSpacing: 4(换行垂直间距)
//     - 短 chip (1-2 个) 保持一行,长 chip (3-4 个或文字超长) 自动换行
//     - Wrap 替代 Row 是 Flutter 标准 "horizontal overflow → 多行" 解法
//   - 不改 chip 文字 / padding / fontSize,只换 layout,保持视觉风格不变
// 2026-10-16 D64.42 改(user UAT 反馈):
//   - user 反馈"资产 tile 跟流水 tile 很像,为什么不把编辑删除做成滑动操作,UI 和操作都统一"
//   - 修法:tile wrap 进 `SwipeToActions`(从 transaction_tile 的 `_SwipeToDelete` 抽出
//     的 public 共享 widget,见 lib/core/widgets/swipe_to_actions.dart)
//   - 删 trailing 的 [编辑][删除] 两个 InkWell(原代码占用 80px,跟 Wrap 一起解决 71px 溢出)
//   - 不传 SwipeToActions.onTap(默认 null):tile 自身 onTap 走 noop,
//     但 SwipeToActions 内部 onTap handler 仍会清 openSwipeIdProvider + _close,
//     实现"点 tile 收回正在滑开的 tile"(点编辑/删除按钮 InkWell 会吃掉 tap,
//     不会触发这条)
//   - iOS Mail.app 风格:左滑露 [编辑 64px + gap + 删除 64px] 按钮,跟流水 tile 完全一致
//   - 物理参数 / 弹性 / fling 速度 / spring / openSwipeIdProvider 全局互斥 = 跟流水共用一套
// 2026-10-16 D64.43 改(user UAT 反馈):
//   - user 反馈"感觉是因为有三列所以给拉高了吧,所以滑动出来的两个按钮也被拉高了,
//     我觉得可以调整为两列:名称 + 金额 + chips 在下方;另外,底色换成主题黑色,
//     区别一般的流水"
//   - 修法:
//     ① ListTile 三列布局(leading + title+subtitle + trailing slot)→ 自绘 2 列
//       Row(leading 36 + name Expanded + amount 右对齐),name 和 amount 在同一行,
//       chip Wrap 在第二行。整体 tile 高度由"自然内容"决定(leading 36 + s2 + chips),
//       滑动按钮高度跟 tile 高度 1:1,不再被"ListTile trailing slot 空白 padding"拉高
//     ② 底色 theme.colorScheme.surfaceContainerLow(流水 tile 的浅色)→ AppBrand.ink
//       (主题黑色,跟净资产卡 / range_summary / 关于卡 一致)
//     ③ outline 跟 主题黑 卡一致:1px white alpha 0.08-0.15(浅色主题)/ 0.08(深色主题)
//     ④ shadow 跟 主题黑 卡一致:CardShadows.dark(context)
//     ⑤ 字体色:title 文字 → cream(AppSecondary.cream,在 ink 上读得清),
//       amount → AppSemantic.balanceFor(0=g400,>0=teal,<0=error)沿用,跟其它卡视觉语言一致
// 2026-10-16 D64.43.2 改(user UAT 反馈):
//   - user 反馈"不是这样,要做成流水卡片那种,logo 是直接全占了左边"
//   - 修法:
//     ① leading 从 36×36 → 56×56(占满 tile 高度),居中显示 28px icon,
//       card 内边距 s3(12px),logo 占大部分左侧空间
//     ② 卡片内布局 Row → leading 56 + s3 gap + Expanded(Column [Row [name+amount], chips Wrap])
//     ③ logo 在 ink 黑底上 alpha 0.18 background + icon color 0.7 / 24-28px,
//       视觉"全占左边"突出资产标识,跟 transaction_tile leading 36 风格统一但更显眼
//     ④ 卡片总高 ≈ max(leading 56, content 自然高度),滑出按钮高度跟 tile 高度 1:1
//     ⑤ name 字号 14 → 15(主信息更突出),amount 14 → 16(加强视觉权重)
// 2026-10-16 D64.43.3 改(user UAT 反馈):
//   - user 反馈"还是很奇怪,跟流水卡片差在哪里吗?或者按流水卡片的高度来修改一下?
//     好像 logo 也偏大"
//   - 实测对比:流水卡片高 ~52px(asset_tile 当前 ~80px,高 54%),主要差距在
//     ① leading 56 vs 流水 36(大 20)
//     ② padding s3(12) vs 流水 8(大 4×2=8)
//   - 修法:
//     ① leading 56 → **48**(跟流水 36 的比例感同,但仍"占满左边"视觉)
//     ② padding s3 → **s2(8)**(跟流水 default contentPadding 对齐)
//     ③ logo icon 28 → **24**(适配 48 box)
//     ④ chip padding horizontal 6 → **4**(chip 更紧凑,流水卡片 label 字号
//       也是 12sp 比 asset 15sp 小,chip 紧凑是视觉对齐的一部分)
//   - 预期新总高 ≈ 8 + max(48, name 18 + s2 8 + chips 20) = 64px
//     vs 流水 52px,asset 仍多 12px(因为 asset 多 1 行 chips 内容),合理
// 2026-10-16 D64.43.4 改(user UAT 反馈):
//   - user 反馈"感觉好像有点不是很搭,颜色换成主题青"
//   - 修法:
//     ① 卡片底色 `AppBrand.ink`(炭黑,0xFF0F1419)→ **`AppBrand.teal`(明亮青,0xFF14B8A6)**
//     ② outline rim border 白色 alpha 调整:深色主题 0.15 / 浅色主题 0.30
//       (teal 比 ink 浅,需要更强 outline 区分边缘)
//     ③ shadow 沿用 `CardShadows.dark(context)`(teal 在亮底上 + 深色阴影好看)
//     ④ name 文字色 `AppSecondary.cream`(米白)→ **`Colors.white`**(teal 底上纯白最清晰)
//     ⑤ amount 文字色:正数保留 `AppBrand.teal`(但 teal 底上太相近,改 `Colors.white`);
//       负数保留 `AppStatus.error` 但提到 0.95 alpha(亮底上红需要更饱和);
//       0 用 `Colors.white54` 弱化
//     ⑥ chip 底色 alpha 0.20 → 0.18 + 文字 `Colors.white` 覆盖(teal 底上白 chip)
//     ⑦ logo icon 在 teal 底上保留原 asset.color,但 logo 底色从 0.20 alpha
//       提到 0.28(增强 logo 在亮底上的辨识度)
// 2026-10-16 D64.44 改(user UAT 反馈):
//   - user 反馈"左滑动是暴露编辑删除按钮,但是直接点击卡片也会进入编辑,
//     这不行,把这个点击进入编辑的去掉"
//   - 背景:asset tile 现在走 SwipeToActions 左滑露 [编辑 64 + 删除 64] 按钮,
//     D64.43 之前 tile 自身也 onTap = onEdit(user 早起 PageTile 行为),
//     形成"点 tile 进编辑 + 左滑也能进编辑"的入口重复
//   - 修法:
//     ① 不传 SwipeToActions.onTap,内部 tile GestureDetector.onTap 走 noop
//       (SwipeToActions 默认 onTap = null,widget.onTap?.call() 在 null 时不会触发)
//     ② SwipeToActions 内 tile GestureDetector.onTap handler 仍会做:
//        - ref.read(openSwipeIdProvider.notifier).state = null
//        - _close()
//        → 实现"点 tile 收回正在滑开的 tile"(点编辑/删除按钮时 InkWell 吃掉 tap,
//          这条不触发;这跟 ledger tile 行为一致)
//     ③ 编辑只能走 SwipeToActions 左滑露 [编辑] 按钮这一个入口,
//       删除走左滑 [删除] 按钮(纯 destructive 按钮,iOS Mail 同款)
//     ④ 不要给 tile 加"无响应"的副作用:用户点 tile 时视觉上无动作只收回正在滑开的 tile,
//       这是有意义的(关 swipe),跟 ledger 一致
//   - 不改 assets_management_page 的外层 GestureDetector(它仍然是"点屏幕收回正在滑开的 tile",
//     跟 ledger page 同样模式)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/card_shadows.dart';
import '../../../../core/utils/asset_balance_provider.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/swipe_to_actions.dart';

/// 资产列表 tile
///   - name / type / icon / color / currentBalance(实时算)
///   - onEdit / onDelete:用户操作回调
class AssetTile extends ConsumerWidget {
  const AssetTile({
    super.key,
    required this.asset,
    required this.onEdit,
    required this.onDelete,
  });
  final Asset asset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// icon 名 → IconData 映射(2026-10-12 P2):
  /// 2026-10-13 P6 UAT 扩:资产 icon 池(覆盖通用钱包/支付/保险/股票/债券等)
  ///   - 之前 8 个 icon 不够:用户要"保险/股票/债券/钱包/微信/支付宝/银联"
  ///   - Material Icons 没品牌 icon(微信/支付宝/银联),需要 brand assets;
  ///     这次先扩通用池,品牌 icon 等 user 后续提供素材再加
  ///   - Flutter Material Icons 内置 + 通用钱包/支付类
  /// 2026-10-14 D48:扩 8 个票务 / 充值 / 餐饮 / 兑换类,user 要丰富账户图标池
  static const Map<String, IconData> icons = {
    // 钱包 / 支付 / 现金
    'account_balance_wallet': Icons.account_balance_wallet_rounded, // 钱包通用
    'wallet': Icons.wallet_rounded, // 钱包
    'payments': Icons.payments_rounded, // 支付
    'credit_card': Icons.credit_card_rounded, // 信用卡
    'savings': Icons.savings_rounded, // 储蓄
    'account_balance': Icons.account_balance_rounded, // 银行
    'currency_yen': Icons.currency_yen_rounded, // 现金(¥)
    'attach_money': Icons.attach_money_rounded, // 现金($)
    'monetization_on': Icons.monetization_on_rounded, // 现金
    // 支付品牌(Material 内置品牌 icon,2026-10-14 D48 加)
    'apple_pay': Icons.apple_rounded, // Apple Pay(走 Material apple icon,跨平台稳)
    // 资产类型
    'home': Icons.home_rounded, // 不动产
    'directions_car': Icons.directions_car_rounded, // 车
    'landscape': Icons.landscape_rounded, // 土地
    'apartment': Icons.apartment_rounded, // 公寓
    // 投资 / 股票 / 债券
    'trending_up': Icons.trending_up_rounded, // 涨跌
    'candlestick_chart': Icons.candlestick_chart_rounded, // K 线
    'show_chart': Icons.show_chart_rounded, // 曲线
    'receipt_long': Icons.receipt_long_rounded, // 债券
    'assessment': Icons.assessment_rounded, // 报表
    // 保险 / 保障
    'health_and_safety': Icons.health_and_safety_rounded, // 保险
    'shield': Icons.shield_rounded, // 盾牌
    'security': Icons.security_rounded, // 安全
    'verified': Icons.verified_rounded, // 已验证
    // 票务 / 充值 / 餐饮 / 兑换(2026-10-14 D48 加)
    'card_giftcard': Icons.card_giftcard_rounded, // 礼品卡
    'confirmation_number': Icons.confirmation_number_rounded, // 票务
    'theater_comedy': Icons.theater_comedy_rounded, // 娱乐
    'restaurant': Icons.restaurant_rounded, // 餐饮
    'redeem': Icons.redeem_rounded, // 兑换/积分
    'flight': Icons.flight_rounded, // 机票
    'train': Icons.train_rounded, // 火车
    'local_activity': Icons.local_activity_rounded, // 活动
    // 福利 / 借出 / 其它
    'favorite': Icons.favorite_rounded, // 福利
    'handshake': Icons.handshake_rounded, // 借出
    'swap_horiz': Icons.swap_horiz_rounded, // 调拨
    'category': Icons.category_rounded, // 其它
  };

  /// 2026-10-14 D48:品牌 / 加密 / 银行 letter chip icon 映射
  ///   - Material Icons 内置无品牌 logo(Alipay/微信/Apple Pay/Google Pay/ePay)
  ///   - 走 brand:xxx / crypto:xxx / bank:xxx 命名空间前缀,跟 material key 不冲突
  ///   - 自渲染彩色圆形 + 单字/单符号(支/微//G/e + ₿/Ξ/₮ + 招/工/建/农/中)
  ///   - 颜色用各品牌官方色 + 数字货币 / 银行标准色
  ///   - 跨页统一(form picker + asset tile leading 都走 AssetTile.renderIcon)
  static const Map<String, BrandIconSpec> brandIcons = {
    // === 支付品牌(支付宝 / 微信 / Apple Pay / Google Pay / ePay + 银联)===
    'brand:alipay': BrandIconSpec('支', Color(0xFF1677FF)), // 支付宝蓝
    'brand:wechat': BrandIconSpec('微', Color(0xFF07C160)), // 微信绿
    'brand:google_pay': BrandIconSpec('G', Color(0xFF4285F4)), // Google 蓝
    'brand:epay': BrandIconSpec('e', Color(0xFF6B7280)), // ePay 灰(中性,无强品牌色)
    'brand:unionpay': BrandIconSpec(
      '银',
      Color(0xFFE21836),
    ), // 银联红(2026-10-14 D48 简化:只留银联)
    // === 加密货币(Bitcoin / Ethereum / USDT)===
    'crypto:btc': BrandIconSpec('₿', Color(0xFFF7931A)), // Bitcoin 橙
    'crypto:eth': BrandIconSpec('Ξ', Color(0xFF627EEA)), // Ethereum 紫
    'crypto:usdt': BrandIconSpec('₮', Color(0xFF26A17B)), // Tether 绿
  };

  /// 2026-10-14 D48:统一 icon 渲染入口
  ///   - material key:走 Material Icon(跟现有一样)
  ///   - brand:/crypto:/bank: 前缀:走 Container 自渲染彩色圆 + 字
  ///   - 未知 key:fallback wallet_rounded,跟现有兜底一致
  ///   - 跨页(form picker + asset tile leading)统一走这个,避免 brand 漏渲染
  static Widget renderIcon(String key, {double size = 22, Color? tintColor}) {
    final matIcon = icons[key];
    if (matIcon != null) {
      return Icon(matIcon, size: size, color: tintColor);
    }
    final brand = brandIcons[key];
    if (brand != null) {
      // brand chip:正方形(资产 form picker 44x44 + asset tile 36x36 都用这个)
      // 字大小跟 size 成比例(0.55 倍),中文 0.6 倍
      //   letter 为空(无单字 / 符号,如未来纯色块):只渲染背景,不渲染 Text
      final hasLetter = brand.letter.isNotEmpty;
      final fontSize = hasLetter ? size * 0.55 : 0.0;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: brand.color,
          borderRadius: AppRadius.brXs,
        ),
        alignment: Alignment.center,
        child: hasLetter
            ? Text(
                brand.letter,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.0,
                ),
              )
            : null,
      );
    }
    return Icon(
      Icons.account_balance_wallet_rounded,
      size: size,
      color: tintColor,
    );
  }

  /// 2026-10-14 D48:判断 key 是否走 brand letter chip(给 form picker / db 列展示用)
  static bool isBrandKey(String key) =>
      key.startsWith('brand:') ||
      key.startsWith('crypto:') ||
      key.startsWith('bank:');

  /// type 名 → 中文标签(2026-10-14 D47:统一走 AppSegment 集中数据源)
  ///   之前硬编码 6 段 label,跟资产页 / 报表不一致;现在走 AppSegment.labelFor
  ///   删硬编码 map,跨 3 页(总览 / 资产页 / 新增账户 / 报表)改一处生效全部
  static String labelFor(String type) => AppSegment.labelFor(type);

  /// 2026-10-14 P18:type 名 → 段色统一走 AppSegment(集中管理)
  static Color colorFor(String type) => AppSegment.colorFor(type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(asset.color);
    final typeColor = colorFor(asset.type);
    // 余额走 family provider 单查(避免 watch 整张 balances map)
    final balanceAsync = ref.watch(assetBalanceProvider(asset.id));
    final balance = balanceAsync.valueOrNull ?? 0.0;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // D64.42:tile 整段 wrap 进 SwipeToActions,左滑露 [编辑][删除] 按钮(共享 widget,跟 transaction_tile 同套交互)
    // D64.43:不再用 ListTile(3 列 leading + title+subtitle + trailing slot),改成自绘 2 列
    //   Row(leading + name Expanded + amount) + Wrap(chips),整体高度由自然内容决定,
    //   滑动按钮高度跟 tile 高度 1:1 不再被"ListTile trailing 空白 padding"拉高
    // D64.43.2:leading 56×56 大方块,占满 tile 高度,居中 28px icon,
    //   像流水卡片的 logo 一样"全占左边",卡片总高 ≈ 56 + s3 内边距 ≈ 64px
    return SwipeToActions(
      key: ValueKey('asset-${asset.id}'),
      tileId: asset.id,
      onEdit: onEdit,
      onDelete: onDelete,
      // D64.44:不传 onTap → tile 自身点击 noop(D64.43 之前是 onTap = onEdit,
      //   但左滑已经露编辑/删除按钮,user 反馈"直接点 tile 不该再进编辑"
      //   入口重复)。SwipeToActions 内部 onTap handler 仍会清
      //   openSwipeIdProvider + _close,实现"点 tile 收回正在滑开的 tile"
      //   (点编辑/删除按钮 InkWell 吃掉 tap,不触发这条;这跟 ledger tile 行为一致)
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s1,
        ),
        decoration: BoxDecoration(
          // D64.43.4:底色换主题青 `AppBrand.teal`(明亮青,0xFF14B8A6),
          //   跟 chips 上 teal 调一致,视觉统一;从原来 D64.43 黑底换青底
          //   (user 反馈黑底"不是很搭",改跟品牌色 teal 同色系)
          color: AppBrand.teal,
          borderRadius: AppRadius.brLg,
          // D64.43.4:rim border 白色 alpha 调整:浅色主题 0.30 / 深色主题 0.15
          //   (teal 比 ink 浅,需要更强 outline 区分边缘)
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.30),
            width: 1.0,
          ),
          boxShadow: CardShadows.dark(context),
        ),
        // D64.43.3:padding s3 → s2(8),跟流水卡片 default contentPadding 8 对齐
        padding: const EdgeInsets.all(AppSpacing.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 2026-10-14 D48 + 2026-10-16 D64.43.2/3/4:leading 大方块,全占 tile 高度
            //   - material:48×48 tinted box(asset.color 0.28 底 + asset.color icon 24px),
            //     teal 亮底上 alpha 从 0.20 提到 0.28 让 logo 更显眼
            //   - brand/crypto/bank:48×48 圆角盒,内部 brand chip 自带品牌色背景
            //     不再加 tinted 外框(避免双层色块冲突)
            isBrandKey(asset.icon)
                ? ClipRRect(
                    borderRadius: AppRadius.brSm,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: renderIcon(asset.icon, size: 48),
                    ),
                  )
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      // D64.43.4:teal 亮底上 alpha 提到 0.28 增强 logo 辨识
                      color: color.withValues(alpha: 0.28),
                      borderRadius: AppRadius.brSm,
                      border: Border.all(
                        color: color.withValues(alpha: 0.45),
                        width: 0.5,
                      ),
                    ),
                    child: Icon(
                      icons[asset.icon] ?? Icons.account_balance_wallet_rounded,
                      color: color,
                      size: 24,
                    ),
                  ),
            const SizedBox(width: AppSpacing.s3),
            // 右侧内容:Column [name + amount 一行 / chips Wrap 一行]
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行:name + amount
                  Row(
                    children: [
                      // name:Expanded 占剩余空间,长名字自动 ellipsis
                      Expanded(
                        child: Text(
                          asset.name,
                          style: const TextStyle(
                            // D64.43.3:name 字号 15 → 14,跟流水卡片对齐
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            // D64.43.4:teal 底上用 Colors.white 比 cream 更清晰
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      // amount:右对齐,w600 14sp(跟流水卡片对齐)
                      // D64.43.4:teal 底上余额颜色调整:
                      //   正数(原 teal)= Colors.white(teal 底同色消失)
                      //   负数(error 红)= 0.95 alpha 加亮
                      //   0(g400 浅灰)= Colors.white54 弱化
                      Text(
                        '¥${Formatters.amount(balance)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: balance == 0
                              ? Colors.white54
                              : balance > 0
                              ? Colors.white
                              : AppStatus.error.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s1),
                  // 第二行:chips Wrap(流动资金 / 默认 / 计入流水 等)
                  // D64.43.4:chip 在 teal 底上 — 颜色还是 chip.color(segment 语义色),
                  //   底色从 0.20 → 0.18 (青底上 0.20 偏重),
                  //   文字色在青底上需要提亮
                  Wrap(
                    spacing: 6, // 水平间距
                    runSpacing: 4, // 换行垂直间距
                    children: [
                      // type chip(同款胶囊,type 配色)
                      _TileChip(label: labelFor(asset.type), color: typeColor),
                      // 2026-10-13 P7:仅 cash_flow + isDefault=true 显示"默认" chip
                      if (asset.isDefault && asset.type == 'cash_flow')
                        const _TileChip(label: '默认', color: AppBrand.gold),
                      // 2026-10-13 P6:includeInTransactions chip
                      _TileChip(
                        label: asset.includeInTransactions ? '计入流水' : '不计入流水',
                        color: asset.includeInTransactions
                            ? AppBrand.gold
                            : AppGray.g600,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 资产 tile 小 chip(2026-10-13 P6 第 2 次改)
/// - 圆角 4px 胶囊
/// - 底色 `color.withValues(alpha:0.25)` 文字 `color`(D64.43.4 在 teal 亮底上
///   从 0.20 → 0.25 让 chip 更显眼;文字保持 chip.color 区分语义——cash_flow 段
///   chip 文字色是亮蓝,在 teal 底上虽然不强烈但 chip 底色已经区分 type chip vs 计入 chip)
/// - 10sp w600(跟之前 type chip 风格一致)
/// - 复用 type chip + 计入/不计入 chip 两种语义
class _TileChip extends StatelessWidget {
  const _TileChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      // D64.43.3:padding horizontal 6 → 4 vertical 1 → 0,更紧凑
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      decoration: BoxDecoration(
        // D64.43.4:teal 亮底上 chip 底色 alpha 0.20 → 0.25 更显眼
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 2026-10-14 D48:品牌 / 加密 / 银行 letter chip icon 配置
///   - letter:单字(支/微/G/e)或单符号(₿/Ξ/₮)或单字(招/工/建/农/中)
///   - color:品牌官方背景色,Container 用作底色
///   - 渲染走 AssetTile.renderIcon() 统一入口,跨 form picker + asset tile 一致
///   - 公开类:AssetTile.brandIcons 是 public API,spec 类型也得 public 避免 lint
class BrandIconSpec {
  const BrandIconSpec(this.letter, this.color);
  final String letter;
  final Color color;
}
