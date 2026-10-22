// lib/core/theme/app_colors.dart
// 配色规范来源:design/THEME.md v1.0
// 修改任何颜色前先查 THEME.md,不要直接覆盖本文件
import 'package:flutter/material.dart';

/// 品牌主色(三色)
class AppBrand {
  AppBrand._();
  static const Color ink = Color(0xFF0F1419); // 炭黑 · 主背景(Dark)
  static const Color charcoal = Color(0xFF1F2329); // 炭灰 · 主文字
  static const Color gold = Color(0xFFF5BC1F); // 金黄 · 收入 / CTA
  static const Color teal = Color(0xFF14B8A6); // 明亮青 · 支出 / 流动
  // design/THEME.html §1.2 (line 10 / 169-170 / 397) 明确定义的 brand color。
  // 视觉上 hue 174° 偏 green 那一侧(在中文里"青色"也常被理解为 green-leaning),
  // 用户在 2026-10-11 UAT 时明确说"我说青色其实是指绿色",所以维持设计稿原值不动。

  // 2026-10-16 D64.43.5 加:`navy` 夜蓝(资产 tile 底色专用)
  //   - D64.43.4 试 teal(0xFF14B8A6)作为资产 tile 底色,user UAT 否决"不搭"
  //     (撞 asset.color 默认 teal 同色系,看 logo 不出)
  //   - 4 候选 HTML demo 给 user 选,user 16:00 选 A 夜蓝
  //   - navy = 深空蓝(冷调),跟 teal chip 在色相轮互补,chip 最跳;
  //     深但不是黑(ink 是 0xFF0F1419 比 navy 还暗),跟主题黑背景区分
  //   - 仅 asset_tile.dart 用,不入 theme,所有 chip / amount / name 配色
  //     仍按 teal 版延用(D64.43.4 已通过 user 验证的对比度)
  static const Color navy = Color(0xFF1B2A41);
}

/// 粉色主题专用色板(D71.1 加 · 2026-10-19)
///   跟 AppBrand 平行,主品牌三色替换为暖粉调
///   使用方式:AppTheme.pinkLight() / AppTheme.pinkDark() 内取用
///   跟"主题"(light/dark)正交叠加,可组合出 4 种(浅粉/深粉/浅默认/深默认)
class AppPinkBrand {
  AppPinkBrand._();
  static const Color ink = Color(0xFF4A1942);       // 深紫红(D71.5.11:回归 #4A1942 冷紫)
  static const Color charcoal = Color(0xFF6B2C5F);   // 中紫
  static const Color gold = Color(0xFFFF5C8A);       // 亮粉(替代金)
  static const Color teal = Color(0xFFE84B7F);       // 深粉(替代青)
  static const Color softGold = Color(0xFFFFD9E5);  // 浅粉(替代 soft-gold)
  static const Color lightTeal = Color(0xFFFFE0EC); // 粉白(替代 light-teal)
  static const Color cream = Color(0xFFFFF5F8);      // 暖白(替代 cream)
  static const Color navy = Color(0xFF6B2C5F);       // 中紫(深色场景底色)
}

/// 辅助色
class AppSecondary {
  AppSecondary._();
  static const Color softGold = Color(0xFFFFEAA7); // 浅金
  static const Color lightTeal = Color(0xFFA7F3E0); // 浅青
  static const Color cream = Color(0xFFF5F1E8); // 米白
}

/// 中性灰阶
class AppGray {
  AppGray._();
  static const Color g50 = Color(0xFFFAFAFA);
  static const Color g100 = Color(0xFFF4F4F5);
  static const Color g200 = Color(0xFFE4E4E7);
  static const Color g400 = Color(0xFFA1A1AA);
  static const Color g600 = Color(0xFF52525B);
  static const Color g900 = Color(0xFF18181B);
}

/// 状态色
class AppStatus {
  AppStatus._();
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);
}

/// 记账语义色 —— 业务层用
class AppSemantic {
  AppSemantic._();

