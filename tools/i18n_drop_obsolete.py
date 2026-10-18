#!/usr/bin/env python3
"""删除已不存在于源码的词条（i18n_translate.py 的 --prune 无法处理前缀相同的词条）"""
import io
import re

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()

targets = [
    "'Please review before starting the service': '启动服务前请先确认以下风险',\n",
    "'Set a secret in the configuration, otherwise the API is unauthenticated.':\n        '请在配置中设置密钥，否则 API 将无需认证。',\n",
]

removed = 0
for item in targets:
    if item in t:
        t = t.replace(item, '', 1)
        removed += 1
        print('已删除词条:', item.split(':')[0])
    else:
        # 兜底：用正则匹配「键: 值」可能跨行的写法
        m = re.search(r"\s*'%s':\s*\n?\s*'[^']*',\n" % re.escape(item.split(':')[0].strip("'")), t)
        if m:
            t = t[:m.start()] + '\n' + t[m.end():]
            removed += 1
            print('已删除词条（正则）:', item.split(':')[0])
        else:
            print('未找到:', item.split(':')[0])

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('共删除', removed, '条')
