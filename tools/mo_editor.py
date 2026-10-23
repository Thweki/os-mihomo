#!/usr/bin/env python3
"""
os-mihomo —— GNU gettext .mo 编辑器（纯 Python，无需 gettext 工具链）

OPNsense 用单一 gettext 域（defaultDomain=OPNsense，目录 /usr/local/share/locale），
每个语言一个 <locale>/LC_MESSAGES/OPNsense.mo。要让插件字符串显示中文，
只能把词条合并进这个文件。本脚本负责「可回滚、可复现」地做这件事。

用法：
  # 1) 列出 .mo 中已有的词条（可按前缀过滤）
  python tools/mo_editor.py dump <OPNsense.mo> [--filter "Active"]

  # 2) 检查某个 .po 里哪些词条在 .mo 中缺失（= 需要补的）
  python tools/mo_editor.py check <OPNsense.mo> <zh_CN.po>

  # 3) 把 .po 合并进 .mo，输出新文件（保留原有全部词条）
  python tools/mo_editor.py merge <OPNsense.mo> <zh_CN.po> -o <out.mo> [--stats]

  # 4) 校验：读取生成的 .mo，逐条确认 .po 里的键都有译文
  python tools/mo_editor.py verify <out.mo> <zh_CN.po>
"""
from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

MAGIC = 0x950412DE


# --------------------------------------------------------------------------- #
# .mo 读写
# --------------------------------------------------------------------------- #
def read_mo(path: str | Path) -> dict[str, str]:
    """读取 .mo，返回 {msgid: msgstr}（跳过空 msgid 的元数据条目）。"""
    data = Path(path).read_bytes()
    magic, = struct.unpack('<I', data[:4])
    if magic != MAGIC:
        # 允许字节序反转
        magic_be, = struct.unpack('>I', data[:4])
        if magic_be != MAGIC:
            raise ValueError(f'not a .mo file: {path}')
        endian = '>'
    else:
        endian = '<'

    _, nstrings, orig_off, trans_off = struct.unpack(f'{endian}IIII', data[4:20])
    result: dict[str, str] = {}
    for i in range(nstrings):
        o_len, o_off = struct.unpack(f'{endian}II', data[orig_off + i * 8: orig_off + i * 8 + 8])
        t_len, t_off = struct.unpack(f'{endian}II', data[trans_off + i * 8: trans_off + i * 8 + 8])
        msgid = data[o_off: o_off + o_len]
        msgstr = data[t_off: t_off + t_len]
        if msgid == b'':
            continue
        result[msgid.decode('utf-8')] = msgstr.decode('utf-8')
    return result


def write_mo(path: str | Path, catalog: dict[str, str], metadata: str = '') -> None:
    """写出 .mo（两遍构建：先算总长再定位，避免偏移量错位）。"""
    entries: list[tuple[bytes, bytes]] = []
    if metadata:
        entries.append((b'', metadata.encode('utf-8')))
    for key, value in sorted(catalog.items()):
        entries.append((key.encode('utf-8'), value.encode('utf-8')))

    # 第一遍：计算 msgid 表总长度，从而得出 msgstr 表基线
    ids = b''
    for msgid, _ in entries:
        ids += msgid + b'\x00'

    n = len(entries)
    orig_off = 7 * 4
    trans_off = orig_off + n * 8
    str_base = trans_off + n * 8

    # 第二遍：写字符串表与索引表
    id_offsets: list[tuple[int, int]] = []
    str_offsets: list[tuple[int, int]] = []
    strs = b''
    cursor = 0
    for msgid, _ in entries:
        id_offsets.append((len(msgid), str_base + cursor))
        cursor += len(msgid) + 1
    cursor = 0
    for _, msgstr in entries:
        str_offsets.append((len(msgstr), str_base + len(ids) + cursor))
        cursor += len(msgstr) + 1
    for _, msgstr in entries:
        strs += msgstr + b'\x00'

    out = struct.pack('<I', MAGIC)
    out += struct.pack('<I', 0)            # revision
    out += struct.pack('<I', n)
    out += struct.pack('<I', orig_off)
    out += struct.pack('<I', trans_off)
    out += struct.pack('<I', 0)            # hash table size
    out += struct.pack('<I', 0)            # hash table offset
    for length, off in id_offsets:
        out += struct.pack('<II', length, off)
    for length, off in str_offsets:
        out += struct.pack('<II', length, off)
    out += ids + strs
    Path(path).write_bytes(out)


