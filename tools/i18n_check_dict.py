#!/usr/bin/env python3
"""检查：还有哪些待翻译词条在字典里没有对应键"""
import io
import sys

sys.path.insert(0, 'tools')
import i18n_translate as T  # noqa: E402

D = None
for name in dir(T):
    v = getattr(T, name)
    if isinstance(v, dict) and len(v) > 100:
        D = v
        print('字典:', name, '条目:', len(v))
        break

if D is None:
    raise SystemExit('未找到字典')

mis = [l.rstrip('\n') for l in io.open('refs/zh_CN-missing.txt', encoding='utf-8') if l.strip()]
po_txt = io.open('locales/zh_CN.po', encoding='utf-8').read()

missing_from_dict = [m for m in mis if m not in D]
print()
print('== 字典里没有的键 (%d) ==' % len(missing_from_dict))
for m in missing_from_dict:
    in_po = ('msgid "' + m + '"') in po_txt
    print('  %-70s | 已在 .po: %s' % (repr(m)[:70], in_po))
