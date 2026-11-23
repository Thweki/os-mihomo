#!/bin/sh
# Publish one verified release package from the workflow's private staging area.
set -eu
umask 077
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="$root/work/pkg-feed"
version=$1
url=$2
key="$work/signing.key"
public_key="$root/packaging/freebsd/pkg-feed.pub"
abi=$(pkg config ABI)
[ "$abi" = 'FreeBSD:15:amd64' ]
trap 'rm -f "$key"' EXIT HUP INT TERM

ABI="$abi" VERSION="$version" BASE_URL="$url" REQUIRE_SIGNED=yes \
    DISTDIR="$work/input" OUTDIR="$work/generated" \
    REPO_SIGNING_KEY="$key" REPO_PUBLIC_KEY="$public_key" \
    sh "$root/scripts/make_repo.sh"
rm -f "$key"

install -d -m 0755 "$work/public"
mkdir -p "$work/check/repos" "$work/check/db" "$work/check/cache"
feed="$work/public/freebsd15-amd64"
mv "$work/generated/$abi" "$feed"
test -f "$feed/meta.conf"
test -f "$feed/os-mihomo-$version.pkg"
cmp "$work/input/os-mihomo.pkg" "$feed/os-mihomo-$version.pkg"

check="$work/check"
cat > "$check/repos/feed.conf" <<EOF
os-mihomo: {
  url: "file://$feed",
  signature_type: "pubkey",
  pubkey: "$public_key",
  enabled: yes
}
EOF
printf 'REPOS_DIR: ["%s/repos"]\n' "$check" > "$check/pkg.conf"
pkg -C "$check/pkg.conf" -R "$check/repos" \
    -o PKG_DBDIR="$check/db" -o PKG_CACHEDIR="$check/cache" update -f
advertised=$(pkg -C "$check/pkg.conf" -R "$check/repos" \
    -o PKG_DBDIR="$check/db" -o PKG_CACHEDIR="$check/cache" rquery '%n %v %o')
[ "$advertised" = "os-mihomo $version opnsense/os-mihomo" ]
printf 'Verified signed catalogue contains exactly os-mihomo %s\n' "$version"
