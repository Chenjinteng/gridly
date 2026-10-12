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

import '../database/providers.dart';

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

/// 资产负债总览(给 P3 资产负债页用,P1 暂未引用)
///   totalCashFlow = sum(所有 cash_flow 账户 currentBalance)
///   P3 会再扩展:加 fixed_asset / liability 维度,这里先占位。
class AssetTotals {
  const AssetTotals({required this.totalCashFlow});
  final double totalCashFlow;
}

final assetTotalsProvider = FutureProvider<AssetTotals>((ref) async {
  final repo = ref.watch(assetRepositoryProvider);
  final assets = await repo.all();
  final balances = await ref.watch(assetBalancesProvider.future);
  var totalCashFlow = 0.0;
  for (final a in assets) {
    if (a.type == 'cash_flow') {
      totalCashFlow += balances[a.id] ?? 0.0;
    }
  }
  return AssetTotals(totalCashFlow: totalCashFlow);
});
