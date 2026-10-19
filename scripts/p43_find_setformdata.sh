#!/bin/sh
set -u
echo "########## 谁定义 setFormData / getFormData ##########"
grep -rln 'setFormData' /usr/local/opnsense/www/js/ /usr/local/www/ 2>/dev/null | sed 's/^/  /'
echo
grep -rn "setFormData\s*[=(]" /usr/local/opnsense/www/js/*.js 2>/dev/null | head -5 | sed 's/^/  /'
echo
F=$(grep -rln 'function setFormData\|setFormData *= *function' /usr/local/opnsense/www/js/ /usr/local/www/ 2>/dev/null | head -1)
echo "  定义文件: ${F:-未找到}"
[ -n "${F:-}" ] && python3 - "$F" <<'PY'
import io,re,sys
p=sys.argv[1]
t=io.open(p,encoding='utf-8',errors='replace').read()
m=re.search(r'(function\s+setFormData|setFormData\s*=\s*function)', t)
print(t[m.start():m.start()+3400] if m else 'no match')
PY
