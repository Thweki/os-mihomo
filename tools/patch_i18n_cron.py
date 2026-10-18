#!/usr/bin/env python3
"""补 ④ 相关词条"""
import io

p = 'tools/i18n_translate.py'
t = io.open(p, encoding='utf-8').read()
anchor = "    'TUN off': 'TUN 未启用',"
new = """    'TUN off': 'TUN 未启用',
    # ---- 订阅自动更新（④）----
    'Auto update': '自动更新',
    'Create a scheduled task for the subscription update.': '创建定时任务执行订阅更新。',
    'Interval': '间隔',
    'How often the scheduled task runs.': '定时任务的执行频率。',
    'Every 6 hours': '每 6 小时',
    'Every 12 hours': '每 12 小时',
    'Daily': '每天',
    'Update the subscription on a schedule.': '按计划更新订阅。',
    'Scheduled task enabled: subscription update (%s).': '定时任务已启用：订阅更新（%s）。',
    'Scheduled task removed: subscription update.': '定时任务已删除：订阅更新。',
    'Scheduled task could not be updated: %s': '定时任务更新失败：%s',
"""
if anchor not in t:
    raise SystemExit('anchor not found')
t = t.replace(anchor, new, 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print('i18n 已补 ④ 词条')
