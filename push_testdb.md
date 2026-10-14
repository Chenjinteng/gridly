# Gridly：通过 ADB 替换 SQLite 数据库

## 1. 环境信息

| 项目 | 路径 / 值 |
|---|---|
| Android 包名 | `cn.jinteng.gridly` |
| Mac 本地数据库 | `/tmp/gridly_year.sqlite` |
| 手机临时数据库 | `/sdcard/gridly_year.sqlite` |
| 应用私有目录 | `/data/user/0/cn.jinteng.gridly` |
| 目标数据库 | `app_flutter/gridly.sqlite` |
| 目标文件完整路径 | `/data/user/0/cn.jinteng.gridly/app_flutter/gridly.sqlite` |

## 2. 完整操作流程

### 第一步：确认设备连接

```bash
adb devices
```

确认设备状态为 `device`。

### 第二步：上传数据库到手机

```bash
adb push /tmp/gridly_year.sqlite /sdcard/gridly_year.sqlite
```

检查文件：

```bash
adb shell ls -lh /sdcard/gridly_year.sqlite
```

### 第三步：停止应用

```bash
adb shell am force-stop cn.jinteng.gridly
```

### 第四步：备份原数据库

将手机原数据库备份到 Mac：

```bash
adb exec-out run-as cn.jinteng.gridly cat app_flutter/gridly.sqlite > /tmp/gridly.sqlite.bak
```

确认备份文件存在且非空：

```bash
ls -lh /tmp/gridly.sqlite.bak
```

### 第五步：覆盖应用数据库

**推荐使用下面这条命令：**

```bash
adb shell "run-as cn.jinteng.gridly sh -c 'cat > /data/user/0/cn.jinteng.gridly/app_flutter/gridly.sqlite'" < /tmp/gridly_year.sqlite
```

说明：

- 使用 `run-as` 获取应用自身的私有目录访问权限。
- 使用绝对路径，避免当前工作目录不正确导致 `No such file or directory`。
- 使用 Mac 端标准输入将数据库内容传入手机。
- 不依赖应用用户直接读取 `/sdcard` 文件。
- 成功时通常没有输出，会直接返回终端提示符。

### 第六步：验证数据库大小

```bash
wc -c /tmp/gridly_year.sqlite

adb shell run-as cn.jinteng.gridly ls -l app_flutter/gridly.sqlite
```

本次源文件大小为 **69632 字节（68 KiB）**。覆盖成功后，目标文件大小应与源文件一致。

### 第七步：启动应用

```bash
adb shell monkey -p cn.jinteng.gridly 1
```

打开 Gridly，检查数据是否已更新。

## 3. 一键执行版本

如果后续经常替换数据库，可以在 Mac 终端直接执行以下脚本：

```bash
#!/bin/bash
set -e

PACKAGE="cn.jinteng.gridly"
SOURCE="/tmp/gridly_year.sqlite"
BACKUP="/tmp/gridly.sqlite.bak"
TARGET="app_flutter/gridly.sqlite"

if [ ! -s "$SOURCE" ]; then
    echo "错误：源数据库不存在或文件为空：$SOURCE"
    exit 1
fi

echo "1. 检查 ADB 设备"
adb get-state

echo "2. 停止应用"
adb shell am force-stop "$PACKAGE"

echo "3. 备份原数据库"
adb exec-out run-as "$PACKAGE" cat "$TARGET" > "$BACKUP"

if [ ! -s "$BACKUP" ]; then
    echo "错误：原数据库备份为空，请停止操作并检查"
    exit 1
fi

echo "4. 覆盖数据库"
adb shell "run-as $PACKAGE sh -c 'cat > /data/user/0/$PACKAGE/$TARGET'" < "$SOURCE"

echo "5. 验证数据库大小"
SOURCE_SIZE=$(wc -c < "$SOURCE" | tr -d ' ')
TARGET_SIZE=$(adb shell run-as "$PACKAGE" wc -c < /dev/null 2>/dev/null || true)

adb shell run-as "$PACKAGE" ls -l "$TARGET"

echo "源数据库大小：$SOURCE_SIZE 字节"
echo "原数据库备份：$BACKUP"
echo "请确认目标数据库大小与源数据库一致后，再启动应用。"
```

将脚本保存为 `replace_gridly_db.sh`，赋予执行权限：

```bash
chmod +x replace_gridly_db.sh
```

运行：

```bash
./replace_gridly_db.sh
```

注意：一键脚本在覆盖后仍应进行目标大小校验。若覆盖失败，不要启动应用；保留备份文件，先恢复或排查。

## 4. 常见问题

| 报错 / 现象 | 原因及处理 |
|---|---|
| `Permission denied` | 应用私有目录不能直接由普通 Shell 写入，使用 `run-as`。 |
| `No such file or directory` | 使用绝对路径，并确认 `app_flutter` 目录存在。 |
| 命令没有输出 | 正常情况下可能表示执行成功，继续检查文件大小。 |
| 覆盖后数据没变化 | 确认目标文件路径、数据库是否为实际使用的文件，以及应用是否存在缓存。 |
| 数据库异常 | 停止应用，保留备份，检查 SQLite 文件和 WAL 相关文件。 |

## 5. 注意事项

- 替换数据库前必须停止应用，避免并发写入。
- 不要随意删除 `gridly.sqlite-wal` 和 `gridly.sqlite-shm`。
- 覆盖前应保留原数据库备份。
- 重要数据建议额外验证 SQLite 完整性，而不仅仅比较文件大小。
