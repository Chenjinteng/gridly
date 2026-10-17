// lib/web/web_app.dart
// LAN_WEB v2.0.0 P3 web 端 app 壳 + home page
//
// P3 commit 2:占位 home page(显示"gridly web" + "已连接到 vX.Y.Z")
// P3 commit 3-7:会逐步加 log in / ledger list / add / stats / sessions
import 'package:flutter/material.dart';

import '../core/server/version.dart';

class GridlyWebApp extends StatelessWidget {
  const GridlyWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gridly · 局域网伴侣端',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6CFF), // 跟 mobile AppBrand primary 对齐
          brightness: Brightness.light,
        ),
      ),
      home: const _HomePage(),
    );
  }
}

/// P3 commit 2 占位 home page
/// P3 commit 3 会改成 log in 页(输 6 位码 → POST /api/auth/pair)
class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('gridly'),
        centerTitle: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.grid_view_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'gridly · 局域网伴侣端',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '已连接到 gridly web v$kGridlyWebVersion+$kGridlyWebBuild',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.construction_rounded,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'P3 commit 2 占位页',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('后续 commit 会逐步加:'),
                      const SizedBox(height: 4),
                      const Text('• P3 commit 3:log in 页(6 位配对码)'),
                      const Text('• P3 commit 4:流水列表 + 月度汇总卡片'),
                      const Text('• P3 commit 5:记一笔 modal'),
                      const Text('• P3 commit 6:已配对设备页'),
                      const Text('• P3 commit 7:docs + E2E'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
