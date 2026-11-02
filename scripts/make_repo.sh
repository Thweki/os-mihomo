#!/bin/sh
# os-mihomo —— 生成标准 OPNsense 插件仓库目录
#
# 产物布局（与 OPNsense 官方/第三方插件仓库一致，仓库按 ABI 分目录）：
#
#   dist/repo/<ABI>/
#     ├── os-mihomo-<版本>.pkg          插件包
#     ├── meta.conf / meta              仓库元数据（pkg 2.x 用 meta.conf）
#     ├── data.pkg / packagesite.pkg    仓库目录数据
#     └── os-mihomo.conf                客户端仓库配置模板
#
# 用法：
#   sh scripts/make_repo.sh                 # 用本机 ABI 生成到 dist/repo/
#   BASE_URL=https://example.com/mihomo sh scripts/make_repo.sh
#   OUTDIR=/srv/www/mihomo sh scripts/make_repo.sh
#
# 生成后把 <OUTDIR>/<ABI> 整个目录放到静态站点（或本机某个目录），
# 再到 OPNsense 上写一份 /usr/local/etc/pkg/repos/os-mihomo.conf 指向它，
# 之后「系统 > 固件 > 插件」里就能看到并安装/升级/卸载本插件。
set -eu
export LC_ALL=C TZ=UTC
umask 022

PKG_NAME="${PKG_NAME:-os-mihomo}"
REPO_NAME="${REPO_NAME:-os-mihomo}"
BASE_URL="${BASE_URL:-}"
REPO_SIGNING_KEY="${REPO_SIGNING_KEY:-}"
REPO_PUBLIC_KEY="${REPO_PUBLIC_KEY:-}"
REQUIRE_SIGNED="${REQUIRE_SIGNED:-no}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DISTDIR="${DISTDIR:-$SCRIPT_DIR/dist}"
OUTDIR="${OUTDIR:-$DISTDIR/repo}"

command -v pkg >/dev/null 2>&1 || { echo "error: 需要 pkg 命令（FreeBSD/OPNsense）" >&2; exit 1; }
[ -f "$DISTDIR/$PKG_NAME.pkg" ] || { echo "error: 找不到 $DISTDIR/$PKG_NAME.pkg，先执行 make package" >&2; exit 1; }

# 版本：优先用环境变量，其次读插件版本文件（与包内 product_version 一致）
if [ -z "${VERSION:-}" ]; then
    VERSION="$(sed -n 's/.*"product_version":"\([^"]*\)".*/\1/p' \
        "$SCRIPT_DIR/src/usr/local/opnsense/version/mihomo" 2>/dev/null | head -1)"
fi
[ -n "${VERSION:-}" ] || { echo "error: 无法确定版本号，请传 VERSION=" >&2; exit 1; }

# ABI：与 build.sh 一致，取本机 ABI（清掉外部 ABI 变量干扰）
ABI="${ABI:-$(env -u ABI pkg config ABI)}"
case "$ABI" in
    *:*) : ;;
    *) echo "error: ABI 看起来不合法：$ABI" >&2; exit 1 ;;
esac

REPO_DIR="$OUTDIR/$ABI"
case "$REQUIRE_SIGNED" in yes|no) ;; *) echo 'REQUIRE_SIGNED must be yes or no' >&2; exit 1;; esac
if [ -n "$REPO_SIGNING_KEY" ]; then
    [ -r "$REPO_SIGNING_KEY" ] && [ -r "$REPO_PUBLIC_KEY" ] || {
        echo 'Signing requires readable REPO_SIGNING_KEY and REPO_PUBLIC_KEY' >&2; exit 1;
    }
    # Match the configured public key before emitting a trusted client template.
    private_public=$(openssl rsa -in "$REPO_SIGNING_KEY" -pubout 2>/dev/null)
    expected_public=$(openssl pkey -pubin -in "$REPO_PUBLIC_KEY" -pubout 2>/dev/null)
    [ "$private_public" = "$expected_public" ] || { echo 'Signing key pair mismatch' >&2; exit 1; }
elif [ "$REQUIRE_SIGNED" = yes ] || [ -n "$REPO_PUBLIC_KEY" ]; then
    echo 'A signing key is required; refusing unsigned fallback' >&2; exit 1
fi
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"

PKG_FILE="$PKG_NAME-$VERSION.pkg"
cp "$DISTDIR/$PKG_NAME.pkg" "$REPO_DIR/$PKG_FILE"

echo "==> 生成仓库元数据（pkg repo）"
if [ -n "$REPO_SIGNING_KEY" ]; then
    pkg repo "$REPO_DIR" "rsa:$REPO_SIGNING_KEY" >/dev/null
    install -m 0644 "$REPO_PUBLIC_KEY" "$REPO_DIR/$REPO_NAME.pub"
    trust="signature_type: \"pubkey\", pubkey: \"/usr/local/etc/pkg/keys/$REPO_NAME.pub\","
else
    pkg repo "$REPO_DIR" >/dev/null
    trust='signature_type: "none",'
    echo 'Repository is unsigned; configure REPO_SIGNING_KEY and REPO_PUBLIC_KEY for production.' >&2
fi

URL="${BASE_URL:-<把本目录放到静态站点后填写 base URL>/$ABI}"
cat > "$REPO_DIR/$REPO_NAME.conf" <<EOF
# os-mihomo 插件仓库 —— 放到 OPNsense 的 /usr/local/etc/pkg/repos/ 下即可
#
#   url 指向本仓库目录（即包含 meta.conf 的那一层）。
#   可用形式：
#     · 静态站点   url: "https://example.com/mihomo/$ABI"
#     · 本机目录   url: "file:///usr/local/opnsense/_repo/$ABI"
#   改完后执行：pkg update
#   随后「系统 > 固件 > 插件」即可看到 os-mihomo。
$REPO_NAME: {
  url: "$URL",
  $trust
  enabled: no
}
EOF

echo
echo "==> 仓库目录：$REPO_DIR"
ls -la "$REPO_DIR"
echo
echo "==> 客户端配置（已写入 $REPO_DIR/$REPO_NAME.conf）："
cat "$REPO_DIR/$REPO_NAME.conf"
echo
echo "==> 安装路径（与插件管理器一致）："
echo "    pkg update && pkg install -y $PKG_NAME"
