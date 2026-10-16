// lib/features/settings/data/backup_service.dart
// 2026-10-17 D68 加:数据库全量备份 / 还原服务
//
// 设计要点:
//   1. **备份格式:raw .sqlite 文件**(user 原话"全备")
//      - 走 SQLite `VACUUM INTO` 命令(原子、压实、自动 checkpoint WAL)
//      - 不走 sqlite3 .dump(SQL 文本)—— 那个文件大 5-10x、慢、不适合 >10k 笔
//   2. **备份位置**:temp 目录 + 时间戳命名 `gridly_backup_20261017_003600.sqlite`
//      - 走 share_plus 系统分享,user 自己存到任意位置(网盘/U盘/微信文件等)
//   3. **还原流程**:
//      a. file_picker 选 .sqlite 文件(Android 走 SAF,无 READ_EXTERNAL_STORAGE 权限需求)
//      b. 二次确认(user 选 D68: 弹 2 次 dialog 防止误操作)
//      c. db.close() —— 让 SQLite 释放文件锁,删除 .sqlite-wal/.sqlite-shm 临时文件
//      d. 复制选中的文件覆盖 gridly.sqlite
//      e. SystemNavigator.pop() —— 强制退出 app,user 手动重开读到新 db
//      (db 在线状态不能直接覆盖文件,必须先 close 再覆盖,再重启)
//
// 已知边界 / 后续可优化项:
//   - 备份跨 gridly 版本可能不兼容(forward 兼容 OK,backward 可能 schema 不匹配);
//     加版本号 header 字段可在还原时拒绝错误版本
//   - 不加密(本地工具,数据本身不上云,user 自己保管备份文件即可)
//   - 备份时 db 在写(用户在记一笔)不影响——VACUUM INTO 走 SQLite 内部快照
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/app_database.dart';

/// 数据库元信息(给 sheet UI 显示"当前位置 / 大小 / 修改时间")
class DbInfo {
  const DbInfo({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime? modifiedAt;
}

/// 2026-10-17 D68 加:备份 / 还原服务
///   - 通过 Riverpod Provider 注入(跟 csvExporterProvider 同 pattern)
///   - 还原方法 `restoreDbFromFile` 需要传入 [AppDatabase] 实例以调 close()
///   - 调完会调 SystemNavigator.pop() 退出 app(force exit 让 user 重开读到新 db)
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService();
});

class BackupService {
  /// 解析数据库文件路径
  ///   - 跟 lib/core/database/app_database.dart:152-153 的 _openConnection 同源
  ///   - 改路径要同步改 app_database.dart
  Future<File> _getDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'gridly.sqlite'));
  }

  /// 读 db 元信息(sheet UI 用)
  Future<DbInfo> getDbInfo() async {
    final file = await _getDbFile();
    if (!await file.exists()) {
      return const DbInfo(path: '', sizeBytes: 0, modifiedAt: null);
    }
    final stat = await file.stat();
    return DbInfo(
      path: file.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
    );
  }

  /// 备份数据库
  ///   - 走 SQLite `VACUUM INTO '<temp_path>'` —— 原子、压实、自动 checkpoint WAL
  ///   - 不走 file.copy(db) 那种简单复制:那样复制出来的文件仍依赖 .sqlite-wal
  ///     (WAL 没 checkpoint 完),不完整;VACUUM INTO 是 SQLite 官方保证一致的备份方式
  ///   - VACUUM INTO 需要 SQLite ≥ 3.27.0(2019-02),Android API 21+ 设备基本都满足
  Future<File> exportDb(AppDatabase db) async {
    final src = await _getDbFile();
    if (!await src.exists()) {
      throw const BackupException('数据库文件不存在,可能首次启动还未创建');
    }
    final tempDir = await getTemporaryDirectory();
    final stamp = _timestamp();
    final dst = File(p.join(tempDir.path, 'gridly_backup_$stamp.sqlite'));
    // VACUUM INTO 路径必须是字符串字面量或者显式 escape,这里走 raw SQL
    final escaped = dst.path.replaceAll("'", "''");
    await db.customStatement("VACUUM INTO '$escaped'");
    if (!await dst.exists()) {
      throw const BackupException('VACUUM INTO 未生成目标文件,备份失败');
    }
    return dst;
  }

  /// 分享备份文件(走系统分享)
  Future<void> shareDb(File file) async {
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/x-sqlite3'),
    ], text: '格子记账数据库备份 · ${_formatTimestamp(DateTime.now())}');
  }

  /// 还原数据库
  ///   - 流程(细节见文件头注释):
  ///     1. close db → 释放文件锁 + SQLite 自动删 .sqlite-wal/-shm
  ///     2. 复制 picked file → 覆盖 gridly.sqlite
  ///     3. SystemNavigator.pop() → 退出 app 让 user 重开
  ///   - 调用方负责 double-confirm dialog 之后再调本方法
  ///   - 不会 throw,失败抛 _BackupException
  Future<void> restoreDbFromFile(AppDatabase db, File picked) async {
    if (!await picked.exists()) {
      throw const BackupException('选中的备份文件不存在');
    }
    final dbFile = await _getDbFile();
    // 1. 关 db(WAL 模式下 close 会触发最后一次 checkpoint,
    //    并删除 .sqlite-wal/.sqlite-shm 临时文件)
    await db.close();
    // 2. 复制 picked → 覆盖 db
    try {
      await picked.copy(dbFile.path);
    } catch (e) {
      throw BackupException('复制备份文件失败:$e');
    }
    // 3. 强制退出 app,让 user 重开时重新打开 db(读新文件)
    await SystemNavigator.pop();
  }
}

/// 异常类型(给 sheet UI 弹 banner)
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 时间戳:yyyyMMdd_HHmmss(文件名 + 分享文案)
String _timestamp() {
  final n = DateTime.now();
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${pad(n.month)}${pad(n.day)}_${pad(n.hour)}${pad(n.minute)}${pad(n.second)}';
}

String _formatTimestamp(DateTime t) {
  String pad(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${pad(t.month)}-${pad(t.day)} ${pad(t.hour)}:${pad(t.minute)}';
}

/// 公开格式化(sheet 显示"修改时间"用)
String formatBackupTimestamp(DateTime t) => _formatTimestamp(t);
