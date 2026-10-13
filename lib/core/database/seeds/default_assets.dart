// lib/core/database/seeds/default_assets.dart
// 资产/账户预置数据(2026-10-12 P1 加,commit 110)
//
// 3 个 cash_flow 类账户作为兜底,user 首次启动时自动 seed:
//   - 现金     → 默认 / 兜底账户,老数据迁移时 NULL accountId 全指向这
//   - 银行卡   → 常见兜底
//   - 微信支付 → 第三方支付常见兜底
//
// type / color / icon 设计理由:
//   - 全部 cash_flow:user 99% 场景
//   - 现金 → gold(金 = 流通感),银行卡 / 微信 → teal(品牌色)
//   - 现金 icon = 'payments' (Material Icons 直对应付款),其余用 'credit_card' / 'account_balance_wallet'
//
// 2026-10-13 P7:加 isDefault 字段(cash_flow 段"日常流水默认账户"标记)
//   - 现金作为 displayOrder 0 同时默认 isDefault=true
//   - 银行卡 / 微信 isDefault=false(user 主动在资产列表"设为默认"时可换主)
class DefaultAsset {
  const DefaultAsset({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.displayOrder,
    this.isDefault = false,
  });

  final String name;
  final String type;
  final String icon;
  final int color;
  final int displayOrder;
  // 2026-10-13 P7:现金段"日常流水默认账户",记一笔时优先选
  final bool isDefault;
}

class DefaultAssets {
  DefaultAssets._();

  static const List<DefaultAsset> all = [
    DefaultAsset(
      name: '现金',
      type: 'cash_flow',
      icon: 'payments',
      color: 0xFFF5BC1F, // AppBrand.gold — 流通感
      displayOrder: 0,
      // 2026-10-13 P7:作为 cash_flow 段默认账户,记一笔优先命中
      isDefault: true,
    ),
    DefaultAsset(
      name: '银行卡',
      type: 'cash_flow',
      icon: 'credit_card',
      color: 0xFF14B8A6, // AppBrand.teal
      displayOrder: 1,
    ),
    DefaultAsset(
      name: '微信支付',
      type: 'cash_flow',
      icon: 'account_balance_wallet',
      color: 0xFF14B8A6, // AppBrand.teal
      displayOrder: 2,
    ),
  ];
}
