// lib/shared/constants/default_categories.dart
// 默认分类:支出 12 类 + 收入 5 类
// 配色:v3 起每个分类独占语义色(支付宝记账本风格),
// 用于报表圆环 / 图例 / 流水图标背景的"分类维度"区分
//   - 支出 → 11 类各色 + 其他用灰
//   - 收入 → 4 类各色 + 退款用灰
// 所有色都集中定义在 AppCategory(见 app_colors.dart),不在本文件硬编码
import 'package:gridly/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

class DefaultCategory {
  const DefaultCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
    required this.sortOrder,
  });
  final String name;
  final String icon; // icon key,对应 CategoryIcons.map
  final Color color;
  final String type; // 'expense' | 'income'
  final int sortOrder;
}

/// 分类图标库 —— key → IconData
/// v2 起每个分类都用语义化图标(餐饮 → 餐具,交通 → 公交...),
/// 一眼能看出区别。v1 的 7 个几何图标保留作为老数据 fallback。
/// v3 起扩充 ~30 个图标供自定义分类挑选,覆盖常见消费场景。
class CategoryIcons {
  CategoryIcons._();
  static const Map<String, IconData> map = {
    // === v2 语义化图标(rounded,Material 3 推荐) ===
    // 支出
    'restaurant': Icons.restaurant_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'home': Icons.home_rounded,
    'phone_iphone': Icons.phone_iphone_rounded,
    'medical_services': Icons.medical_services_rounded,
    'school': Icons.school_rounded,
    'movie': Icons.movie_rounded,
    'chair': Icons.chair_rounded,
    'spa': Icons.spa_rounded,
    'pets': Icons.pets_rounded,
    'more_horiz': Icons.more_horiz_rounded,
    // 收入
    'payments': Icons.payments_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'savings': Icons.savings_rounded,
    'work': Icons.work_rounded,
    'replay': Icons.replay_rounded,

    // === v3 扩充图标(自定义分类可选) ===
    // 餐饮
    'local_cafe': Icons.local_cafe_rounded,
    'cake': Icons.cake_rounded,
    'local_dining': Icons.local_dining_rounded,
    'local_bar': Icons.local_bar_rounded,
    // 交通
    'directions_car': Icons.directions_car_rounded,
    'local_taxi': Icons.local_taxi_rounded,
    'flight': Icons.flight_rounded,
    'directions_bike': Icons.directions_bike_rounded,
    // 购物
    'shopping_cart': Icons.shopping_cart_rounded,
    'redeem': Icons.redeem_rounded,
    // 居住 / 居家
    'bed': Icons.bed_rounded,
    'kitchen': Icons.kitchen_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    // 通讯 / 数码
    'wifi': Icons.wifi_rounded,
    'devices': Icons.devices_rounded,
    'laptop_mac': Icons.laptop_mac_rounded,
    // 医疗
    'local_pharmacy': Icons.local_pharmacy_rounded,
    'monitor_heart': Icons.monitor_heart_rounded,
    // 教育
    'menu_book': Icons.menu_book_rounded,
    'auto_stories': Icons.auto_stories_rounded,
    // 娱乐
    'music_note': Icons.music_note_rounded,
    'videogame_asset': Icons.videogame_asset_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'headphones': Icons.headphones_rounded,
    // 美妆
    'face': Icons.face_rounded,
    'content_cut': Icons.content_cut_rounded,
    // 福利(2026-10-14 加)
    'favorite': Icons.favorite_rounded,
    // 债权段 1 cat(2026-10-14 加):负债
    'request_quote': Icons.request_quote_rounded, // 负债 — 凭证 / 单据
    // 健身 / 旅行 / 礼物
    'fitness_center': Icons.fitness_center_rounded,
    'hotel': Icons.hotel_rounded,
    'luggage': Icons.luggage_rounded,
    // 收入补充
    'trending_up': Icons.trending_up_rounded,
    // 2026-10-20 D64.77 加:投资亏损(收益为负时用)
    'trending_down': Icons.trending_down_rounded,
    'account_balance_wallet': Icons.account_balance_wallet_rounded,
    'emoji_events': Icons.emoji_events_rounded,

    // === v1 几何图标(老数据 fallback,不再用于系统分类) ===
    'circle': Icons.circle_rounded,
    'square': Icons.square_rounded,
    'triangle': Icons.change_history_rounded,
    'diamond': Icons.diamond_rounded,
    'star': Icons.star_rounded,
    'hexagon': Icons.hexagon_rounded,
    'pentagon': Icons.pentagon_rounded,
    'category': Icons.category_rounded,
  };
}

class DefaultCategories {
  DefaultCategories._();

