#!/usr/bin/env python3
"""打印 policy_net.php 的 apply 分支（看步骤顺序与退出点）"""
import io

t = io.open('src/usr/local/opnsense/scripts/mihomo/policy_net.php', encoding='utf-8').read()
i = t.find("if ($action === 'apply')")
print(t[i:i + 2600])
