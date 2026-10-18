#!/bin/sh
# 收尾验证：仓库关闭后系统是否回到原状 + 清单脚本语法检查
set -u

echo "########## 1. plugin.sh 的语义 ##########"
cat /usr/local/opnsense/scripts/firmware/plugin.sh
echo "--- 对照：已由插件管理器安装的 os-ttyd ---"
configctl firmware plugin os-ttyd 2>&1 | head -2 || true
echo "--- 未安装的 os-mihomo ---"
configctl firmware plugin os-mihomo 2>&1 | head -2 || true

echo
echo "########## 2. 关闭仓库后 pkg 是否仍会看到它 ##########"
grep -n 'enabled' /usr/local/etc/pkg/repos/os-mihomo.conf
echo "--- pkg search ---"
pkg search os-mihomo 2>&1 | head -5
echo "--- pkg rquery（显式指定仓库） ---"
pkg rquery -r os-mihomo '%n %v' 'os-mihomo' 2>&1 | head -3

echo "--- 缓存目录 ---"
ls -la /var/db/pkg/ | head -12
ls -la /var/cache/pkg/ 2>/dev/null | head -6

echo
echo "########## 3. 清掉该仓库的本地缓存（如果还在） ##########"
for f in /var/db/pkg/repo-os-mihomo* /var/cache/pkg/os-mihomo*; do
    [ -e "$f" ] && { echo "  删除 $f"; rm -rf "$f"; }
done
echo "--- 清理后 ---"
pkg rquery -r os-mihomo '%n %v' 'os-mihomo' 2>&1 | head -3 || echo "  (已不可用)"

echo
echo "########## 4. 确认启用的仓库列表没变 ##########"
pkg -vv 2>/dev/null | awk '/^Repositories:/,/^$/' | grep -E '^\s{2}\S+:|enabled' | head -20

echo
echo "########## 5. 插件页面数据源里只剩上游那条 ##########"
configctl firmware remote 2>&1 | grep -i mihomo || echo "(没有 mihomo)"

echo
echo "########## 6. 清单内三个安装脚本的语法检查 ##########"
PKG=/usr/local/opnsense/_bak/pkgbuild/dist/os-mihomo.pkg
python3 - "$PKG" <<'PY'
import subprocess, sys, json, re
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
echo "########## 7. 保留物清单 ##########"
echo "· 仓库目录 : /usr/local/opnsense/_repo/$(env -u ABI pkg config ABI)/"
ls -la "/usr/local/opnsense/_repo/$(env -u ABI pkg config ABI)/" | tail -3
echo "· 仓库配置 : /usr/local/etc/pkg/repos/os-mihomo.conf（enabled: no）"
echo "· 构建目录 : /usr/local/opnsense/_bak/pkgbuild/"
