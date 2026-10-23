#!/usr/bin/env python3
"""Quote translated Volt expressions as JSON, including apostrophes and line breaks."""
import re
from pathlib import Path


def convert(source):
    def script(match):
        expressions = []
        def protect(tag):
            expressions.append(tag.group())
            return f'__VOLT_{len(expressions)-1}__'
        text = re.sub(r'\{\{.*?\}\}', protect, match.group(2), flags=re.S)
        result, pos = [], 0
        while pos < len(text):
            if text.startswith('//', pos) or text.startswith('/*', pos):
                end = text.find('\n' if text.startswith('//', pos) else '*/', pos + 2)
                end = len(text) if end < 0 else end + (1 if text.startswith('//', pos) else 2)
                result.append(text[pos:end]); pos = end; continue
            quote = text[pos]
            if quote not in "'\"":
                result.append(quote); pos += 1; continue
            end = pos + 1
            while end < len(text):
                if text[end] == '\\': end += 2; continue
                if text[end] == quote: break
                end += 1
            value = text[pos + 1:end]
            pieces = re.split(r'(__VOLT_\d+__)', value)
            if any(piece.startswith('__VOLT_') and 'lang._(' in expressions[int(piece[7:-2])] for piece in pieces):
                parts = []
                for piece in pieces:
                    if piece.startswith('__VOLT_') and 'lang._(' in expressions[int(piece[7:-2])]:
                        expr = expressions[int(piece[7:-2])]
                        parts.append(expr[:-2].rstrip() + ' | json_encode }}')
                    elif piece:
                        parts.append(quote + piece + quote)
                result.append('(' + ' + '.join(parts) + ')')
            else: result.append(text[pos:end+1])
            pos = end + 1
        output = ''.join(result)
        for index, expression in enumerate(expressions):
            output = output.replace(f'__VOLT_{index}__', expression)
        return match.group(1) + output + match.group(3)
    return re.sub(r'(<script\b[^>]*>)(.*?)(</script>)', script, source, flags=re.S)


if __name__ == '__main__':
    for path in Path('src/usr/local/opnsense/mvc/app/views/OPNsense/Mihomo').glob('*.volt'):
        path.write_text(convert(path.read_text(encoding='utf-8')), encoding='utf-8', newline='\n')
