// lib/features/splash/splash_page.dart
// 启动屏:LOGO 居中 + 三色横条 + Tagline
// 设计参考:design/THEME.md §6.1
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

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
            // 简化的 LOGO(用 Container 画三色方块,避免 P0 阶段 LOGO 图没到位)
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                children: [
                  Positioned(
                    top: 0, right: 0,
                    child: _Square(size: 80, color: AppBrand.gold),
                  ),
                  Positioned(
                    bottom: 0, left: 0,
                    child: _Square(size: 80, color: AppBrand.teal),
                  ),
                  Positioned(
                    top: 20, left: 0,
                    child: _Square(size: 80, color: AppSecondary.cream),
                  ),
                ],
              ),
            ),
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
            // 三色横条(THEME.md §6.1 启动屏规范)
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

class _Square extends StatelessWidget {
  const _Square({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.brXl,
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