  /// 收入 / 正向金额 —— 绿
  ///
  /// 2026-10-20 D64.75 改:AppBrand.gold(金黄) → AppBrand.teal(#14B8A6)
  ///   - user 要求:"小结这里是要绿色为正,红色为负"
  ///   - 改之前收入色走 theme.colorScheme.secondary —— 默认主题是金黄,
  ///     切粉红主题 secondary 变 AppPinkBrand.gold(#FF5C8A 亮粉),
  ///     亮粉跟支出红(#EF4444)在粉底上几乎分不开 → 视觉上"正负都是红"
  ///   - 现在语义色**恒定**,不跟 palette / colorScheme 走:
  ///     任何主题(默认浅/深/粉浅/粉深)下正负都是绿 / 红
  ///   - 与 TxDisplayStyle.income.color(AppBrand.teal)同一套语言
  static const Color income = AppBrand.teal;
  static const Color expense = AppStatus.error; // 支出 / 负向金额 → 红(警示,刺眼)
  static const Color overBudget = AppStatus.error; // 超支 → 红
  // commit 100 加:深红,用于"超额"段(区别于"已花"的 error 红)
  //   已花 = error 红(#EF4444),超额 = overBudgetDeep(#B91C1C,更深更暗)
  //   已花转 1 圈 + 超额继续转 N 圈时,颜色深度递进,警示感更强
  static const Color overBudgetDeep = Color(0xFFB91C1C);
  // commit 103 加:4 阶超额色阶(配合 _overColorForTurn)
  //   - overBudgetDarker   #7F1D1D → 超额 200-300%(第 2 圈)
  //   - overBudgetDarkest  #450A0A → 超额 300%+(第 3 圈及以后)
  //   解决超额 2-3 倍时圆环颜色糊成一片的问题——每多 1 圈颜色加深一阶
  static const Color overBudgetDarker = Color(0xFF7F1D1D);
  static const Color overBudgetDarkest = Color(0xFF450A0A);

  /// 结余按值动态选色(2026-10-11 UAT 要求"正数绿、负数红"):
  ///   v > 0   → teal #14B8A6   (品牌青 = 设计稿"绿",hue 174° 偏 green)
  ///   v < 0   → error #EF4444  (与支出红同系,警示一致性)
  ///   v == 0  → cream #F5F1E8  (中性,在 ink 背景上仍可读,无正/负信号)
  ///
  /// 2026-10-20 D64.75:正/负两档复用 income / expense 常量,单一数据源。
  ///
  /// 不用 const const Color —— 值由 runtime 决定;业务层直接调
  /// `AppSemantic.balanceFor(value)`,不要硬编码 AppBrand.teal/AppStatus.error
  /// 否则未来色板微调时还得改多处。
  static Color balanceFor(double v) {
    if (v > 0) return income;
    if (v < 0) return expense;
    return AppSecondary.cream;
  }
}

/// 分类语义色 —— 用于报表圆环 / 图例 / 流水列表图标背景的"分类"维度区分
/// 不与 AppSemantic.expense / income 冲突(那是文字色,这里是分类色)
/// 命名按"业务领域"而非"颜色",避免一处改名到处跟改
/// 调色板参照支付宝记账本 + 微信记账本的分类习惯
class AppCategory {
  AppCategory._();
  // === 支出 11 类(自定义 / 其他用中性灰) ===
  static const Color food = AppStatus.warning; // 餐饮 — 橙
  static const Color transport = AppStatus.info; // 交通 — 蓝
  static const Color shopping = Color(0xFFEC4899); // 购物 — 粉
  static const Color housing = Color(0xFF92400E); // 居住 — 棕
  static const Color telecom = Color(0xFF06B6D4); // 通讯 — 青
  static const Color medical = AppStatus.error; // 医疗 — 红(警示,和支出文字色同系但允许)
  static const Color education = Color(0xFF8B5CF6); // 教育 — 紫
  static const Color entertainment = AppStatus.success; // 娱乐 — 绿
  static const Color home = Color(0xFFD97706); // 居家 — 棕橙
  static const Color beauty = Color(0xFFF43F5E); // 美妆 — 玫红
  static const Color pet = Color(0xFFFB923C); // 宠物 — 浅橙

  // === 收入 4 类(退款用中性灰) ===
  static const Color salary = AppBrand.gold; // 工资 — 金(主收入)
  static const Color bonus = Color(0xFFFFC107); // 奖金 — 亮金
  static const Color invest = AppStatus.success; // 理财 — 绿(收益)
  static const Color parttime = Color(0xFFA855F7); // 兼职 — 紫
  // 2026-10-14 加:福利分类色,跟 AppSegment.benefit 同值(流水 tile cat icon chip
  //   跟 account 段色一致视觉)。不复用 shopping(同 #EC4899):"福利" vs "购物"
  //   是不同财务概念,语义独立。user 拍板用 #EC4899,后续不喜欢可以再 fix。
  static const Color benefit = Color(0xFFEC4899); // 福利 — 粉
  // 2026-10-14 加:债权段 1 cat(负债)内置色
  //   - user 提议:期权直接去掉(归到投资段),负债借贷改名为"负债"统称
  //   - receivable 段下只剩 1 cat,跟投资/福利同 pattern:UI 隐藏,自动 fallback
  //   - 红(警示我需还金额)跟 D16 支出红同系,语义一致
  static const Color liability = Color(0xFFEF4444); // 负债 — 红(警示)
  // 2026-10-14 D57 加:其它 1 cat(其它)内置色,跟 AppSegment.other 同值(灰)
  //   - 其它段跟福利/债权同 pattern:UI 隐藏 cat,DB NOT NULL 通过内置 cat 兜底
  static const Color other = Color(0xFF71717A); // 其它 — 灰(跟 AppSegment.other 一致)

