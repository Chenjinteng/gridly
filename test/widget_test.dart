// P0 阶段的占位测试。P1+ 用真实 widget test 覆盖。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gridly/app.dart';

void main() {
  testWidgets('App boots and shows splash', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: LedgerlyApp()),
    );
    await tester.pump();
    // 启动屏第一个可见文字是 brand 名
    expect(find.text('格子记账'), findsOneWidget);
  });
}
