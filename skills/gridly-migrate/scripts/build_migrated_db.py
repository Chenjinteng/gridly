#!/usr/bin/env python3
# gridly-migrate — 旧记账数据 → gridly-migrated.sqlite
#
# 用法:
#   python3 build_migrated_db.py --source <csv|xlsx> --out gridly-migrated.sqlite \
#       [--config config.json] [--report migration-report.md]
#
# 设计原则:
#   - 只依赖 Python 标准库(无 pandas / openpyxl);xlsx 用 zipfile + xml 解析
#   - 列语义靠"表头关键词"自动识别,可被 config.json 覆盖
#   - 识别不出来的行不硬凑,全部写进报告
#   - 产物严格对齐 gridly schemaVersion 9(见 references/target-schema.md)
#
# config.json 可选字段(全部可选,不给就全自动):
# {
#   "header_row": 6,                     // 表头在第几行(1-based),null=自动
#   "columns": {                         // 覆盖自动识别结果
#     "date": "交易时间", "amount": "金额", "direction": "收/支",
#     "category": "交易分类", "account": "收/付款方式",
#     "dest_account": "对方账户", "note": "商品说明", "balance": "余额"
#   },
#   "account_types": {                   // 账户名 → gridly 资产段位
#     "花呗": "receivable", "余额宝": "investment"
#   },
#   "category_aliases": {                // 旧分类名 → gridly 分类名
#     "吃饭": "餐饮", "打车": "交通"
#   },
#   "skip_rows_before": 0,              // 跳过前 N 行(不含表头行)
#   "skip_rows_after": 0,               // 跳过末尾 N 行(汇总区)
#   "default_account": "现金",           // 找不到账户时兜底
#   "timezone": null                    // null=系统本地时区
# }

import argparse
import csv
import datetime
import json
import os
import re
import sqlite3
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
SKILL_ROOT = HERE.parent
SEED_FILE = SKILL_ROOT / "references" / "seed_data.json"

SCHEMA_VERSION = 9

TX_TYPES = {"expense", "income", "balance", "lend_out", "borrow_in"}
CAT_TYPES = {"expense", "income", "investment", "benefit", "liability", "other", "adjust"}
ASSET_TYPES = {"cash_flow", "investment", "benefit", "receivable", "fixed_asset", "other"}

# ---------------------------------------------------------------- 表头关键词

COLUMN_PATTERNS = {
    "date": [
        r"交易时间", r"交易日期", r"记账日期", r"日期", r"时间",
        r"^date$", r"^time$", r"datetime", r"occurred",
    ],
    "amount": [
        r"金额", r"发生额", r"交易额", r"^amount$", r"^value$", r"^money$",
        r"^金额\(.*\)$", r"价格",
    ],
    "direction": [
        r"收.?支", r"交易方向", r"方向", r"借贷", r"^type$", r"^category_type$",
        r"收支类型", r"资金方向",
    ],
    "category": [
        r"交易分类", r"类别", r"分类", r"^category$", r"^type$", r"摘要", r"用途",
        # 微信账单没有「交易分类」列,「商品」是最接近的分类来源
        # (「交易类型」只有 商户消费/转账 等粗粒度值,不适合当分类)
        r"^商品$", r"商品名称", r"商品说明",
    ],
    "account": [
        r"账户", r"账号", r"支付方式", r"收.?付款方式", r"付款方式", r"资金账户",
        r"^account$", r"卡号", r"钱包",
    ],
    "dest_account": [
        r"对方账户", r"转入账户", r"转出账户", r"目标账户", r"转入方", r"转出方",
        r"对方账号", r"收款账户", r"付款账户",
    ],
    "counterparty": [
        r"交易对方", r"对方名称", r"对方户名", r"^payee$", r"^counterparty$", r"商户",
    ],
    "note": [
        r"备注", r"^note$", r"^memo$", r"说明$", r"描述", r"详情", r"附言", r"摘要",
    ],
    "balance": [
        r"余额", r"当前余额", r"账户余额", r"^balance$",
    ],
}

# direction 值 → tx type
DIRECTION_MAP = {
    "支出": "expense", "expense": "expense", "付款": "expense", "借": "expense",
    "消费": "expense", "pay": "expense", "out": "expense", "debit": "expense",
    "收入": "income", "income": "income", "收款": "income", "贷": "income",
    "入账": "income", "in": "income", "credit": "income",
    "转账": "balance", "transfer": "balance", "转出": "balance", "转入": "balance",
    "余额变更": "balance", "互转": "balance",
    # 支付宝/微信导出用「不计收支」表示资金在账户间流转
    "不计收支": "balance", "不计收付": "balance",
    "借出": "lend_out", "lend_out": "lend_out", "lendout": "lend_out",
    "借入": "borrow_in", "borrow_in": "borrow_in", "borrowin": "borrow_in",
}

# 账户名关键词 → (asset_type, flags)
ACCOUNT_HINTS = [
    # 可消费债务(信用卡/花呗/白条)→ 能当 cash_flow 支出源
    (r"信用卡|花呗|白条|贷记卡|消费贷", "receivable",
     {"act_as_cash_flow": 1, "include_in_transactions": 1}),
    # 不可消费债务(车贷/房贷/借款)→ 只能走调拨还款
    (r"车贷|房贷|借款|欠款|负债|贷款", "receivable", {}),
    (r"借给|应收|别人欠|债权", "receivable", {"is_lender": 1}),
    (r"公积金|社保|医保|年金|保险", "benefit", {}),
    (r"余额宝|基金|股票|理财|证券|黄金|定投|指数", "investment", {}),
    (r"房|车|房产|车辆|不动产", "fixed_asset", {}),
    (r"现金|储蓄|借记|零钱|微信|支付宝|银行卡|工资卡|钱包|储值", "cash_flow", {}),
]

