#!/bin/sh
# FreeBSD CI only: transient keys and isolated pkg database; never installs.
set -eu
mkdir -p work
scratch=$(mktemp -d "$PWD/work/repo-signing.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
umask 077
openssl genrsa -out "$scratch/key" 2048 2>/dev/null
openssl rsa -in "$scratch/key" -pubout -out "$scratch/public" 2>/dev/null
abi=$(pkg config ABI)
REQUIRE_SIGNED=yes REPO_SIGNING_KEY="$scratch/key" REPO_PUBLIC_KEY="$scratch/public" \
    OUTDIR="$scratch/repository" sh scripts/make_repo.sh >/dev/null
if REQUIRE_SIGNED=yes REPO_SIGNING_KEY= REPO_PUBLIC_KEY= \
    OUTDIR="$scratch/refused" sh scripts/make_repo.sh >/dev/null 2>&1; then
    echo 'Unsigned fallback was accepted' >&2; exit 1
fi
mkdir -p "$scratch/repos" "$scratch/db" "$scratch/cache" "$scratch/rejected-db" "$scratch/rejected-cache"
cat > "$scratch/repos/test.conf" <<EOF
test: {
  url: "file://$scratch/repository/$abi",
  enabled: yes,
  signature_type: "pubkey",
  pubkey: "$scratch/public"
}
EOF
printf 'REPOS_DIR: ["%s/repos"]\n' "$scratch" > "$scratch/pkg.conf"
pkg -C "$scratch/pkg.conf" -R "$scratch/repos" \
    -o PKG_DBDIR="$scratch/db" -o PKG_CACHEDIR="$scratch/cache" update -f
pkg -C "$scratch/pkg.conf" -R "$scratch/repos" \
    -o PKG_DBDIR="$scratch/db" -o PKG_CACHEDIR="$scratch/cache" \
    rquery -r test '%n' | grep -Fxq os-mihomo
# A different public key must reject the same repository with a fresh database.
openssl genrsa -out "$scratch/wrong-key" 2048 2>/dev/null
openssl rsa -in "$scratch/wrong-key" -pubout -out "$scratch/public" 2>/dev/null
# pkg 2.8 can return zero after rejecting a signature and removing the catalogue.
# Verify rejection diagnostics AND the absence of an available package.
pkg -C "$scratch/pkg.conf" -R "$scratch/repos" \
    -o PKG_DBDIR="$scratch/rejected-db" -o PKG_CACHEDIR="$scratch/rejected-cache" \
    update -f > "$scratch/rejected.log" 2>&1 || true
if ! grep -Eq 'signature verification failure|Invalid signature' "$scratch/rejected.log"; then
    cat "$scratch/rejected.log"
    echo 'Wrong-key test did not reach signature verification' >&2; exit 1
fi
if pkg -C "$scratch/pkg.conf" -R "$scratch/repos" \
    -o PKG_DBDIR="$scratch/rejected-db" -o PKG_CACHEDIR="$scratch/rejected-cache" \
    rquery -r test '%n' 2>/dev/null | grep -Fxq os-mihomo; then
    echo 'Repository with an untrusted signing key was accepted' >&2; exit 1
fi
echo 'Signed repository accepted; wrong key and unsigned fallback rejected.'
