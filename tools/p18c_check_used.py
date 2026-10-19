#!/usr/bin/env python3
"""检查哪些词条还在源码里被引用（用于清理废弃词条）"""
import io
import os

keys = [
    'Each item has a',
    'Every item is set to',
    'Let the page write every item',
    'Tick nothing',
    'Nothing is written to any file',
    'Tick everything',
    'Will be written',
    'Tick "leave alone" = this plugin never writes that item',
    'leave alone',
]
hits = {k: [] for k in keys}
for root, dirs, files in os.walk('src'):
    for f in files:
        if f.endswith(('.php', '.volt', '.xml')):
            p = os.path.join(root, f)
            t = io.open(p, encoding='utf-8', errors='replace').read()
            for k in keys:
                if k in t:
                    hits[k].append(os.path.basename(p))
for k, v in hits.items():
    print('%-58s %s' % (k[:56], ', '.join(v) if v else '(未使用)'))
