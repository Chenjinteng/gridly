// lib/core/utils/asset_balance_provider.dart
// 资产实时余额 Provider —— 组合 Assets.initialBalance + 流水净增量,实时算 currentBalance
//
// 2026-10-12 commit 110 加(P1 资产层):
//   - assets 表 initialBalance 持久化
//   - 流水净增量由 AssetRepository.balanceDeltaByAssetId() 提供:
//       delta = -sum(expense) + sum(income) + sum(balance,可正可负)
//   - currentBalance = initialBalance + delta
//
// P1 阶段用途:暂未上 UI,先建好数据层等 P2 资产页面用。
//   调用方只需 watch assetBalancesProvider,得到 Map<assetId, currentBalance>。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/providers.dart';

/// 2026-10-12 P2 commit 加:所有资产列表(按 displayOrder 升序)
///   AssetsManagementPage / AssetSummaryCard 用。
///   跟 AssetRepository.all() 等价但作为 Provider 暴露便于 ref.watch。
final allAssetsProvider = FutureProvider<List<Asset>>((ref) async {
  final repo = ref.watch(assetRepositoryProvider);
  return repo.all();
});

/// 每个资产的实时余额(assetId → currentBalance)
/// 公式:currentBalance = asset.initialBalance + balanceDelta(assetId)
/// 没流水的账户(只在 delta map 里查不到)也返回,值为 initialBalance。
///
/// 实时性:流水变化后必须 invalidate 这个 provider 才刷新。
/// 已加到 refresh_providers.dart 的 refreshAllData() 里,
/// 保存一笔 / 删一笔 / 编辑一笔都会同步刷新余额。
final assetBalancesProvider = FutureProvider<Map<int, double>>((ref) async {
  final repo = ref.watch(assetRepositoryProvider);
  final assets = await repo.all();
  final deltas = await repo.balanceDeltaByAssetId();
  final out = <int, double>{};
  for (final a in assets) {
    final delta = deltas[a.id] ?? 0.0;
    out[a.id] = a.initialBalance + delta;
  }
  return out;
});

/// 单个资产的实时余额(家族化:用 assetId 查)
/// 供资产列表 item / 详情页等"只关心一个账户"的 UI 用,避免 watch 整张表。
final assetBalanceProvider = FutureProvider.family<double, int>((
  ref,
  assetId,
) async {
  final balances = await ref.watch(assetBalancesProvider.future);
  return balances[assetId] ?? 0.0;
});

/// 2026-10-12 P4 commit 扩展:资产总览(给 P4 资产页雷达图 + 报表净资产卡用)
///   2026-10-16 D64.45:报表净资产卡移除,这里仍供 AssetsRadar 雷达 + 资产页 AssetSummaryCard 使用
///   - 2026-10-13 P6 扩到 6 段:总现金 / 总投资 / 总福利 / 总债权 / 总不动产 / 总其它
///   - 累加不取 abs(让 user 看到"实际欠多少/待收多少",正值/负值都反映)
///   - 雷达图单独取 abs 用以显示对比幅度
class AssetTotals {
  const AssetTotals({
    required this.totalCashFlow,
    required this.totalInvestment,
    required this.totalBenefit,
    required this.totalReceivable,
    required this.totalFixedAsset,
    required this.totalOther,
  });
  final double totalCashFlow;
  final double totalInvestment;
  final double totalBenefit;
  final double totalReceivable;
  final double totalFixedAsset;
  final double totalOther;
}

final assetTotalsProvider = FutureProvider<AssetTotals>((ref) async {
  final repo = ref.watch(assetRepositoryProvider);
  final assets = await repo.all();
  final balances = await ref.watch(assetBalancesProvider.future);
  var cf = 0.0, inv = 0.0, ben = 0.0, rec = 0.0, fa = 0.0, ot = 0.0;
  for (final a in assets) {
    final bal = balances[a.id] ?? 0.0;
    switch (a.type) {
      case 'cash_flow':
        cf += bal;
        break;
      case 'investment':
        inv += bal;
        break;
      case 'benefit':
        ben += bal;
        break;
      case 'receivable':
        rec += bal;
        break;
      case 'fixed_asset':
        fa += bal;
        break;
      default:
        ot += bal;
    }
  }
  return AssetTotals(
    totalCashFlow: cf,
    totalInvestment: inv,
    totalBenefit: ben,
    totalReceivable: rec,
    totalFixedAsset: fa,
    totalOther: ot,
  );
});