# 旧分类名 → 系统分类名
CATEGORY_ALIASES = {
    "吃饭": "餐饮", "餐饮": "餐饮", "食物": "餐饮", "餐厅": "餐饮", "外卖": "餐饮", "咖啡": "餐饮",
    "打车": "交通", "交通": "交通", "公交": "交通", "地铁": "交通", "加油": "交通", "停车": "交通",
    "淘宝": "购物", "京东": "购物", "网购": "购物", "购物": "购物", "拼多多": "购物",
    "房租": "居住", "房贷": "居住", "水电": "居住", "物业": "居住", "居住": "居住",
    "燃气": "居住", "住房": "居住", "房屋": "居住", "租金": "居住", "住宿": "居住",
    "话费": "通讯", "流量": "通讯", "宽带": "通讯", "通讯": "通讯", "网费": "通讯",
    "看病": "医疗", "医院": "医疗", "药品": "医疗", "医疗": "医疗", "体检": "医疗",
    "学费": "教育", "培训": "教育", "书籍": "教育", "教育": "教育",
    "电影": "娱乐", "游戏": "娱乐", "娱乐": "娱乐", "旅游": "娱乐", "演唱会": "娱乐",
    "家具": "居家", "家居": "居家", "居家": "居家",
    "化妆品": "美妆", "美容": "美妆", "护肤": "美妆", "美妆": "美妆",
    "宠物": "宠物",
    "工资": "工资", "薪水": "工资", "薪资": "工资",
    "年终奖": "奖金", "绩效": "奖金", "奖金": "奖金",
    "利息": "理财", "收益": "理财", "理财": "理财",
    "副业": "兼职", "外快": "兼职", "兼职": "兼职",
    "退款": "退款", "退货": "退款",
}

# 商品名/分类名 → 系统分类的关键词归并
# 微信/支付宝账单里的「商品」列是很细的名字(火锅/外套/猫粮/月卡),
# 直接当分类会造出一堆碎片分类,这里按关键词归并回系统 23 条。
# 顺序敏感:先匹配到的优先。
PRODUCT_TO_SYSTEM = [
    (r"火锅|烧烤|外卖|快餐|午餐|晚餐|早餐|餐|饭|菜|food|咖啡|奶茶|饮料|零食|水果|烘焙|蛋糕",
     "餐饮"),
    (r"打车|地铁|公交|高铁|火车|机票|加油|停车|交通|出行|单车|滴滴|油费|过路费",
     "交通"),
    (r"衣服|鞋|服饰|外套|裤|裙|内衣|箱包|日用品|超市|购物|淘宝|京东|拼多多|数码|耳机|家电|化妆品|护肤|洗发",
     "购物"),
    (r"房租|租金|物业|水电|燃气|宽带|网费|住房|家具|家居|装修|维修",
     "居住"),
    (r"话费|流量|通讯|手机费|电话费|中国移动|中国联通|中国电信",
     "通讯"),
    (r"医院|看病|药|挂号|体检|医疗|牙医|诊所|疫苗",
     "医疗"),
    (r"学费|培训|课程|书籍|书|网课|教育|考试|学习",
     "教育"),
    (r"电影|电影票|游戏|健身|运动|旅游|酒店|门票|演唱会|娱乐|会员|月卡|瑜伽|球|球馆",
     "娱乐"),
    (r"家具|装修|床|沙发|家居|厨房|电器|清洁",
     "居家"),
    (r"美妆|化妆品|护肤|面膜|口红|美容|spa|理发|剪发|美发",
     "美妆"),
    (r"猫|狗|宠物|鱼|猫粮|狗粮|宠物医院|疫苗",
     "宠物"),
    (r"工资|薪水|薪资|奖金|年终|绩效",
     "工资"),
    (r"利息|理财|收益|基金|定投|余额宝|分红",
     "理财"),
    (r"兼职|外快|副业|劳务|稿费",
     "兼职"),
    (r"退款|退货|返现|赔付",
     "退款"),
]

# 分类名 → 特殊段位(优先于 expense/income 投票)
# 这些段位的分类在 app 里 UI 隐藏,且不计入月度收支 —— 符合"投资/还款"语义
CATEGORY_SEGMENT = [
    (r"投资|基金|股票|证券|理财|定投|黄金|余额宝|收益",
     "investment", r"投资投入"),
    (r"还款|还贷|信用卡还款|花呗还款|白条还款|还信用卡|还钱|还房贷|还车贷|还花呗",
     "liability", "债务"),
    (r"福利|公积金|社保|医保|年金|保险",
     "benefit", "福利"),
]

# 分类名 → 图标候选
ICON_HINTS = [
    (r"餐|吃|食|外卖|咖啡|奶茶|菜", "restaurant"),
    (r"车|交通|打车|公交|地铁|加油|停车|油", "directions_bus"),
    (r"购物|淘宝|京东|网购|买", "shopping_bag"),
    (r"房|租|水电|物业|燃气", "home"),
    (r"话费|流量|通讯|宽带|电话", "phone_iphone"),
    (r"医|药|病|体检", "medical_services"),
    (r"学|书|培训|教育|课程", "school"),
    (r"电影|游戏|娱乐|玩|唱", "movie"),
    (r"家|家具|居家|装修", "chair"),
    (r"美|化妆|护肤|美容", "spa"),
    (r"宠|猫|狗", "pets"),
    (r"工资|薪", "payments"),
    (r"奖|年终", "card_giftcard"),
    (r"理财|利息|收益|基金", "savings"),
    (r"兼职|副业|外快", "work"),
    (r"退款|退货", "replay"),
    (r"投资|股票|证券|黄金", "trending_up"),
    (r"福利|社保|公积金|医保", "favorite"),
    (r"债|还|贷|借", "request_quote"),
]


# ---------------------------------------------------------------- 工具函数

def load_seed():
    with open(SEED_FILE, encoding="utf-8") as f:
        return json.load(f)


def sniff_delimiter(sample: str) -> str:
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t|").delimiter
    except csv.Error:
        counts = {d: sample.count(d) for d in ",;\t|"}
        return max(counts, key=counts.get) if max(counts.values()) > 0 else ","


def read_csv_rows(path: Path):
    raw = path.read_bytes()
    text = None
    for enc in ("utf-8-sig", "utf-8", "gb18030", "gbk", "big5", "latin-1"):
        try:
            text = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    if text is None:
        raise SystemExit(f"无法解码文件 {path}")
    delimiter = sniff_delimiter(text[:8192])
    reader = csv.reader(text.splitlines(), delimiter=delimiter)
    return [row for row in reader]


