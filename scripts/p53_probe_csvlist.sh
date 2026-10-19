#!/bin/sh
set -u
echo "########## CSVListField / BaseListField ##########"
sed -n '28,200p' /usr/local/opnsense/mvc/app/models/OPNsense/Base/FieldTypes/CSVListField.php | sed 's/^/  /'
echo "  ---- BaseListField（关键部分） ----"
grep -n -A18 'function __toString\|function setValue\|function getNodeData\|internalMask' /usr/local/opnsense/mvc/app/models/OPNsense/Base/FieldTypes/BaseListField.php | head -60 | sed 's/^/  /'

echo
echo "########## getFormData / saveFormToEndpoint ##########"
python3 - <<'PY'
import io, re
t = io.open('/usr/local/opnsense/www/js/opnsense.js', encoding='utf-8', errors='replace').read()
for name in ('function getFormData', 'function saveFormToEndpoint'):
    m = re.search(re.escape(name), t)
    if m:
        print('  ===== %s =====' % name)
        seg = t[m.start(): m.start()+1300]
        for line in seg.splitlines():
            print('  ' + line)
        print()
PY
