# CI/CD

Every push, pull request and manual run executes `.github/workflows/ci.yml`:

1. Check the publication file list, sample credentials, PHP syntax, XML, translation catalogs, JavaScript encoding, traffic calculations, read-only runtime parsers and maintained shell scripts.
2. Build and inspect the package in an isolated FreeBSD 15.1 amd64 VM. Package hooks are not executed.
3. Upload `os-mihomo.pkg`, `os-mihomo-repository.tar.gz`, `SHA256SUMS` and `package-files.txt`. Artifacts are retained for 14 days.

Tags named `v<version>` must match Makefile's VERSION. A successful tag build creates a GitHub Release **draft** containing the artifacts. Review it before publishing. Branch builds do not create releases. No workflow connects to or deploys to a router.

All Actions are pinned to commit SHAs. Default permissions are read-only; only the release job receives `contents: write`. Checkout does not persist credentials. Dependabot checks Action updates weekly.

```sh
python3 tools/validate.py
# On FreeBSD, build without installing:
sh scripts/ci_build.sh
```

The repository archive contains ABI-specific package metadata. To host it, extract it to a static server and replace the URL in its client configuration template. A hosted package repository is not provisioned by this workflow. SHA-256 files detect download corruption; independent release signing is not configured.

Local instructions, work logs, original screenshots, device exports and one-off diagnostics are excluded from publication. Only the three reviewed, sanitized README images in `docs/assets/` are allowed, with exact SHA-256 checksums pinned in `tools/check_publication.py`. Replacing an image requires a new visual privacy review and checksum update; text scanning cannot detect sensitive content inside image pixels.

CI rejects tracked files that match `.gitignore`, unexpected files, private host addresses, home-directory paths, private keys and token patterns. Distributed configuration accepts only documented example credentials.
