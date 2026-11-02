# CI/CD

Every push, pull request and manual run executes `.github/workflows/ci.yml`:

1. Check the publication allowlist and fixed third-party asset hashes, sample credentials, PHP syntax, XML, translation catalogs, JavaScript and maintained shell scripts. Run UI, runtime, configuration patch, transaction/failure/concurrency, API permission/result and deterministic archive fixture tests. Tests never use an appliance configuration.
2. In an isolated FreeBSD 15.1 amd64 VM, run PHP fixtures and build the package twice with separate staging directories. `cmp` must find identical package bytes. Run the bundled core with `-t` against synthetic valid and invalid YAML (TUN/DNS disabled, no subscription or service start). Inspect package metadata and ensure the package owns samples, not live configuration. Package hooks are not executed.
3. Exercise optional RSA repository signing with disposable keys and an isolated pkg database: the valid key must work, a different key must fail, and `REQUIRE_SIGNED=yes` must reject missing keys. Nothing is installed and CI keys are discarded.
4. Upload `os-mihomo.pkg`, `os-mihomo-repository.tar.gz`, `SHA256SUMS`, `package-files.txt` and `build-info.json`. Artifacts are retained for 14 days.

Tags named `v<version>` must match Makefile's VERSION. A successful tag build creates a GitHub Release **draft**. Branch builds do not create releases. No workflow connects to or deploys to a router.

All Actions are pinned to commit SHAs. Default permissions are read-only; only the tag release job receives `contents: write`, `id-token: write` and `attestations: write`. Checkout does not persist credentials. Dependabot checks Action updates weekly.

```sh
python3 tools/check_publication.py
python3 tools/validate.py
# FreeBSD only, with Python 3, PHP (including SimpleXML), Git and build tools:
sh scripts/ci_build.sh
```

## Reproduce and verify

`build.sh` sets `SOURCE_DATE_EPOCH` to the checked-out commit time unless explicitly supplied. The archive writer sorts paths and fixes uid/gid, owner names, file times and the gzip header. Staged file modes are normalized, including 0600 for configuration samples. Source checkout timestamps and staging locations are not archive inputs.

The byte-for-byte reproducibility claim applies to `os-mihomo.pkg` built from identical source, pinned assets, build variables, Python/zlib toolchain and ABI. `build-info.json` records the commit/tree, dirty state, epoch, pinned input metadata, OS, Python/zlib/pkg versions and output hashes. It is an inventory, not a signature. The repository archive has deterministic outer packaging, but internal `pkg repo` catalogues/signatures may vary with pkg version or signing setup; CI does not claim byte-for-byte repository catalogue reproducibility. Toolchain changes can also change compressed package bytes; use the recorded versions when reproducing.

```sh
# Checkout the release commit in a clean working tree first.
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) sh scripts/ci_build.sh
sha256 -q dist/os-mihomo.pkg
# Compare with the release SHA256SUMS and build-info.json.
```

New tag workflows attest the package, repository archive, build record and checksum file using GitHub OIDC and Sigstore. Verify each downloaded artifact, and inspect the attested source commit and workflow identity before use:

```sh
gh attestation verify os-mihomo.pkg --repo Thweki/os-mihomo
gh attestation verify os-mihomo-repository.tar.gz --repo Thweki/os-mihomo
gh attestation verify build-info.json --repo Thweki/os-mihomo
gh attestation verify SHA256SUMS --repo Thweki/os-mihomo
```

This requires a successful run of the updated tag workflow and GitHub artifact-attestation support. A local build and older releases have no GitHub attestation unless one was separately generated. SHA-256 alone detects corruption, not publisher identity. See the official [GitHub attestation action](https://github.com/actions/attest) and [verification guide](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline).

## Optional signed package repository

The default build emits an **unsigned** repository and a disabled client template. A hosted source and production signing key are not provisioned. To publish a signed source, keep an RSA private key outside the checkout and web root, readable only by the signing account. Distribute the public key through an independently authenticated channel; downloading an unauthenticated key beside the repository does not establish trust.

```sh
# On a protected signing host; these are examples, not bundled credentials.
umask 077
openssl genrsa -out /secure/os-mihomo.key 4096
openssl rsa -in /secure/os-mihomo.key -pubout -out /secure/os-mihomo.pub

# BASE_URL is the full ABI-specific URL containing meta.conf.
REQUIRE_SIGNED=yes \
REPO_SIGNING_KEY=/secure/os-mihomo.key \
REPO_PUBLIC_KEY=/secure/os-mihomo.pub \
BASE_URL=https://packages.example.com/mihomo/FreeBSD:15:amd64 \
sh scripts/make_repo.sh
```

The script checks that both keys match, invokes `pkg repo` with RSA signing, and emits `signature_type: "pubkey"` and a public-key path. Any signing failure aborts; `REQUIRE_SIGNED=yes` prevents fallback to an unsigned source. It never copies the private key into the repository. Publish the ABI directory over HTTPS, install the authenticated public key at `/usr/local/etc/pkg/keys/os-mihomo.pub`, review the generated URL, then explicitly enable the client template. Do not change `signature_type` to bypass a verification failure.

For an isolated signing verification without changing client settings, build a package and run `sh tests/test_repository.sh` on a disposable FreeBSD machine. Production key rotation requires distributing the new public key before changing the hosted signatures. The implementation follows [pkg-repo(8)](https://man.freebsd.org/cgi/man.cgi?query=pkg-repo&sektion=8&format=html).

## Publication boundary

Local instructions, work logs, original screenshots, device exports and one-off diagnostics are excluded. Only the three reviewed, sanitized README images in `docs/assets/` are allowed, with exact SHA-256 checksums pinned in `tools/check_publication.py`. Replacing an image requires a new visual privacy review and checksum update; text scanning cannot detect sensitive pixels.

CI rejects tracked files that match `.gitignore`, unexpected files, private host addresses, home-directory paths, private keys and token patterns. Distributed configuration accepts only documented example credentials. Production signing keys, locally downloaded test runtimes and generated outputs remain ignored.
