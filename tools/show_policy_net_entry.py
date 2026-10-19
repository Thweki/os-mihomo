#!/usr/bin/env python3
"""打印 policy_net.php 的 apply 入口段（staging 解析 + 各步骤顺序）"""
import io

t = io.open('src/usr/local/opnsense/scripts/mihomo/policy_net.php', encoding='utf-8').read()
i = t.find('$action = $argv[1]')
print(t[max(0, i - 1500):i + 1800])
