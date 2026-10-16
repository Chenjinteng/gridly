// lib/core/utils/open_swipe_id_provider.dart
//
// 2026-10-16 D64.42 加:跨 tile 类型的"当前打开的滑动 tile id"全局状态。
//   - 之前是 `openSwipeTileIdProvider` 定义在
//     lib/features/ledger/application/transactions_providers.dart,专给
//     流水 tile 滑动用 —— 但本质是通用机制,任何"左滑露操作按钮"的
//     tile(资产 / 流水 / 未来分类等)都用得上。
//   - 改名:`openSwipeTileIdProvider` → `openSwipeIdProvider`,
//     类型仍 `int?`(流水 / 资产 id 都是 int)
//   - 行为不变:某 tile 滑开时 set 为自己的 id,其他 tile 通过 ref.listen
//     检测到 provider 变化且自己不在开,自动 spring 收回;点屏幕任何地方
//     也能通过清 provider 触发收回(具体由 caller 在父级 GestureDetector
//     里 `ref.read(provider.notifier).state = null`)。
//   - 这里挪到 core/utils 是因为它跨 feature,跟 transaction / asset
//     业务无强耦合,只是 tile 滑动的全局协调机制。
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局状态:当前正在左滑展开操作按钮的 tile 的 id。
///
/// - `null` 表示没有 tile 展开(默认)
/// - `int` 是某个正在展开的 tile 的 id(transaction.id / asset.id)
///
/// 设计目的:保证同时只有一个 tile 开着(避免视觉混乱)。
/// 任何 tile 都可以 watch / read 这个 provider:
///   - 自己滑开 → set(myId)
///   - 别人滑开 / 点屏幕别处 → 通过 ref.listen 检测到 next != myId 时
///     自动 spring 回 0 收回(具体实现在 `SwipeToActions` widget)
final openSwipeIdProvider = StateProvider<int?>((ref) => null);
