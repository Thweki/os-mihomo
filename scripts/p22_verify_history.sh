#!/bin/sh
# P22：历史重写后的收尾与核实
set -e
cd "$(dirname "$0")/.." || exit 1

echo "=== 1. 删除 filter-branch 留下的备份引用 ==="
for r in $(git for-each-ref --format='%(refname)' refs/original/); do
    git update-ref -d "$r"
    echo "  removed $r"
done
git reflog expire --expire=now --all
git gc --prune=now --quiet
echo "  done"

echo
echo "=== 2. 历史里还能搜到明文吗（应为 0） ==="
echo -n "  git log -S 命中提交数: "
git log --all -S'PASS="$(cat' --oneline | wc -l || true
echo -n "  明文串命中提交数: "
git log --all -S'sudo0rm0' --oneline | wc -l || true

echo
echo "=== 3. 全历史文件内容扫描（应为 0） ==="
hits=0
for c in $(git rev-list --all); do
    n=$(git grep -c 'sudo0rm0' "$c" 2>/dev/null | wc -l)
    hits=$((hits + n))
done
echo "  命中文件条目: $hits"

echo
echo "=== 4. 仓库现状 ==="
echo -n "  未提交改动: "
git status --porcelain | wc -l
echo "  最近提交:"
git log --oneline -6 | sed 's/^/    /'
echo -n "  入库文件数: "
git ls-files | wc -l
