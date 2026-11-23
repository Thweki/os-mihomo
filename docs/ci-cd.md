# Build, validate and publish os-mihomo

[中文首页](../README.md) · [English home](../README.US.md) · [Installation guide](install.en.md)

Use this guide to work on the source, reproduce a release or run your own signed package feed. For a normal installation, follow the installation guide.

## Local development

The repository root is the plugin tree. `src/` mirrors the appliance paths. The MVC models, controllers and Volt views live under `src/usr/local/opnsense/mvc/app/`, with `/ui/mihomo/*` and `/api/mihomo/*` as the entry points. Backend scripts and configd actions live under `src/usr/local/opnsense/`. Package metadata, hooks and pinned [core](../packaging/freebsd/binary-source.json) and [Geo data](../packaging/freebsd/geodata-source.json) inputs are under `packaging/freebsd/`.

Run the portable checks with Python 3, Node.js, PHP CLI with SimpleXML and DOM, and a POSIX shell.

```sh
python3 tools/check_publication.py
python3 tools/validate.py
```

On FreeBSD 15 amd64, `make package` builds `dist/os-mihomo.pkg`. `make repo` also builds the catalogue under `dist/repo/<ABI>/`. Install test packages in a disposable OPNsense environment. [Installation checks](install.en.md#check-the-installation)

For localization, edit `locales/<locale>.po` using `locales/os-mihomo.pot` as the template. Run `python3 tools/build_locales.py` and then `python3 tools/build_locales.py --check`. Commit both the translation source and generated catalogue. The plugin uses its own gettext domain and falls back to system translations or English.

## What CI verifies

Every push, pull request and manual run executes `.github/workflows/ci.yml`:

1. Install explicit validation runtimes (Python 3.12, Node.js 24 and PHP 8.3 with SimpleXML) and pinned correctness linters. Check the publication allowlist and fixed third-party asset hashes, sample credentials, PHP syntax, XML, translation catalogs, JavaScript and maintained shell scripts. Run UI, runtime, configuration patch, transaction/failure/concurrency, API permission/result and deterministic archive fixture tests. Tests never use an appliance configuration.
2. In an isolated FreeBSD 15.1 amd64 VM, run PHP fixtures and build the package twice with separate staging directories. `cmp` must find identical package bytes. Run the bundled core with `-t` against synthetic valid and invalid YAML and representative subscription-generated block, flow and mixed layouts (audit B6). Downloads and installation are stubbed; TUN/DNS are disabled, with no service start. Inspect package metadata and ensure the package owns samples, not live configuration. Package hooks are not executed.
3. Exercise optional RSA repository signing with disposable keys and an isolated pkg database: the valid key must work, a different key must fail, and `REQUIRE_SIGNED=yes` must reject missing keys. Nothing is installed and CI keys are discarded.
4. Upload `os-mihomo.pkg`, `os-mihomo-repository.tar.gz`, `SHA256SUMS`, `package-files.txt` and `build-info.json`. Artifacts are retained for 14 days.

Tags named `v<version>` must match Makefile's VERSION. A successful tag build creates a GitHub Release **draft**. Branch builds do not create releases. No workflow connects to or deploys to a router.

All Actions are pinned to commit SHAs. Default permissions are read-only; only the tag release job receives `contents: write`, `id-token: write` and `attestations: write`. Checkout does not persist credentials. Dependabot checks Action updates weekly.

```sh
# Include CI correctness lint (install into an isolated virtual environment):
python3 -m venv work/ci-venv
work/ci-venv/bin/python -m pip install ruff==0.14.4 shellcheck-py==0.10.0.1
PATH="$PWD/work/ci-venv/bin:$PATH" work/ci-venv/bin/python tools/validate.py --lint
# FreeBSD only, with Python 3, PHP (including SimpleXML and DOM), Git and build tools:
sh scripts/ci_build.sh
```

`python3 tests/test_subscription.py` exercises the actual subscription shell offline,
without PHP or a core binary. It checks block and single-line flow mappings, field
order, nested fields, quoted commas, Unicode, indentationless lists, duplicate-name
filtering, template isolation, converter/fallback generation and rejected inputs.
It covers name selection, not general YAML scalar fidelity. The PHP installer is
stubbed only in this generator suite; `tests/test_writes.php` covers the real
installer. Use `--output-dir <directory>` to retain representative generated configs
for core validation. These fixtures also run in the portable validator, including
with `--frontend-only`.

Shell syntax checks use `sh -n` for maintained `.sh` files, POSIX shell shebangs (including extensionless service and CLI entrypoints and package hooks), and the shipped rc.conf/env snippets. ShellCheck runs the same files with error-level diagnostics only; Ruff checks `tools/` and `tests/` with `E9,F63,F7,F82` (syntax, invalid comparisons/control flow and undefined names). Neither linter applies fixes. Temporary fixtures verify discovery, parse-only behavior, rejection of broken extensionless scripts and shell/Python correctness errors, and acceptance of valid input.

Without PHP CLI, use `python3 tools/validate.py --frontend-only`; this skips PHP syntax and PHP fixtures. Without ShellCheck/Ruff, omit `--lint`: shell syntax and the other portable checks still run, and linter-dependent fixtures report explicit skips. CI always uses `--lint` with all runtimes installed, so missing linters fail validation. FreeBSD package, core and repository-signing checks require the VM and do not run in the portable harness.

## Reproduce and verify

`build.sh` sets `SOURCE_DATE_EPOCH` to the checked-out commit time unless explicitly supplied. The archive writer sorts paths and fixes uid/gid, owner names, file times and the gzip header. Staged file modes are normalized, including 0600 for configuration samples. Source checkout timestamps and staging locations are not archive inputs.

Each tree copy finishes a temporary tar archive before extraction, so a source read failure aborts packaging even if tar produced a readable partial archive. This requires temporary disk space for one uncompressed tree under `WORKDIR`. Portable `tests/test_packaging.py` fixtures run the build with a synthetic core and stubbed FreeBSD commands, checking failures in both copy stages and successful payload/sample preservation without downloads or package installation. They run through `tools/validate.py`; real pkg validation remains in the FreeBSD job.

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

## Use the project feed

The project publishes a signed FreeBSD 15 amd64 catalogue at `https://thweki.github.io/os-mihomo/freebsd15-amd64`. Its catalogue contains only `os-mihomo`. The OPNsense firmware manager lists new versions when it checks for updates. The administrator decides when to install them.

1. Obtain the public signing key and check that its SHA-256 is `a57255717f9840a63608b903afaee68e76af9ef25c1ff568f1e711c67a5af919` before installing it as `/usr/local/etc/pkg/keys/os-mihomo.pub`. [Key in the source repository](../packaging/freebsd/pkg-feed.pub) · [Key on the HTTPS feed](https://thweki.github.io/os-mihomo/freebsd15-amd64/os-mihomo.pub)
2. Review the [published repository template](https://thweki.github.io/os-mihomo/freebsd15-amd64/os-mihomo.conf). Its URL must match the feed above, its signature type must be `pubkey`, and its key path must match step 1. Save it as `/usr/local/etc/pkg/repos/os-mihomo.conf`, set `enabled: yes` for this feed, and keep the official OPNsense source enabled.
3. Check for updates under **System → Firmware → Status**, then install or upgrade `os-mihomo`. See the [upgrade and migration steps](install.en.md#upgrade-and-remove) if the package is already installed.

The feed uses GitHub Pages and the **Publish signed OPNsense package feed** workflow. Publishing a stable GitHub Release triggers the workflow. For the initial setup or a retry, run that workflow manually from `main`. It verifies the upstream release attestation and source, signs and tests a catalogue from the released package, and deploys it only if the release is still the latest. The signing key is kept in the encrypted Actions secret `MIHOMO_PKG_FEED_RSA_KEY_B64`. Rotate the client trust key before switching the signing key.

## Optional signed package repository

The default `make repo` build emits an **unsigned** repository and a disabled client template. To publish your own signed source, keep an RSA private key outside the checkout and web root, readable only by the signing account. Distribute the public key through an independently authenticated channel.

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

The script checks that both keys match, invokes `pkg repo` with RSA signing, and emits `signature_type: "pubkey"` and a public-key path. Any signing failure aborts. `REQUIRE_SIGNED=yes` prevents fallback to an unsigned source. The published directory contains the public key and no private key.

1. Publish the complete ABI directory over HTTPS. The client URL points to the directory that contains `meta.conf`.
2. On the appliance, install the authenticated key under `/usr/local/etc/pkg/keys/os-mihomo.pub`. Review the generated `os-mihomo.conf` and its URL, then install it under `/usr/local/etc/pkg/repos/` and set `enabled: yes` for this source. Keep the official OPNsense source enabled. Keep `signature_type: "pubkey"` for this feed.
3. Refresh the catalogue in **System → Firmware → Status**. If you need to diagnose catalogue discovery from the console, `pkg update -r os-mihomo` refreshes this feed and `pkg rquery -r os-mihomo '%n %v' os-mihomo` checks whether it advertises the expected version. Install from **System → Firmware → Plugins** after checking the origin. [Installation steps](install.en.md#install-through-the-plugin-manager)

For an isolated signing verification without changing client settings, build a package and run `sh tests/test_repository.sh` on a disposable FreeBSD machine. Production key rotation requires distributing the new public key before changing the hosted signatures. The implementation follows [pkg-repo(8)](https://man.freebsd.org/cgi/man.cgi?query=pkg-repo&sektion=8&format=html).

## Publication boundary

Local instructions, work logs, original screenshots, device exports and one-off diagnostics are excluded. Only the three reviewed, sanitized documentation images in `docs/assets/` are allowed, with exact SHA-256 checksums pinned in `tools/check_publication.py`. Replacing an image requires a new visual privacy review and checksum update.

CI rejects tracked files that match `.gitignore`, unexpected files, private host addresses, home-directory paths, private keys and token patterns. Distributed configuration accepts only documented example credentials. Production signing keys, locally downloaded test runtimes and generated outputs remain ignored.

## Network XML concurrency fixtures

`php tests/test_network.php` exercises overlapping core/plugin writers, stale revisions,
private unique backups and staging, inode-preserving persistence, guarded rollback,
Unbound round trips, and API lock release before synchronous configd calls. The tests
use temporary XML and a small core persistence double; they do not reload a firewall.
The network plan revision is carried through apply and each subsequent stage. Automatic
rollback refuses backups without a recorded revision, or any intervening configuration
save. Core persistence may reformat XML while preserving unrelated configuration nodes.

The Ubuntu validation and FreeBSD package jobs run the concurrency fixture. Check
the Actions run for the exact commit to see which checks passed.
