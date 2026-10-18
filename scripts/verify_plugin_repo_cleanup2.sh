#!/bin/sh
# 收尾（二）：清掉仓库缓存，确认系统回到原状
set -u

echo "########## 1. 仓库缓存位置 ##########"
ls -la /var/db/pkg/repos/ 2>/dev/null

echo
echo "########## 2. 删除本插件的仓库缓存 ##########"
rm -rf /var/db/pkg/repos/os-mihomo
ls -la /var/db/pkg/repos/ 2>/dev/null

echo
echo "########## 3. 再刷新一次索引 ##########"
pkg update 2>&1 | tail -5

echo
echo "########## 4. 现在的可见性 ##########"
echo -n "pkg search  : "; pkg search -q os-mihomo 2>&1 | tr '\n' ' '; echo
echo -n "rquery 本仓库: "; pkg rquery -r os-mihomo '%n %v' 'os-mihomo' 2>&1 | head -2 | tr '\n' ' '; echo
echo "插件页面数据源中的 mihomo："
configctl firmware remote 2>&1 | grep -i mihomo || echo "  (无)"

echo
echo "########## 5. 清单内三个安装脚本的语法检查 ##########"
PKG=/usr/local/opnsense/_bak/pkgbuild/dist/os-mihomo.pkg
python3 - "$PKG" <<'PY'
import subprocess, sys, re
pkg = sys.argv[1]
raw = subprocess.run(['tar','-xOf',pkg,'+MANIFEST'], capture_output=True, text=True).stdout
for name in ('post-install','pre-deinstall','post-deinstall'):
    m = re.search(r'"%s":\s*<<EOS\n(.*?)\nEOS' % re.escape(name), raw, re.S)
    if not m:
        print('  %-16s 未找到' % name); continue
    body = m.group(1)
    open('/tmp/script-check.sh','w').write(body)
    rc = subprocess.run(['sh','-n','/tmp/script-check.sh']).returncode
    print('  %-16s %d 行, sh -n -> %s' % (name, body.count('\n')+1, 'OK' if rc == 0 else 'FAIL(%d)' % rc))
PY
rm -f /tmp/script-check.sh

echo
echo "########## 6. 保留物 ##########"
echo "· 仓库目录 : /usr/local/opnsense/_repo/$(env -u ABI pkg config ABI)/"
du -sh "/usr/local/opnsense/_repo" 2>/dev/null
echo "· 仓库配置 : /usr/local/etc/pkg/repos/os-mihomo.conf（enabled: no）"
cat /usr/local/etc/pkg/repos/os-mihomo.conf
echo "· 构建目录 : /usr/local/opnsense/_bak/pkgbuild/（含 dist/ 与 dist/repo/）"
ls -1 /usr/local/opnsense/_bak/pkgbuild/dist/
