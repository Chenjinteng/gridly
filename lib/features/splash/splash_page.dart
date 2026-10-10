// lib/features/splash/splash_page.dart
// 启动屏:GridlyMark(LOGO mark)+ App 名 + Tagline + 三色横条
// LOGO 实现统一在 core/widgets/gridly_mark.dart,严格按 design/THEME.html .logo3
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/gridly_mark.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppBrand.ink,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // 统一 LOGO mark:2×2 + -8° + 6.67% gap + 16.67% 圆角
            // onDark=true:ink 块在深底上变 cream,避免融背景
            const GridlyMark(size: 120, onDark: true),
            const SizedBox(height: AppSpacing.s6),
            const Text(
              '格子记账',
              style: TextStyle(
                color: AppSecondary.cream,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            const Text(
              '一格一账',
              style: TextStyle(
                color: AppGray.g400,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            // 三色横条(经典 gridly 标志)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.s8),
              child: Row(
                children: [
                  Expanded(child: _Bar(color: AppBrand.ink, height: 4)),
                  SizedBox(width: 2),
                  Expanded(child: _Bar(color: AppBrand.gold, height: 4)),
                  SizedBox(width: 2),
                  Expanded(child: _Bar(color: AppBrand.teal, height: 4)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.height});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