  /// 支出 12 类 —— 每个分类一个独特图标 + 一个独特颜色
  static const List<DefaultCategory> expense = [
    DefaultCategory(
      name: '餐饮',
      icon: 'restaurant',
      color: AppCategory.food,
      type: 'expense',
      sortOrder: 0,
    ),
    DefaultCategory(
      name: '交通',
      icon: 'directions_bus',
      color: AppCategory.transport,
      type: 'expense',
      sortOrder: 1,
    ),
    DefaultCategory(
      name: '购物',
      icon: 'shopping_bag',
      color: AppCategory.shopping,
      type: 'expense',
      sortOrder: 2,
    ),
    DefaultCategory(
      name: '居住',
      icon: 'home',
      color: AppCategory.housing,
      type: 'expense',
      sortOrder: 3,
    ),
    DefaultCategory(
      name: '通讯',
      icon: 'phone_iphone',
      color: AppCategory.telecom,
      type: 'expense',
      sortOrder: 4,
    ),
    DefaultCategory(
      name: '医疗',
      icon: 'medical_services',
      color: AppCategory.medical,
      type: 'expense',
      sortOrder: 5,
    ),
    DefaultCategory(
      name: '教育',
      icon: 'school',
      color: AppCategory.education,
      type: 'expense',
      sortOrder: 6,
    ),
    DefaultCategory(
      name: '娱乐',
      icon: 'movie',
      color: AppCategory.entertainment,
      type: 'expense',
      sortOrder: 7,
    ),
    DefaultCategory(
      name: '居家',
      icon: 'chair',
      color: AppCategory.home,
      type: 'expense',
      sortOrder: 8,
    ),
    DefaultCategory(
      name: '美妆',
      icon: 'spa',
      color: AppCategory.beauty,
      type: 'expense',
      sortOrder: 9,
    ),
    DefaultCategory(
      name: '宠物',
      icon: 'pets',
      color: AppCategory.pet,
      type: 'expense',
      sortOrder: 10,
    ),
    DefaultCategory(
      name: '其他',
      icon: 'more_horiz',
      color: AppCategory.neutral,
      type: 'expense',
      sortOrder: 99,
    ),
  ];

  /// 收入 5 类 —— 每个分类一个独特图标 + 一个独特颜色
  static const List<DefaultCategory> income = [
    DefaultCategory(
      name: '工资',
      icon: 'payments',
      color: AppCategory.salary,
      type: 'income',
      sortOrder: 0,
    ),
    DefaultCategory(
      name: '奖金',
      icon: 'card_giftcard',
      color: AppCategory.bonus,
      type: 'income',
      sortOrder: 1,
    ),
    DefaultCategory(
      name: '理财',
      icon: 'savings',
      color: AppCategory.invest,
      type: 'income',
      sortOrder: 2,
    ),
    DefaultCategory(
      name: '兼职',
      icon: 'work',
      color: AppCategory.parttime,
      type: 'income',
      sortOrder: 3,
    ),
    DefaultCategory(
      name: '退款',
      icon: 'replay',
      color: AppCategory.neutral,
      type: 'income',
      sortOrder: 99,
    ),
  ];

  /// 投资 2 类 —— 2026-10-14 P18 大改加:
  ///   - '投资投入':投入(_intent='input')和调拨(_intent='transfer')用,语义:cash → investment
  ///   - '投资收益':收益(_intent='output')用,语义:investment 账户自身增长
  ///   - UI 隐藏:TransactionForm 在 investment context 不显示分类选择器
  ///     (user 看不到这两个分类,也选不到),seed 出来只是为了填 DB NOT NULL 字段
  ///   - ledger 默认隐藏(ledger_page filter 黑名单),投资 record 不混入 cash_flow 流水
  static const List<DefaultCategory> investment = [
    DefaultCategory(
      name: '投资投入',
      icon: 'savings',
      color: AppCategory.invest,
      type: 'investment',
      sortOrder: 0,
    ),
    DefaultCategory(
      name: '投资收益',
      icon: 'trending_up',
      color: AppCategory.invest,
      type: 'investment',
      sortOrder: 1,
    ),
    // 2026-10-20 D64.77 加:投资亏损(收益为负时用)
    //   - 场景:基金/股票跌了,用户要记一笔负收益。DB 存 type='income' +
    //     amount = -184.88(余额公式 +Σ → 账户余额减少,数学正确)
    //   - 单独一个 cat 而不是复用'投资收益':流水列表 label 显示 cat.name,
    //     显示"投资亏损 - ¥184.88"比"投资收益 - ¥184.88"清楚得多
    //   - cat.type 仍是 'investment' → 不进月度收支 / 报表收支口径,
    //     也不进分类管理页(该页只列 expense / income 两类)
    DefaultCategory(
      name: '投资亏损',
      icon: 'trending_down',
      color: AppStatus.error,
      type: 'investment',
      sortOrder: 2,
    ),
  ];