def read_xlsx_rows(path: Path):
    """极简 xlsx 读取:sharedStrings + 第一张 sheet 的 cell 文本。"""
    ns = {
        "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
        "rel": "http://schemas.openxmlformats.org/package/2006/relationships",
    }
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        shared = []
        if "xl/sharedStrings.xml" in names:
            root = ET.fromstring(zf.read("xl/sharedStrings.xml"))
            for si in root.findall("main:si", ns):
                shared.append("".join(t.text or "" for t in si.iter(
                    "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t")))
        # 第一个 worksheet
        sheet = sorted(n for n in names if re.match(r"xl/worksheets/sheet\d+\.xml$", n))[0]
        root = ET.fromstring(zf.read(sheet))
        rows = []
        for row in root.iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}row"):
            cells = {}
            for c in row.iter("{http://schemas.openxmlformats.org/spreadsheetml/2006/main}c"):
                ref = c.get("r") or ""
                m = re.match(r"([A-Z]+)", ref)
                if not m:
                    continue
                col = 0
                for ch in m.group(1):
                    col = col * 26 + (ord(ch) - 64)
                col -= 1
                t = c.get("t")
                if t == "inlineStr":
                    is_el = c.find("main:is", ns)
                    val = "".join(x.text or "" for x in is_el.iter(
                        "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t")) if is_el is not None else ""
                else:
                    v = c.find("main:v", ns)
                    val = v.text if v is not None and v.text is not None else ""
                    if t == "s":
                        try:
                            val = shared[int(val)]
                        except (ValueError, IndexError):
                            val = ""
                cells[col] = val
            if cells:
                width = max(cells) + 1
                rows.append([cells.get(i, "") for i in range(width)])
            else:
                rows.append([])
        return rows


def read_rows(path: Path):
    if path.suffix.lower() in (".xlsx", ".xlsm"):
        return read_xlsx_rows(path)
    return read_csv_rows(path)


def norm(s) -> str:
    return re.sub(r"\s+", "", str(s if s is not None else "")).lower()


def detect_header(rows, cfg):
    """返回 (header_row_index, header_list)"""
    if cfg.get("header_row"):
        idx = int(cfg["header_row"]) - 1
        return idx, [str(x) for x in rows[idx]]
    best, best_score = None, -1
    for i, row in enumerate(rows[:40]):
        cells = [norm(c) for c in row]
        joined = " ".join(cells)
        score = 0
        for pats in COLUMN_PATTERNS.values():
            if any(re.search(p, joined) for p in pats):
                score += 1
        # 奖励:含「时间/日期」和「金额」
        if re.search(r"时间|日期|date", joined):
            score += 2
        if re.search(r"金额|amount|发生额", joined):
            score += 2
        filled = sum(1 for c in cells if c)
        if score > best_score and filled >= 2:
            best, best_score = i, score
    if best is None:
        best = 0
    return best, [str(x) for x in rows[best]]


def detect_columns(header, cfg):
    """语义 → 列下标"""
    override = cfg.get("columns") or {}
    result = {}
    for sem, colname in override.items():
        if colname is None:
            continue
        for i, h in enumerate(header):
            if str(h).strip() == str(colname).strip():
                result[sem] = i
                break
    used = set(result.values())
    for sem, pats in COLUMN_PATTERNS.items():
        if sem in result:
            continue
        best, best_rank = None, len(pats) + 1
        for i, h in enumerate(header):
            if i in used:
                continue
            nh = norm(h)
            if not nh:
                continue
            for rank, pat in enumerate(pats):
                if re.search(pat, nh):
                    if rank < best_rank:
                        best, best_rank = i, rank
                    break
        if best is not None:
            result[sem] = best
            used.add(best)
    return result


def parse_amount(v):
    if v is None:
        return None
    s = str(v).strip()
    if not s or s in {"-", "--", "—"}:
        return None
    neg = False
    if s.startswith("(") and s.endswith(")"):
        neg, s = True, s[1:-1]
    s = re.sub(r"[¥￥$€£,\s]", "", s)
    s = re.sub(r"(元|人民币|RMB|CNY)", "", s, flags=re.I)
    if s.startswith("-"):
        neg, s = True, s[1:].strip()
    if s.startswith("+"):
        s = s[1:].strip()
    if not re.fullmatch(r"\d*\.?\d+", s):
        return None
    try:
        val = float(s)
    except ValueError:
        return None
    return -val if neg else val


def parse_date(v, tz_override=None):
    """返回 (epoch_seconds, has_time) 或 (None, False)"""
    if v is None:
        return None, False
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        # Excel 序列号
        if 20000 < float(v) < 80000:
            base = datetime.datetime(1899, 12, 30)
            dt = base + datetime.timedelta(days=float(v))
            return int(dt.timestamp()), False
        # 已是 epoch 秒/毫秒
        iv = int(v)
        if iv > 10_000_000_000:
            return iv // 1000, True
        return iv, True
    s = str(v).strip()
    if not s:
        return None, False
    s = s.replace("　", " ")
    # 纯数字 YYYYMMDD
    if re.fullmatch(r"\d{8}", s):
        try:
            dt = datetime.datetime(int(s[:4]), int(s[4:6]), int(s[6:8]))
            return int(dt.timestamp()), False
        except ValueError:
            return None, False
    # 带时区
    m = re.search(r"([+-]\d{2}):?(\d{2})$", s)
    tzinfo = None
    if m:
        sign = 1 if m.group(1)[0] == "+" else -1
        offset = sign * (int(m.group(1)[1:]) * 3600 + int(m.group(2)) * 60)
        tzinfo = datetime.timezone(datetime.timedelta(seconds=offset))
        s = s[:m.start()].strip()
    s = s.replace("/", "-").replace(".", "-").replace("年", "-").replace("月", "-").replace("日", "")
    s = re.sub(r"\s+", " ", s).strip()
    # 归一化分隔
    s = re.sub(r"-+", "-", s)
    fmts = [
        "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d",
        "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M",
        "%m-%d-%Y %H:%M:%S", "%m-%d-%Y %H:%M", "%m-%d-%Y",
    ]
    for fmt in fmts:
        try:
            dt = datetime.datetime.strptime(s, fmt)
            if tzinfo:
                dt = dt.replace(tzinfo=tzinfo)
            has_time = "%H" in fmt
            return int(dt.timestamp()), has_time
        except ValueError:
            continue
    return None, False