  // === 中性 ===
  static const Color neutral = AppGray.g400; // 其他 / 退款

  /// 自定义分类调色板 —— Python 导入脚本按 name hash 在这里分散取色
  /// 不要把分类专属色(food/transport/...)放进来,只放"通用色",
  /// 保证预置 12 类在报表里仍独占语义色
  static const List<int> hashPalette = [
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
  ];
}

/// 2026-10-14 P18 加:资产 6 段统一色 token
///   - 替代散落在 asset_summary_card / asset_tile / transaction_tile 的重复 switch
///   - 流水页资产 chip + 金额统一用段色,跨页视觉一致
///   - 颜色拉大色相距离,避免 cash_flow teal / investment gold / benefit 绿 撞色
///   - user 反馈:6 段颜色不够明显,流水颜色不跟资产大类一致
class AppSegment {
  AppSegment._();
  static const Color cashFlow = Color(0xFF0EA5E9); // 流动资金 — 亮蓝
  static const Color investment = Color(0xFFA855F7); // 投资 — 紫
  static const Color benefit = Color(0xFFEC4899); // 福利 — 粉
  static const Color receivable = Color(0xFFF59E0B); // 负债(原"债权/借出")— 橙
  static const Color fixedAsset = Color(0xFF06B6D4); // 不动产 — 青
  static const Color other = Color(0xFF71717A); // 其它 — 灰

  /// asset.type → 段色统一查询
  ///   - 'cash_flow' / 'investment' / 'benefit' / 'receivable' / 'fixed_asset' / 'other'
  ///   - 未知 type 兜底 other 灰
  static Color colorFor(String type) {
    switch (type) {
      case 'cash_flow':
        return cashFlow;
      case 'investment':
        return investment;
      case 'benefit':
        return benefit;
      case 'receivable':
        return receivable;
      case 'fixed_asset':
        return fixedAsset;
      default:
        return other;
    }
  }

  /// 2026-10-14 加:asset.type → 中文 label 集中数据源
  ///   - 之前散落在 assets_overview_chart / asset_summary_card / asset_form_page
  ///     各自硬编码 '现金流' / '投资' / '负债' / ...
  ///   - 统一走 AppSegment.labelFor,user 改 label 只改一处
  ///   - 2026-10-14 D51 v2:user 反馈'receivable 段 label 改"债务",语义更准
  ///     "负债"是会计负债(legal accounting),用户口语"债务"更直观
  ///   - 跟 "会计/记账 app 词汇:债权/期权/负债借贷统一叫'负债'" 偏好 supersede:
  ///     "负债"内部技术命名 OK,UI label 改 "债务" 更自然
  ///   - 2026-10-16 D64.40:user 反馈"现金流叫法不太合理",6 段第 1 段从"现金流"
  ///     改为"流动资金"。"现金流"是会计现金流量表用语,易跟"收支流水"混淆;
  ///     "流动资金"指"可即时动用的钱"(银行卡/钱包/现金),语义更直接
  ///   - DB enum 仍是 'cash_flow'(技术稳定),仅 UI label 改"流动资金"
  static String labelFor(String type) {
    switch (type) {
      case 'cash_flow':
        return '流动资金'; // D64.40:从"现金流"改"流动资金"
      case 'investment':
        return '投资';
      case 'benefit':
        return '福利';
      case 'receivable':
        return '债务'; // D51 v2:从 "负债" 改 "债务",user 反馈更直观
      case 'fixed_asset':
        return '不动产';
      default:
        // 2026-10-22 D64.95 改:'其它' → '其它资产'
        //   - user 拍板:第 6 段(asset.type='other')的 label 跟它的隐藏分类同名,口径统一
        //   - 之前叫「其它」,跟分类里的「其它支出」/用户自建的「其它」混在一起分不清
        //   - 未知 type 也走这个兜底,显示「其它资产」同样能表达"兜底段"
        return '其它资产';
    }
  }

  /// 2026-10-14 加:asset.type → icon 集中数据源
  ///   - 跟 labelFor 同源,3 个 widget(报表 / 资产页 / 新增账户)都用
  ///   - 未知 type 兜底 Icons.category_rounded(同 other 段,避免不一致)
  static const _iconCashFlow = Icons.account_balance_wallet_rounded;
  static const _iconInvestment = Icons.trending_up_rounded;
  static const _iconBenefit = Icons.favorite_rounded;
  static const _iconReceivable = Icons.handshake_rounded;
  static const _iconFixedAsset = Icons.home_rounded;
  static const _iconOther = Icons.category_rounded;

  static IconData iconFor(String type) {
    switch (type) {
      case 'cash_flow':
        return _iconCashFlow;
      case 'investment':
        return _iconInvestment;
      case 'benefit':
        return _iconBenefit;
      case 'receivable':
        return _iconReceivable;
      case 'fixed_asset':
        return _iconFixedAsset;
      default:
        return _iconOther;
    }
  }
}
