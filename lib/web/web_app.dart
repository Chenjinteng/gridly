// lib/web/web_app.dart
// LAN_WEB v2.0.0 P3 web 端 app 壳 + 路由(log in ↔ ledger list)
//
// P3 commit 3:加 log in 页 + ledger list 占位页
// P3 commit 4-6:逐步加流水列表 / 月度汇总 / 记一笔 / 配对设备
import 'package:flutter/material.dart';

import '../core/server/version.dart';
import 'api_client.dart';
import 'ledger_list_page.dart';
import 'log_in_page.dart';

class GridlyWebApp extends StatefulWidget {
  const GridlyWebApp({super.key});

  @override
  State<GridlyWebApp> createState() => _GridlyWebAppState();
}

class _GridlyWebAppState extends State<GridlyWebApp> {
  // true = 已配对(显示 ledger list),false = 显示 log in
  bool _paired = false;
  final _api = WebApiClient();

  void _onPaired() => setState(() => _paired = true);
  void _onLoggedOut() => setState(() => _paired = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gridly · 局域网伴侣端 v$kGridlyWebVersion+$kGridlyWebBuild',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A6CFF), // 跟 mobile AppBrand primary 对齐
          brightness: Brightness.light,
        ),
      ),
      home: _paired
          ? LedgerListPage(api: _api, onLogout: _onLoggedOut)
          : LogInPage(api: _api, onSuccess: _onPaired),
    );
  }
}
