#!/usr/bin/env python3
"""Write deterministic package/repository tar.gz files without running hooks."""
import argparse
import gzip
import os
from pathlib import Path
import tarfile


def archive(root, output, epoch, package=False):
    root = Path(root).resolve()
    files = sorted(path for path in root.rglob('*') if path.is_file())
    if package:
        files.sort(key=lambda path: (0 if path.name == '+COMPACT_MANIFEST' else
                                    1 if path.name == '+MANIFEST' else 2,
                                    path.relative_to(root).as_posix()))
    with Path(output).open('wb') as raw:
        # An empty filename and fixed gzip timestamp remove host/time variation.
        with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as compressed:
            with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as tar:
                for path in files:
                    if path.is_symlink():
                        raise ValueError(f'Symlink not supported: {path}')
                    relative = path.relative_to(root).as_posix()
                    name = '/' + relative if package and relative.startswith(('etc/', 'usr/')) else relative
                    entry = tarfile.TarInfo(name)
                    entry.size = path.stat().st_size
                    entry.mode = path.stat().st_mode & 0o777
                    entry.uid = entry.gid = 0
                    entry.uname, entry.gname = 'root', 'wheel'
                    entry.mtime = epoch
                    with path.open('rb') as source:
                        tar.addfile(entry, source)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root')
    parser.add_argument('output')
    parser.add_argument('--package', action='store_true')
    parser.add_argument('--epoch', type=int, default=int(os.environ.get('SOURCE_DATE_EPOCH', '0')))
    args = parser.parse_args()
    if args.epoch < 0:
        parser.error('epoch must be nonnegative')
    archive(args.root, args.output, args.epoch, args.package)
