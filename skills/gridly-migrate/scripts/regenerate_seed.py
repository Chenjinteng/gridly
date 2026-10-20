#!/usr/bin/env python3
# 从 gridly 源码重新生成 references/seed_data.json
#
# 用法(在 gridly 仓库内跑):
#   python3 skills/gridly-migrate/scripts/regenerate_seed.py \
#       --repo ~/Documents/Projects/gridly-1.X \
#       --out skills/gridly-migrate/references/seed_data.json
#
# 为什么需要它:
#   系统预置分类/资产的 icon / color 来自 default_categories.dart / default_assets.dart,
#   颜色是 AppCategory token(可能是 AppStatus.warning / AppBrand.gold 这类别名),
#   手工抄进 JSON 容易抄错 —— 这个脚本从源码解析,保证与 app 一致。
#
# schema 升级后(加/删/改系统分类)必须重跑一次。

import argparse
import json
import re
import sys
from pathlib import Path

CATEGORY_GROUPS = ["expense", "income", "investment", "benefit",
                   "receivable", "other", "balanceAdjust"]


def resolve_colors(colors_src):
    """把 AppCategory token 解析成 0xAARRGGBB 整数(支持类别名,如 AppStatus.warning)"""
    consts = {}
    for m in re.finditer(r"static const Color (\w+)\s*=\s*([^;]+);", colors_src):
        consts[m.group(1)] = m.group(2).strip()

    def resolve(token, depth=0):
        if depth > 6:
            return None
        expr = consts.get(token)
        if expr is None:
            return None
        m = re.search(r"0x[0-9A-Fa-f]{8}", expr)
        if m:
            return int(m.group(0), 16)
        m2 = re.fullmatch(r"(\w+)\.(\w+)", expr)
        if m2:
            return resolve(m2.group(2), depth + 1)
        return None

    return resolve


def parse_categories(src):
    cats = []
    for group in CATEGORY_GROUPS:
        m = re.search(
            r"static const List<DefaultCategory> " + group + r" = \[(.*?)\n  \];",
            src, re.S)
        if not m:
            continue
        for block in re.findall(r"DefaultCategory\((.*?)\n    \)", m.group(1), re.S):
            name = re.search(r"name: '([^']+)'", block)
            icon = re.search(r"icon: '([^']+)'", block)
            color = re.search(r"color: AppCategory\.(\w+)", block)
            ctype = re.search(r"type: '([^']+)'", block)
            order = re.search(r"sortOrder: (\d+)", block)
            if not (name and icon and color and ctype and order):
                sys.exit(f"解析分类失败:{block[:120]}")
            cats.append(dict(
                name=name.group(1), icon=icon.group(1),
                color_token=color.group(1), type=ctype.group(1),
                sort_order=int(order.group(1))))
    return cats


def parse_assets(src):
    assets = []
    for block in re.findall(r"DefaultAsset\((.*?)\n    \),", src, re.S):
        name = re.search(r"name: '([^']+)'", block)
        atype = re.search(r"type: '([^']+)'", block)
        icon = re.search(r"icon: '([^']+)'", block)
        color = re.search(r"color: (0x[0-9A-Fa-f]+)", block)
        order = re.search(r"displayOrder: (\d+)", block)
        isdef = re.search(r"isDefault: (\w+)", block)
        if not (name and atype and icon and color and order):
            sys.exit(f"解析资产失败:{block[:120]}")
        assets.append(dict(
            name=name.group(1), type=atype.group(1), icon=icon.group(1),
            color=int(color.group(1), 16), display_order=int(order.group(1)),
            is_default=1 if (isdef and isdef.group(1) == "true") else 0))
    return assets


def parse_hash_palette(src):
    m = re.search(r"static const List<int> hashPalette = \[(.*?)\];", src, re.S)
    if not m:
        return []
    body = m.group(1)
    out = []
    for line in body.split("\n"):
        line = line.split("//")[0]
        mm = re.search(r"0x[0-9A-Fa-f]{8}", line)
        if mm:
            out.append(int(mm.group(0), 16))
    return out


def parse_icon_keys(src):
    m = re.search(r"static const Map<String, IconData> map = \{(.*?)\n  \};", src, re.S)
    if not m:
        return []
    body = m.group(1)
    out = []
    for line in body.split("\n"):
        line = line.split("//")[0]
        mm = re.search(r"'([a-z0-9_]+)':\s*Icons\.", line)
        if mm:
            out.append(mm.group(1))
    return out


def main():
    ap = argparse.ArgumentParser(description="从 gridly 源码重新生成 seed_data.json")
    ap.add_argument("--repo", required=True, help="gridly 仓库根目录")
    ap.add_argument("--out", required=True, help="输出 seed_data.json 路径")
    args = ap.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    cats_src = (repo / "lib/shared/constants/default_categories.dart").read_text(encoding="utf-8")
    assets_src = (repo / "lib/core/database/seeds/default_assets.dart").read_text(encoding="utf-8")
    colors_src = (repo / "lib/core/theme/app_colors.dart").read_text(encoding="utf-8")

    resolve = resolve_colors(colors_src)
    cats = parse_categories(cats_src)
    for c in cats:
        v = resolve(c.pop("color_token"))
        if v is None:
            sys.exit(f"颜色 token 解析失败: {c['name']}")
        c["color"] = v

    seed = {
        "_note": "gridly app 系统预置数据,权威来源 release/1.0 分支 "
                 "lib/shared/constants/default_categories.dart + lib/core/database/seeds/default_assets.dart。"
                 "由 scripts/regenerate_seed.py 生成,勿手改。",
        "categories": cats,
        "assets": parse_assets(assets_src),
        "hash_palette": parse_hash_palette(colors_src),
        "icon_map_keys": parse_icon_keys(cats_src),
    }

    out = Path(args.out).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(seed, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"已生成 {out}")
    print(f"  categories = {len(seed['categories'])}, assets = {len(seed['assets'])}, "
          f"hash_palette = {len(seed['hash_palette'])}, icon_map_keys = {len(seed['icon_map_keys'])}")


if __name__ == "__main__":
    main()
