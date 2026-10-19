#!/usr/bin/env python3
"""打印 policy_net.php 的第 4b 步之后（网关/接口/自检/回滚）的代码，用于精确改造"""
import io

t = io.open('src/usr/local/opnsense/scripts/mihomo/policy_net.php', encoding='utf-8').read()
i = t.find('/* ---------------- 4b.')
print(t[i:i + 6000])
