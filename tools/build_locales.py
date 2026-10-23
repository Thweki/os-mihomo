#!/usr/bin/env python3
"""Build a plugin-owned gettext domain. Never edit the system OPNsense.mo."""
from pathlib import Path
import gettext
import re
from extract_strings import collect
from mo_editor import read_po, write_mo

ROOT = Path(__file__).resolve().parent.parent


def build(check=False):
    strings = collect()
    for po in sorted((ROOT / 'locales').glob('*.po')):
        catalog = {k: v for k, v in read_po(po).items() if k in strings and v}
        for key, value in catalog.items():
            if sorted(re.findall(r'%(?:\d+\$)?[sd]', key)) != sorted(re.findall(r'%(?:\d+\$)?[sd]', value)):
                raise ValueError(f'{po.name}: placeholder mismatch: {key}')
        destination = ROOT / 'src/usr/local/opnsense/mvc/app/models/OPNsense/Mihomo/Locale' / po.stem / 'LC_MESSAGES/os-mihomo.mo'
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not check:
            write_mo(destination, catalog, f'Language: {po.stem}\nContent-Type: text/plain; charset=UTF-8\n')
        with destination.open('rb') as stream:
            translated = gettext.GNUTranslations(stream)
        assert all(translated.gettext(key) == value for key, value in catalog.items())
        print(f'{po.stem}: {len(catalog)} plugin translations verified')


if __name__ == '__main__':
    import sys
    build('--check' in sys.argv)