  /// 福利 1 类 —— 2026-10-14 加:
  ///   - '福利':福利段账户(_type='benefit')的支出/收入都用同一个分类
  ///   - UI 隐藏:TransactionForm 在 benefit context 不显示分类选择器,
  ///     seed 出来只填 DB NOT NULL 字段(cat.type='benefit')
  ///   - 跟 investment 同结构:UI 隐藏 + DB 必填,所以统一 fallback
  ///   - 后续要细分福利支出/收入可改 2 类(福利支出 / 福利收入),同结构扩展
  static const List<DefaultCategory> benefit = [
    DefaultCategory(
      name: '福利',
      icon: 'favorite',
      color: AppCategory.benefit,
      type: 'benefit',
      sortOrder: 0,
    ),
  ];

  /// 债权段 1 类 —— 2026-10-14 改:
  ///   - '债务':跟 receivable 段账户对账,记录我需还的借款 / 债务(D51 v2 从"负债"改"债务")
  ///   - 2026-10-14 简化前是 2 类(股份期权 / 负债借贷,user 主动在 2 里选区分)
  ///   - 2026-10-14 简化后:user 反馈"期权直接去掉,放到投资中",只剩 1 个"债务" cat
  ///   - 跟福利同 pattern:UI 隐藏,自动 fallback(cat.type='liability' 唯一)
  ///   - DB schema 不动:cat.type 是 String,'liability' 新值不需 migration
  static const List<DefaultCategory> receivable = [
    DefaultCategory(
      name: '债务', // D51 v2:从"负债"改"债务",口语更直观
      icon: 'request_quote',
      color: AppCategory.liability,
      type: 'liability',
      sortOrder: 0,
    ),
  ];

  /// 其它段 1 类 —— 2026-10-14 D57 加:
  ///   - '其它':其它段账户(asset.type='other')的支出/收入都用同一个分类
  ///   - UI 隐藏:TransactionForm 在 other context 不显示分类选择器,
  ///     seed 出来只填 DB NOT NULL 字段(cat.type='other')
  ///   - 跟 investment/benefit/receivable 同 pattern:UI 隐藏 + DB 必填,所以统一 fallback
  ///   - DB schema 不动:cat.type 是 String,'other' 新值不需 migration
  static const List<DefaultCategory> other = [
    DefaultCategory(
      name: '其它',
      icon: 'category', // 复用 v1 几何 icons 里 'category'(label icon 语义)
      color: AppCategory.other,
      type: 'other',
      sortOrder: 0,
    ),
  ];

  /// 余额调整 1 类 —— 2026-10-19 D72 加:
  ///   - '余额调整':资产 form 编辑"期初余额"时,如果用户输入 ≠ 当前 currentBalance,
  ///     自动生成一笔 type='balance' 流水(amount = oldCurrent - newInit)抹平差值,
  ///     让 newCurrent = newInit。这种流水不算月度收支,但参与资产 currentBalance 计算。
  ///   - UI 隐藏(TransactionForm 不显示这个 cat),跟 investment/benefit/receivable/other
  ///     同 pattern —— 自动 fallback 给 asset_form_page 调用
  ///   - cat.type 跟 cat 物理表的 enum 兼容(schema 不需 migration,纯字符串)
  ///   - 跟其它段的 cat(其它/福利/债务/投资)一样,DB NOT NULL 字段需要填
  static const List<DefaultCategory> balanceAdjust = [
    DefaultCategory(
      name: '余额调整',
      icon: 'tune', // tune 图标(微调 / 调音)语义最贴
      color: AppCategory.other, // 复用其它段灰色,跟其它"系统隐藏 cat"一致
      type: 'adjust',
      sortOrder: 0,
    ),
  ];
}

/// v1 → v2 图标 key 迁移表,按 name 匹配老数据。
/// 老用户数据库里的系统分类可能是 v1 几何 key,这里按名字映射升级。
const Map<String, String> kIconMigrationV2 = {
  '餐饮': 'restaurant',
  '交通': 'directions_bus',
  '购物': 'shopping_bag',
  '居住': 'home',
  '通讯': 'phone_iphone',
  '医疗': 'medical_services',
  '教育': 'school',
  '娱乐': 'movie',
  '居家': 'chair',
  '美妆': 'spa',
  '宠物': 'pets',
  '其他': 'more_horiz',
  '工资': 'payments',
  '奖金': 'card_giftcard',
  '理财': 'savings',
  '兼职': 'work',
  '退款': 'replay',
};
