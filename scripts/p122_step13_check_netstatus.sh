#!/bin/sh
# 最后确认：netstatus 的网关字段取值
set -u
configctl mihomo policy-net-check | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('device                :', d.get('device'), '| up:', d.get('device_up'))
print('interface             :', d.get('interface'))
print('gateway present       :', d.get('gateway_present'))
print('gateway configured ip :', repr(d.get('gateway_ip_configured')))
print('tun peer (detected)   :', d.get('gateway_ip'))
print('rules                 :', [r.get('interface') for r in (d.get('rules') or [])])
"
