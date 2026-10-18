#!/usr/bin/env python3
"""
os-mihomo —— 生成待补翻译清单

比对插件字符串与设备上 zh_CN 的 OPNsense.mo：
  · 已有译文 → 直接复用（打印出来供确认）
  · 缺失     → 写入 refs/zh_CN-missing.txt 供人工翻译

用法:
  python tools/i18n_gap.py --mo refs/zh_CN-OPNsense.mo --strings refs/plugin-strings.json \
                           --missing-out refs/zh_CN-missing.txt --present-out refs/zh_CN-present.txt
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from mo_editor import read_mo


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mo', required=True)
    parser.add_argument('--strings', required=True)
    parser.add_argument('--missing-out', required=True)
    parser.add_argument('--present-out', required=True)
    args = parser.parse_args()

    catalog = read_mo(args.mo)
    strings = json.loads(Path(args.strings).read_text(encoding='utf-8'))

    missing, present = [], []
    for msgid in sorted(strings):
        (present if msgid in catalog else missing).append(msgid)

    Path(args.missing_out).write_text('\n'.join(missing) + '\n', encoding='utf-8')
    Path(args.present_out).write_text(
        '\n'.join(f'{k}\t{catalog[k]}' for k in present) + '\n', encoding='utf-8'
    )

    print(f'插件字符串 : {len(strings)}')
    print(f'已有译文   : {len(present)}  -> {args.present_out}')
    print(f'待补翻译   : {len(missing)}  -> {args.missing_out}')
    return 0


if __name__ == '__main__':
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
