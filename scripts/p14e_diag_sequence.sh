#!/bin/sh
# 诊断：OPNsense 如何给规则排序（sequence 语义）+ 自动默认放行规则从哪来
set -u
F=/usr/local/etc/inc/filter.inc
echo "########## 1. sequence 相关逻辑 ##########"
grep -n 'sequence' $F | head -20 | sed 's/^/  /'

echo
echo "########## 2. 自动默认放行规则（Default allow ...） ##########"
grep -rn "Default allow" /usr/local/etc/inc/*.inc 2>/dev/null | head -5 | sed 's/^/  /'
grep -n -B3 -A12 "function filter_core_rules\|default allow" $F | head -40 | sed 's/^/  /'

echo
echo "########## 3. 排序在哪里做的 ##########"
grep -rn 'usort\|uasort\|sort_by' $F /usr/local/etc/inc/filter.lib.inc 2>/dev/null | head -10 | sed 's/^/  /'
grep -n -A12 'function filter_sort' /usr/local/etc/inc/*.inc 2>/dev/null | head -30 | sed 's/^/  /'