# --------------------------------------------------------------------------- #
# .po 读取（只取 msgid/msgstr 对，忽略注释与复数形式）
# --------------------------------------------------------------------------- #
def read_po(path: str | Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    msgid = None
    msgstr = None
    mode = None

    def flush():
        nonlocal msgid, msgstr
        if msgid is not None and msgstr is not None:
            pid, pstr = unescape(msgid), unescape(msgstr)
            if pid != '':                 # 跳过 .po 头部（msgid 为空）
                entries[pid] = pstr
        msgid = msgstr = None

    for raw in Path(path).read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if line.startswith('#') or line == '':
            if line == '':
                flush()
            continue
        if line.startswith('msgid_plural') or line.startswith('msgstr['):
            mode = 'skip'
            continue
        if line.startswith('msgid '):
            if msgstr is not None:
                flush()
            msgid = line[6:].strip()
            mode = 'msgid'
        elif line.startswith('msgstr '):
            msgstr = line[7:].strip()
            mode = 'msgstr'
        elif line.startswith('"'):
            if mode == 'msgid':
                msgid = (msgid or '') + line
            elif mode == 'msgstr':
                msgstr = (msgstr or '') + line
    flush()
    return entries


def unescape(text: str) -> str:
    """把 .po 里带引号的字符串还原（去除外层引号并解转义）。"""
    parts = []
    buf = ''
    in_str = False
    i = 0
    while i < len(text):
        ch = text[i]
        if not in_str:
            if ch == '"':
                in_str = True
            i += 1
            continue
        if ch == '\\' and i + 1 < len(text):
            nxt = text[i + 1]
            buf += {'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\'}.get(nxt, nxt)
            i += 2
            continue
        if ch == '"':
            in_str = False
            parts.append(buf)
            buf = ''
            i += 1
            continue
        buf += ch
        i += 1
    if buf:
        parts.append(buf)
    return ''.join(parts)


# --------------------------------------------------------------------------- #
# 命令
# --------------------------------------------------------------------------- #
def cmd_dump(args) -> int:
    catalog = read_mo(args.mo)
    keys = sorted(catalog)
    if args.filter:
        keys = [k for k in keys if args.filter.lower() in k.lower()]
    print(f'# {args.mo}: {len(catalog)} 条词条（显示 {len(keys)}）')
    for k in keys:
        print(f'{k!r} -> {catalog[k]!r}')
    return 0


def cmd_check(args) -> int:
    catalog = read_mo(args.mo)
    wanted = read_po(args.po)
    missing = [k for k in sorted(wanted) if k not in catalog]
    present = [k for k in sorted(wanted) if k in catalog]
    print(f'.mo 词条总数 : {len(catalog)}')
    print(f'.po 词条总数 : {len(wanted)}')
    print(f'已存在（无需合并）: {len(present)}')
    print(f'缺失（需要合并）  : {len(missing)}')
    for k in missing:
        print(f'  MISSING  {k!r}')
    return 0


def cmd_merge(args) -> int:
    catalog = read_mo(args.mo)
    wanted = read_po(args.po)
    added, updated = 0, 0
    for k, v in wanted.items():
        if k not in catalog:
            added += 1
        elif catalog[k] != v:
            updated += 1
        catalog[k] = v
    metadata = 'os-mihomo plugin translations merged by tools/mo_editor.py'
    write_mo(args.out, catalog, metadata)
    if args.stats:
        print(f'原有词条      : {len(catalog) - added}')
        print(f'新增词条      : {added}')
        print(f'覆盖原有词条  : {updated}')
        print(f'输出          : {args.out}（共 {len(catalog)} 条）')
    return 0


def cmd_verify(args) -> int:
    catalog = read_mo(args.mo)
    wanted = read_po(args.po)
    bad = []
    for k, v in wanted.items():
        if catalog.get(k) != v:
            bad.append((k, catalog.get(k), v))
    if bad:
        print(f'FAIL: {len(bad)} 条不一致')
        for k, got, exp in bad[:10]:
            print(f'  {k!r}: got={got!r} want={exp!r}')
        return 1
    print(f'PASS: {len(wanted)} 条词条全部就位（共 {len(catalog)} 条）')
    return 0


def cmd_diff_core(args) -> int:
    """比较两个 .mo：确认「只增不改」（原有词条一律没被改写）"""
    old = read_mo(args.old)
    new = read_mo(args.new)
    overwritten = [k for k in old if old[k] != new.get(k)]
    added = [k for k in new if k not in old]
    print(f'  原有词条 {len(old)} 条 / 新增 {len(added)} 条 / 被改写 {len(overwritten)} 条')
    if overwritten:
        print('  被改写示例:')
        for k in overwritten[:5]:
            print(f'    {k!r}: {old[k]!r} -> {new.get(k)!r}')
        return 1
    print('  OK：只增不改')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description='GNU gettext .mo 编辑器（纯 Python）')
    sub = parser.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('dump'); p.add_argument('mo'); p.add_argument('--filter', default='')
    p.set_defaults(func=cmd_dump)

    p = sub.add_parser('check'); p.add_argument('mo'); p.add_argument('po')
    p.set_defaults(func=cmd_check)

    p = sub.add_parser('merge'); p.add_argument('mo'); p.add_argument('po')
    p.add_argument('-o', '--out', required=True); p.add_argument('--stats', action='store_true')
    p.set_defaults(func=cmd_merge)

    p = sub.add_parser('verify'); p.add_argument('mo'); p.add_argument('po')
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser('diff-core'); p.add_argument('old'); p.add_argument('new')
    p.set_defaults(func=cmd_diff_core)

    args = parser.parse_args()
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