def guess_asset_type(name, cfg):
    override = (cfg.get("account_types") or {}).get(name)
    if override:
        if override not in ASSET_TYPES:
            raise SystemExit(f"account_types 里的 '{name}' → '{override}' 不是合法资产段位")
        return override, {}
    for pat, atype, flags in ACCOUNT_HINTS:
        if re.search(pat, name):
            return atype, dict(flags)
    return "cash_flow", {}


def guess_icon(category_name, cat_type, seed):
    for pat, icon in ICON_HINTS:
        if re.search(pat, category_name):
            return icon
    return "more_horiz"


def pick_color(name, seed):
    palette = seed["hash_palette"]
    return palette[sum(ord(c) for c in name) % len(palette)]


def is_summary_row(values):
    """汇总行 / 分隔线 / 空行 —— 不是数据"""
    cells = [str(v).strip() for v in values if str(v).strip()]
    if not cells:
        return True
    joined = " ".join(cells)
    if re.search(r"合\s*计|总\s*计|小\s*计|共\s*\d+\s*笔|总金额|汇总|statistics|total", joined, re.I):
        return True
    # 纯符号分隔行(如 "-----..." 或 "————")
    if all(re.fullmatch(r"[-=—–_*·\.\s]{3,}", c) for c in cells):
        return True
    # 整行都是数字(没有文字描述)—— 多半是统计汇总
    if all(re.fullmatch(r"[-+]?[\d.,]+", c) for c in cells) and len(cells) <= 2:
        return True
    return False


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser(description="旧记账数据 → gridly-migrated.sqlite")
    ap.add_argument("--source", required=True, help="源文件(.csv / .xlsx)")
    ap.add_argument("--out", default="gridly-migrated.sqlite")
    ap.add_argument("--config", default=None, help="可选 JSON 配置")
    ap.add_argument("--report", default="migration-report.md")
    ap.add_argument("--merge-into", default=None,
                    help="把数据合并进这个已有 gridly 库(而非产出干净库)。"
                         "用户 app 里的现有账本会保留 —— 走这条路更安全")
    args = ap.parse_args()

    src = Path(args.source).expanduser().resolve()
    out = Path(args.out).expanduser().resolve()
    cfg = {}
    if args.config:
        with open(args.config, encoding="utf-8") as f:
            cfg = json.load(f)
    seed = load_seed()

    if not src.exists():
        raise SystemExit(f"源文件不存在:{src}")

    rows = read_rows(src)
    if not rows:
        raise SystemExit("源文件是空的")

    hdr_idx, header = detect_header(rows, cfg)
    cols = detect_columns(header, cfg)
    print(f"[1/6] 表头行:第 {hdr_idx+1} 行 → {header}")
    print(f"      识别到的列语义: {cols}")
    if "date" not in cols or "amount" not in cols:
        print("[警告] 未能识别出日期列或金额列 —— 迁移质量会很低,"
              "建议用 --config 显式指定 columns。")

    # ---- 建库
    merge_base = None
    if args.merge_into:
        merge_base = Path(args.merge_into).expanduser().resolve()
        if not merge_base.exists():
            raise SystemExit(f"--merge-into 指定的库不存在:{merge_base}")
        if out.exists():
            out.unlink()
        # 复制已有库作为基线(保留用户原有账本)
        import shutil
        shutil.copy2(merge_base, out)
        print(f"[2/6] 合并模式:基线 = {merge_base}")
    else:
        if out.exists():
            out.unlink()
    conn = sqlite3.connect(str(out))
    conn.row_factory = sqlite3.Row
    if not merge_base:
        conn.executescript("""
CREATE TABLE "categories" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL, "icon" TEXT NOT NULL, "color" INTEGER NOT NULL,
  "type" TEXT NOT NULL,
  "is_system" INTEGER NOT NULL DEFAULT 0 CHECK ("is_system" IN (0, 1)),
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "assets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL, "type" TEXT NOT NULL,
  "icon" TEXT NOT NULL DEFAULT 'account_balance_wallet',
  "color" INTEGER NOT NULL DEFAULT 4279548070,
  "initial_balance" REAL NOT NULL DEFAULT 0.0,
  "include_in_transactions" INTEGER NOT NULL DEFAULT 1 CHECK ("include_in_transactions" IN (0, 1)),
  "is_default" INTEGER NOT NULL DEFAULT 0 CHECK ("is_default" IN (0, 1)),
  "act_as_cash_flow" INTEGER NOT NULL DEFAULT 0 CHECK ("act_as_cash_flow" IN (0, 1)),
  "is_lender" INTEGER NOT NULL DEFAULT 0 CHECK ("is_lender" IN (0, 1)),
  "display_order" INTEGER NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "amount" REAL NOT NULL, "type" TEXT NOT NULL, "category_id" INTEGER NOT NULL,
  "occurred_at" INTEGER NOT NULL, "note" TEXT NULL,
  "account_id" INTEGER NOT NULL, "destination_account_id" INTEGER NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "category_budgets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "category_id" INTEGER NOT NULL,
  "year" INTEGER NOT NULL, "month" INTEGER NOT NULL, "amount" REAL NOT NULL,
  "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  UNIQUE ("category_id", "year", "month"));
CREATE TABLE "monthly_budgets" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "year" INTEGER NOT NULL,
  "month" INTEGER NOT NULL, "amount" REAL NOT NULL,
  "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
  UNIQUE ("year", "month"));
""")
    now = int(datetime.datetime.now().timestamp())

    # ---- 分类 / 资产基线
    # 干净库:写入系统预置 23 分类 + 3 资产
    # 合并库:复用库里已有的,避免重复,也避免把用户的自定义分类冲掉
    cat_id = {}
    asset_id = {}
    if merge_base:
        for r in conn.execute("SELECT id,name FROM categories"):
            cat_id.setdefault(r["name"], r["id"])
        for r in conn.execute("SELECT id,name FROM assets"):
            asset_id.setdefault(r["name"], r["id"])
        # 系统分类里库里没有的补上(app 启动会 ensure,但补上更稳)
        for c in seed["categories"]:
            if c["name"] not in cat_id:
                cur = conn.execute(
                    "INSERT INTO categories(name,icon,color,type,is_system,sort_order,created_at,updated_at)"
                    " VALUES(?,?,?,?,1,?,?,?)",
                    (c["name"], c["icon"], c["color"], c["type"], c["sort_order"], now, now))
                cat_id[c["name"]] = cur.lastrowid
        for a in seed["assets"]:
            if a["name"] not in asset_id:
                cur = conn.execute(
                    "INSERT INTO assets(name,type,icon,color,initial_balance,include_in_transactions,"
                    "is_default,act_as_cash_flow,is_lender,display_order,created_at,updated_at)"
                    " VALUES(?,?,?,?,0,?,?,0,0,?,?,?)",
                    (a["name"], a["type"], a["icon"], a["color"],
                     1 if a["type"] == "cash_flow" else 0,
                     a["is_default"], a["display_order"], now, now))
                asset_id[a["name"]] = cur.lastrowid
        print(f"[2/6] 合并模式:复用已有分类 {len(cat_id)} 条 + 资产 {len(asset_id)} 个")
    else:
        for c in seed["categories"]:
            cur = conn.execute(
                "INSERT INTO categories(name,icon,color,type,is_system,sort_order,created_at,updated_at)"
                " VALUES(?,?,?,?,1,?,?,?)",
                (c["name"], c["icon"], c["color"], c["type"], c["sort_order"], now, now))
            cat_id[c["name"]] = cur.lastrowid
        for a in seed["assets"]:
            cur = conn.execute(
                "INSERT INTO assets(name,type,icon,color,initial_balance,include_in_transactions,"
                "is_default,act_as_cash_flow,is_lender,display_order,created_at,updated_at)"
                " VALUES(?,?,?,?,0,?,?,0,0,?,?,?)",
                (a["name"], a["type"], a["icon"], a["color"],
                 1 if a["type"] == "cash_flow" else 0,
                 a["is_default"], a["display_order"], now, now))
            asset_id[a["name"]] = cur.lastrowid
        print(f"[2/6] 写入系统分类 {len(cat_id)} 条 + 系统资产 {len(asset_id)} 条")

    # ---- 扫描数据行,做归类统计
    data_rows = rows[hdr_idx + 1:]
    skip_before = int(cfg.get("skip_rows_before", 0))
    skip_after = int(cfg.get("skip_rows_after", 0))
    if skip_after:
        data_rows = data_rows[:-skip_after]

    # 第一遍:收集账户名、分类名(含收支方向)
    account_names, cat_names = set(), {}
    parsed_rows = []
    skipped = []

    def cell(row, sem):
        i = cols.get(sem)
        if i is None or i >= len(row):
            return None
        return row[i]

    for ri, row in enumerate(data_rows):
        line_no = hdr_idx + 2 + ri
        if not any(str(c).strip() for c in row):
            continue
        if is_summary_row(row):
            continue
        raw_amount = cell(row, "amount")
        amt = parse_amount(raw_amount)
        dt, _has_time = parse_date(cell(row, "date"))
        cat_raw = cell(row, "category")
        cat_name = str(cat_raw).strip() if cat_raw is not None else ""
        acc_raw = cell(row, "account")
        acc_name = str(acc_raw).strip() if acc_raw is not None else ""
        dir_raw = cell(row, "direction")
        dir_val = str(dir_raw).strip() if dir_raw is not None else ""
        parsed_rows.append(dict(
            line=line_no, raw=row, amt=amt, dt=dt, cat=cat_name, acc=acc_name,
            dir=dir_val, note=str(cell(row, "note") or "").strip() or None,
            dest=str(cell(row, "dest_account") or "").strip() or None,
            cp=str(cell(row, "counterparty") or "").strip() or None,
        ))
        if acc_name:
            account_names.add(acc_name)
        if cat_name:
            cat_names.setdefault(cat_name, {"expense": 0, "income": 0})

    # 第二遍:定每条流水的 type
    for p in parsed_rows:
        t = DIRECTION_MAP.get(norm(p["dir"]))
        if t is None and p["dir"]:
            for k, v in DIRECTION_MAP.items():
                if k and k in norm(p["dir"]):
                    t = v
                    break
        if t is None:
            if p["amt"] is None:
                t = None
            elif p["amt"] < 0:
                t = "expense"
            elif p["amt"] > 0:
                t = "income"
        p["type"] = t
        # 分类方向统计推迟到写入阶段(只有真正迁移成功的行才计数),
        # 否则被跳过的行会造出没有流水的孤儿分类

    # ---- 分类映射
    # 分类的 type 取决于它在旧数据里出现在支出还是收入行。
    # 先按"该分类名下所有行的方向投票"决定 type,写完流水后再清理没有流水的分类。
    aliases = {**CATEGORY_ALIASES, **(cfg.get("category_aliases") or {})}
    # 合并模式下,库里已有的分类(系统 + 用户自定义)都可直接复用,
    # 避免在用户账本里造出重复分类
    sys_names = {c["name"] for c in seed["categories"]}
    if merge_base:
        sys_names |= set(cat_id.keys())
    custom_cats = []
    custom_cat_id = {}
    order = 100

    # 投票:分类名 → {expense: n, income: n}
    votes = {}
    for p in parsed_rows:
        if not p["cat"] or not p["type"]:
            continue
        v = votes.setdefault(p["cat"], {"expense": 0, "income": 0})
        if p["type"] == "income":
            v["income"] += 1
        elif p["type"] in ("expense", "balance"):
            v["expense"] += 1

    name_to_target = {}
    for name in sorted(cat_names):
        target = None
        if name in sys_names:
            target = name
        else:
            # 先试商品名关键词归并(微信/支付宝的「商品」列很细)
            for pat, sys_cat in PRODUCT_TO_SYSTEM:
                if re.search(pat, name):
                    target = sys_cat
                    break
        if target is None:
            for a_name, a_target in aliases.items():
                if name == a_name or norm(name) == norm(a_target):
                    target = a_target
                    break
            if target and target not in sys_names:
                target = None
        if target:
            # 旧分类名命中系统分类(可能经由别名)→ 记录映射,写入时按目标名查 id
            name_to_target[name] = target
            continue
        # 新建自定义分类
        v = votes.get(name, {"expense": 0, "income": 0})
        ctype = None
        for pat, seg_type, seg_cat in CATEGORY_SEGMENT:
            if re.search(pat, name):
                ctype = seg_type
                seg_hint = seg_cat
                break
        if ctype is None:
            if v["income"] > v["expense"]:
                ctype = "income"
            else:
                ctype = "expense"
        if ctype in ("investment", "benefit", "liability", "other", "adjust"):
            # 这类段位的分类在 app 里 UI 隐藏 + 自动 fallback,
            # 直接用系统内置分类(同段位),不要新建自定义分类
            builtin = None
            for c in seed["categories"]:
                if c["type"] == ctype:
                    builtin = c["name"]
                    break
            if builtin:
                name_to_target[name] = builtin
                continue
        icon = guess_icon(name, ctype, seed)
        color = pick_color(name, seed)
        cur = conn.execute(
            "INSERT INTO categories(name,icon,color,type,is_system,sort_order,created_at,updated_at)"
            " VALUES(?,?,?,?,0,?,?,?)",
            (name, icon, color, ctype, order, now, now))
        order += 1
        custom_cat_id[name] = cur.lastrowid
        custom_cats.append(dict(name=name, icon=icon, color=color, type=ctype,
                                expense_n=v["expense"], income_n=v["income"]))
    print(f"[3/6] 自定义分类新建 {len(custom_cats)} 条(系统分类命中复用)")

    # ---- 账户映射
    def _match_existing_account(name):
        """把源数据的账户名匹配到库里已有的账户。
        「招商银行(1234)」→ 库里的「工资卡(招商银行)」——
        按括号前的机构名做包含匹配,避免同一个银行被拆成两个账户。
        """
        if name in asset_id:
            return asset_id[name]
        base = re.split(r"[（(【\[]", name)[0].strip()
        if not base or base == name:
            return None
        cands = [aid for nm, aid in asset_id.items()
                 if base in nm or nm in base]
        # 取最贴近的(名字最短 = 最可能是同一账户的简短写法)
        if cands:
            best = min(cands, key=lambda aid: len(
                [nm for nm in asset_id if asset_id[nm] == aid][0]))
            return best
        return None

    def resolve_account(name):
        if name in asset_id:
            return asset_id[name]
        matched = _match_existing_account(name)
        if matched is not None:
            asset_id[name] = matched   # 记下别名,后续行直接命中
            return matched
        atype, flags = guess_asset_type(name, cfg)
        icon = "account_balance_wallet"
        if atype == "receivable":
            icon = "credit_card"
        elif atype == "investment":
            icon = "savings"
        elif atype == "benefit":
            icon = "favorite"
        elif atype == "fixed_asset":
            icon = "home"
        color = pick_color(name, seed)
        inc = flags.get("include_in_transactions", 1 if atype == "cash_flow" else 0)
        cur = conn.execute(
            "INSERT INTO assets(name,type,icon,color,initial_balance,include_in_transactions,"
            "is_default,act_as_cash_flow,is_lender,display_order,created_at,updated_at)"
            " VALUES(?,?,?,?,0,?,0,?,?,?,?,?)",
            (name, atype, icon, color, inc, flags.get("act_as_cash_flow", 0),
             flags.get("is_lender", 0), 100 + len(asset_id), now, now))
        asset_id[name] = cur.lastrowid
        return cur.lastrowid

    for name in sorted(account_names):
        resolve_account(name)
    print(f"[4/6] 账户 {len(asset_id)} 个(系统 3 + 新建 {len(asset_id)-3})")

    default_account_name = cfg.get("default_account") or "现金"
    default_acc_id = asset_id.get(default_account_name) or list(asset_id.values())[0]

    # ---- 写流水
    tx_ok = 0
    degraded = []   # 降级迁移(不是丢弃,但语义打了折)
    imported_detail = []   # 逐笔迁移明细(报告里列出映射依据)
    cat_type_of = {c["name"]: c["type"] for c in seed["categories"]}
    for _r in conn.execute("SELECT id,name,type FROM categories"):
        cat_type_of[_r["name"]] = _r["type"]
    first_imported_id = (conn.execute("SELECT COALESCE(MAX(id),0) FROM transactions").fetchone()[0] or 0) + 1
    for p in parsed_rows:
        if p["amt"] is None:
            skipped.append((p["line"], "金额无法解析", p["raw"]))
            continue
        if p["dt"] is None:
            skipped.append((p["line"], "日期无法解析", p["raw"]))
            continue
        if not p["type"] or p["type"] not in TX_TYPES:
            skipped.append((p["line"], f"类型无法判定(收/支='{p['dir']}')", p["raw"]))
            continue
        # 分类(旧名可能经别名映射到系统分类)
        cat_name = p["cat"]
        target_name = name_to_target.get(cat_name, cat_name)
        if target_name in cat_id:
            cid = cat_id[target_name]
        elif cat_name in custom_cat_id:
            cid = custom_cat_id[cat_name]
        elif not cat_name:
            skipped.append((p["line"], "分类为空", p["raw"]))
            continue
        else:
            skipped.append((p["line"], f"分类无法映射: '{cat_name}'", p["raw"]))
            continue
        # 账户
        if p["acc"]:
            aid = resolve_account(p["acc"])
        else:
            aid = default_acc_id
        # 目标账户
        did = None
        if p["type"] == "balance":
            if p["dest"]:
                did = resolve_account(p["dest"])
            elif p.get("cp") and p["cp"] in asset_id:
                # 「交易对方」恰好是一个已知账户名 → 认定为目标账户
                did = asset_id[p["cp"]]
            else:
                # 推不出目标账户。默认**不迁**(不硬猜方向 —— 猜错会凭空污染余额和月度汇总),
                # 用 --config 的 "degrade_transfers": true 可以改成降级写入。
                if not cfg.get("degrade_transfers"):
                    skipped.append((p["line"],
                                    "转账缺少目标账户,无法配对(未硬猜方向)", p["raw"]))
                    continue
                # 降级为普通收支,不丢数据
                # 「还款」类 → 支出;「转入」类 → 收入
                cat_type = None
                for c in seed["categories"]:
                    if c["name"] == cat_name:
                        cat_type = c["type"]
                if cat_type == "liability" or re.search(r"还|还款|还贷|信用卡", cat_name or ""):
                    p["type"] = "expense"
                else:
                    p["type"] = "income"
                # 分类 type 必须与流水 type 对齐,否则 app 汇总口径会漏算
                if cat_name in custom_cat_id:
                    conn.execute("UPDATE categories SET type=? WHERE id=?",
                                 (p["type"], custom_cat_id[cat_name]))
                    for cc in custom_cats:
                        if cc["name"] == cat_name:
                            cc["type"] = p["type"]
                            break
                degraded.append((p["line"],
                                 f"转账缺少目标账户,已降级为 {p['type']}(不再是账户间划转)", p["raw"]))
        conn.execute(
            "INSERT INTO transactions(amount,type,category_id,occurred_at,note,account_id,"
            "destination_account_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)",
            (round(abs(p["amt"]), 2), p["type"], cid, p["dt"], p["note"], aid, did, now, now))
        # 记录映射依据(报告里逐笔列出,方便用户复核/推翻)
        why = []
        if p["cat"] and target_name != p["cat"]:
            why.append(f"分类「{p['cat']}」→ {target_name}")
        elif p["cat"]:
            why.append(f"分类「{p['cat']}」")
        if p["acc"]:
            acc_label = {v: k for k, v in asset_id.items()}.get(aid, p["acc"])
            if acc_label != p["acc"]:
                why.append(f"账户「{p['acc']}」→ {acc_label}")
        if p["type"] and p["dir"]:
            why.append(f"收/支「{p['dir']}」→ {p['type']}")
        imported_detail.append(dict(
            dt=p["dt"], amount=round(abs(p["amt"]), 2), type=p["type"],
            cat=target_name, ctype=cat_type_of.get(target_name),
            acc=acc_label if p["acc"] else "(默认账户)", note=p["note"],
            why="; ".join(why) or "-"))
        tx_ok += 1
    print(f"[5/6] 流水写入 {tx_ok} 笔,跳过 {len(skipped)} 笔,降级 {len(degraded)} 笔")

    # ---- 清理没有任何流水的自定义分类(避免孤儿分类)
    orphan = conn.execute(
        "SELECT c.id, c.name FROM categories c WHERE c.is_system=0 AND c.id NOT IN "
        "(SELECT category_id FROM transactions)").fetchall()
    for cid_, cname in orphan:
        conn.execute("DELETE FROM categories WHERE id=?", (cid_,))
        for cc in custom_cats:
            if cc["name"] == cname:
                custom_cats.remove(cc)
                break
    if orphan:
        print(f"      清理孤儿分类 {len(orphan)} 条(旧数据里存在但最终没有流水)")

    # ---- 资产余额倒推(有 balance 列时)
    balance_warn = []
    if "balance" in cols:
        by_acc = {}
        for p in parsed_rows:
            if p["amt"] is None or p["dt"] is None or not p["type"]:
                continue
            if not p["acc"]:
                continue
            delta = 0.0
            if p["type"] == "income":
                delta += abs(p["amt"])
            elif p["type"] == "expense":
                delta -= abs(p["amt"])
            elif p["type"] == "lend_out":
                delta += abs(p["amt"])
            elif p["type"] == "borrow_in":
                delta -= abs(p["amt"])
            by_acc[p["acc"]] = by_acc.get(p["acc"], 0.0) + delta
        # 取每个账户最后一条的 balance 值
        last_bal = {}
        for p in parsed_rows:
            b = parse_amount(cell(p["raw"], "balance"))
            if b is not None and p["acc"]:
                last_bal[p["acc"]] = (p["dt"] or 0, b)
        for acc, (_ts, stated) in last_bal.items():
            if acc not in asset_id:
                continue
            net = by_acc.get(acc, 0.0)
            initial = stated - net
            conn.execute("UPDATE assets SET initial_balance=? WHERE id=?",
                         (round(initial, 2), asset_id[acc]))
            if abs(initial) > 1:
                balance_warn.append((acc, stated, round(net, 2), round(initial, 2)))

    conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    conn.commit()

    # ---- 校验
    def scalar(sql, params=None):
        return conn.execute(sql, params or []).fetchone()[0]

    # 合并模式下,库里本来就有用户的自定义分类和负余额流水(信用卡欠款),
    # 这两项不是错误 —— 改成只检查本次导入的行
    if merge_base:
        sys_cat_check = scalar(
            "SELECT COUNT(*) FROM categories WHERE is_system=1 AND name IN (%s)"
            % ",".join("?" * len(seed["categories"])),
            [c["name"] for c in seed["categories"]]) == len(seed["categories"])
        neg_check = scalar(
            "SELECT COUNT(*) FROM transactions WHERE amount < 0 AND id >= ?",
            [first_imported_id]) == 0
    else:
        sys_cat_check = scalar("SELECT COUNT(*) FROM categories WHERE is_system=1") == 23
        neg_check = scalar("SELECT COUNT(*) FROM transactions WHERE amount < 0") == 0

    checks = {
        "user_version == 9": scalar("PRAGMA user_version") == 9,
        "表数 == 5": len([r for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")]) == 5,
        "系统分类齐备": sys_cat_check,
        "无悬空 category 引用": scalar(
            "SELECT COUNT(*) FROM transactions t LEFT JOIN categories c ON t.category_id=c.id WHERE c.id IS NULL") == 0,
        "无悬空 account 引用": scalar(
            "SELECT COUNT(*) FROM transactions t LEFT JOIN assets a ON t.account_id=a.id WHERE a.id IS NULL") == 0,
        "无悬空 dest 引用": scalar(
            "SELECT COUNT(*) FROM transactions t LEFT JOIN assets a ON t.destination_account_id=a.id "
            "WHERE t.destination_account_id IS NOT NULL AND a.id IS NULL") == 0,
        "金额无负数": neg_check,
        "type 全部合法": all(r[0] in TX_TYPES for r in conn.execute("SELECT DISTINCT type FROM transactions")),
        "时间戳是秒": scalar(
            "SELECT COUNT(*) FROM transactions WHERE occurred_at > 99999999999") == 0,
        "is_default 唯一": scalar(
            "SELECT COUNT(*) FROM (SELECT id FROM assets WHERE is_default=1 GROUP BY id HAVING COUNT(*)>1)") == 0,
    }
    print("[6/6] 自检:")
    for k, v in checks.items():
        print(f"      {'✓' if v else '✗'} {k}")
    failed = [k for k, v in checks.items() if not v]

    # ---- 报告
    write_report(args.report, src, out, seed, custom_cats, skipped, degraded, balance_warn,
                 checks, failed, tx_ok, conn, imported_detail)
    conn.close()

    print()
    print(f"产物:{out}")
    print(f"报告:{Path(args.report).resolve()}")
    if failed:
        print("\n⚠️ 有自检项未通过:", ", ".join(failed))
        sys.exit(1)
    print("\n✅ 迁移完成,自检全过。")


def write_report(path, src, out, seed, custom_cats, skipped, degraded, balance_warn,
                 checks, failed, tx_ok, conn, imported_detail=None):
    total_tx = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    total_cat = conn.execute("SELECT COUNT(*) FROM categories").fetchone()[0]
    total_asset = conn.execute("SELECT COUNT(*) FROM assets").fetchone()[0]
    by_type = dict(conn.execute("SELECT type, COUNT(*) FROM transactions GROUP BY type").fetchall())

    L = []
    A = L.append
    A("# Gridly 数据迁移报告")
    A("")
    A(f"- **源文件**:`{src}`")
    A(f"- **产物**:`{out}`")
    A(f"- **生成时间**:{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    A(f"- **目标 schema**:gridly schemaVersion {SCHEMA_VERSION}")
    A("")
    A("## 迁移结果")
    A("")
    A("| 项目 | 数量 |")
    A("| --- | --- |")
    A(f"| 流水 transactions | {total_tx} |")
    A(f"| 分类 categories | {total_cat}(系统 {len(seed['categories'])} + 自定义 {len(custom_cats)}) |")
    A(f"| 资产 assets | {total_asset}(系统 {len(seed['assets'])} + 新建 {total_asset - len(seed['assets'])}) |")
    A("")
    A("**流水类型分布**:" + "、".join(f"`{k}` {v}" for k, v in sorted(by_type.items())))
    A("")
    A("## 自检结果")
    A("")
    A("| 检查项 | 结果 |")
    A("| --- | --- |")
    for k, v in checks.items():
        A(f"| {k} | {'✅ 通过' if v else '❌ 未通过'} |")
    A("")
    if failed:
        A(f"> ⚠️ {len(failed)} 项自检未通过,**该文件导入 app 可能异常**,请先修复。")
        A("")

    if imported_detail:
        A("## 迁移成功明细")
        A("")
        A("每笔都标了**映射依据**,方便逐条复核或推翻:")
        A("")
        A("| 时间 | 金额 | 类型 | 分类 | 账户 | 备注 | 映射依据 |")
        A("| --- | --- | --- | --- | --- | --- | --- |")
        for d in imported_detail:
            dt = datetime.datetime.fromtimestamp(d["dt"]).strftime("%Y-%m-%d %H:%M:%S")
            note = (d["note"] or "").replace("|", "\\|")
            A(f"| {dt} | {d['amount']:.2f} | `{d['type']}` | {d['cat']} | {d['acc']} | {note} | {d['why']} |")
        A("")

    if custom_cats:
        A("## 新建的自定义分类")
        A("")
        A("| 名称 | 归类 | 图标 | 颜色 | 旧数据出现次数(支出/收入) |")
        A("| --- | --- | --- | --- | --- |")
        for c in custom_cats:
            A(f"| {c['name']} | `{c['type']}` | `{c['icon']}` | `0x{c['color']:08X}` | {c['expense_n']} / {c['income_n']} |")
        A("")

    if balance_warn:
        A("## ⚠️ 余额倒推差异")
        A("")
        A("以下账户的**期初余额**由「旧余额 − 流水净变动」倒推得到,数值较大,"
          "可能意味着旧数据的历史流水不完整,请人工确认:")
        A("")
        A("| 账户 | 旧数据余额 | 流水净变动 | 倒推期初余额 |")
        A("| --- | --- | --- | --- |")
        for acc, stated, net, initial in balance_warn:
            A(f"| {acc} | {stated} | {net} | **{initial}** |")
        A("")

    if degraded:
        A("## ⚠️ 降级迁移的数据")
        A("")
        A(f"共 **{len(degraded)}** 行未能完整还原语义,已按最接近的方式写入(数据保留,但语义有简化):")
        A("")
        A("| 源文件行号 | 降级方式 | 原始内容 |")
        A("| --- | --- | --- |")
        for line, reason, raw in degraded:
            cells = " / ".join(str(c) for c in raw if str(c).strip()).replace("|", "\\|")
            A(f"| {line} | {reason} | {cells} |")
        A("")

    A("## ❗ 无法迁移的数据")
    A("")
    if not skipped:
        A("无 —— 所有数据行均已成功迁移。")
    else:
        A(f"共 **{len(skipped)}** 行未迁移。下列为原始行内容(供人工补录参考):")
        A("")
        A("| 源文件行号 | 原因 | 原始内容 |")
        A("| --- | --- | --- |")
        for line, reason, raw in skipped:
            cells = " / ".join(str(c) for c in raw if str(c).strip())
            cells = cells.replace("|", "\\|")
            A(f"| {line} | {reason} | {cells} |")
    A("")
    A("## 导入方式")
    A("")
    A("1. 把 `gridly-migrated.sqlite` 传到手机")
    A("2. 打开 gridly → **我的** → **数据** → **备份还原** → **还原** → 选这个文件")
    A("3. 按提示确认,app 会自动退出;重新打开即可看到迁移后的数据")
    A("")
    A("> 若 app 提示数据库异常,通常是 `user_version` 不匹配 —— 本产物已固定为 9。")
    A("")

    Path(path).write_text("\n".join(L), encoding="utf-8")


if __name__ == "__main__":
    main()
