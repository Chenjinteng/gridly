// lib/features/add/ui/widgets/numpad.dart
// 5x4 计算器键盘 —— 5 行固定高(SizedBox),外层不再依赖 Expanded 给高
//   C  ⌫  %   ÷
//   7  8  9   ×
//   4  5  6   -
//   1  2  3   +
//   0  .  00  =
//
// 2026-10-11 改本征高:之前每行用 Expanded,在父级被 keyboards 推挤时会均分
// 剩余空间,4 行只剩 1 行可见,后面 3 行被键盘覆盖。改 SizedBox(height:56)
// 后 Numpad 总高 280px,不被压缩,transaction_form 的表单上半部
// 改用 Expanded(SingleChildScrollView) 来让键盘弹出时滚动给备注。
//
// 2026-10-12 Tactile Spring 按压:每个键改 _NumpadKey 单独处理 onTapDown/Up
//   - 按下:80ms easeOut 缩到 0.96
//   - 松手:SpringSimulation(stiffness 380 / damping 18)弹回,有 ~10% overshoot
//   - 不再走 InkWell(ripple 在 ColorOS 风里太"轻",用 scale 单一反馈更克制)
//   - 双重反馈(颜色变深)留给 Phase 2 的 indicator / chip 选中等场景
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/motion/app_motion.dart';
import '../../../../core/haptics/app_haptics.dart';

class Numpad extends StatelessWidget {
  const Numpad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  /// 单行高度。5 × 56 = 280px,典型 4 列 5 行计算器键位;
  /// 太矮(40-50)易误触,太高(70+)挤掉备注/分类显示区
  static const double _rowHeight = 56;

  static const _keys = [
    ['C', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '00', '='],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _keys.map((row) {
        return SizedBox(
          height: _rowHeight,
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: _NumpadKey(
                  label: k,
                  color: _keyColor(context, k),
                  isNumber: _isNumber(k),
                  onTap: () => onKey(k),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  bool _isNumber(String k) {
    if (k.length == 1 && '0123456789.'.contains(k)) return true;
    return k == '00';
  }

  Color _keyColor(BuildContext context, String k) {
    if (k == 'C') return AppStatus.error;
    if ('+-×÷%='.contains(k)) return AppBrand.teal;
    return Theme.of(context).colorScheme.onSurface;
  }
}

/// 单个数字/操作键 —— 弹簧按压 ColorOS Tactile Spring
///
/// 按下:80ms easeOut 缩到 AppMotion.pressedScale(0.96)
/// 松手/Cancel:SpringSimulation 弹回,stiffness 380 / damping 18,
///   ~10% overshoot —— ColorOS"重量感"标志
class _NumpadKey extends StatefulWidget {
  const _NumpadKey({
    required this.label,
    required this.color,
    required this.isNumber,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool isNumber;
  final VoidCallback onTap;

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    // 上界 1(松开态)、下界 pressedScale(按下态)。
    // animateTo 会自动 clamp 到这个区间。
    value: 1.0,
    lowerBound: AppMotion.pressedScale,
    upperBound: 1.0,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    _press.stop();
    // 按下:80ms easeOut 滑到 0.96 —— 不要用 spring(按下要"硬"且即时,
    // spring 反而显得"软";弹回才需要 spring)。
    _press.animateTo(
      AppMotion.pressedScale,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOut,
    );
    // 2026-10-12 ColorOS Tactile Haptics:按下立刻给触觉反馈
    //   - C:warning(清空是个"破坏性"操作,需要重一点)
    //   - =:success(等号是"计算完成"的肯定)
    //   - 其他:lightImpact(数字键 / 运算符标准触感)
    final label = widget.label;
    if (label == 'C') {
      AppHaptics.warning();
    } else if (label == '=') {
      AppHaptics.success();
    } else {
      AppHaptics.tap();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    _springBack();
    widget.onTap();
  }

  void _handleTapCancel() {
    // 滑出 / 被打断:不触发 onTap,直接弹回
    _springBack();
  }

  void _springBack() {
    _press.stop();
    // ColorOS Tactile Spring 弹回:SpringSimulation 从当前 value 弹到 1,
    // 给个初始 velocity(3)让 overshoot 更明显。stiffness 380 / damping 18
    // 临界欠阻尼 ~10% overshoot,有"按了之后微微弹过头再回来"的橡胶感。
    final spring = SpringDescription(
      mass: 1.0,
      stiffness: AppMotion.pressSpringStiffness,
      damping: AppMotion.pressSpringDamping,
    );
    final simulation =
        SpringSimulation(spring, _press.value, 1.0, 3.0);
    _press.animateWith(simulation);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          return Transform.scale(
            scale: _press.value,
            child: child,
          );
        },
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.isNumber ? 22 : 20,
              fontWeight:
                  widget.isNumber ? FontWeight.w500 : FontWeight.w600,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}