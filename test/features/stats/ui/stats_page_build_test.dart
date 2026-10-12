// 临时验证:StatsPage build 不再抛 infinite height 异常
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/core/database/app_database.dart';
import 'package:gridly/core/database/providers.dart';
import 'package:gridly/features/stats/ui/stats_page.dart';

void main() {
  testWidgets('stats page builds without infinite height exception', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith(
            (ref) => AppDatabase(),
          ),
        ],
        child: const MaterialApp(
          home: StatsPage(),
        ),
      ),
    );
    // pump 几帧触发 build + postFrame callback
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 不能断言 null,因为 AnimatedCounter 持续动画有 timer pending
    // 只断言没 "BoxConstraints forces infinite height" 异常
    final ex = tester.takeException();
    expect(ex, isNull, reason: '修复前会抛 BoxConstraints forces infinite height');
  });
}
