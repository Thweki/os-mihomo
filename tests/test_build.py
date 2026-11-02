#!/usr/bin/env python3
"""Portable archive reproducibility/metadata checks, no package installation."""
import importlib.util
import os
from pathlib import Path
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('archive', ROOT / 'tools/reproducible_archive.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as directory:
    scratch = Path(directory)
    source = scratch / 'tree'
    (source / 'usr/local/etc').mkdir(parents=True)
    (source / 'usr/local/etc/example').write_bytes(b'example\n')
    (source / '+MANIFEST').write_text('manifest\n', encoding='utf-8')
    (source / '+COMPACT_MANIFEST').write_text('compact\n', encoding='utf-8')
    module.archive(source, scratch / 'first.gz', 1234567890, True)
    for path in source.rglob('*'):
        os.utime(path, (1800000000, 1800000000))
    module.archive(source, scratch / 'second.gz', 1234567890, True)
    assert (scratch / 'first.gz').read_bytes() == (scratch / 'second.gz').read_bytes()
    with tarfile.open(scratch / 'first.gz') as tar:
        entries = tar.getmembers()
        assert [entry.name for entry in entries] == ['+COMPACT_MANIFEST', '+MANIFEST', '/usr/local/etc/example']
        assert all(entry.uid == entry.gid == 0 and entry.mtime == 1234567890 for entry in entries)
        assert tar.extractfile('/usr/local/etc/example').read() == b'example\n'
print('Deterministic archive and package metadata tests passed.')
