#!/usr/bin/env python3
"""把 settings.xml 中 base_form 不支持的 <type>boolean</type> 修正为 <type>checkbox</type>。

form_input_tr.volt（base_form 的行渲染器）不识别 boolean，会导致该字段完全不渲染输入控件；
<type>boolean</type> 只在 grid/dialog 渲染器里有意义。
"""
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "src/usr/local/opnsense/mvc/app/controllers/OPNsense/Mihomo/forms/settings.xml"
text = path.read_text(encoding="utf-8")
before = text.count("<type>boolean</type>")
text = text.replace("<type>boolean</type>", "<type>checkbox</type>")
path.write_text(text, encoding="utf-8", newline="\n")
print(f"replaced {before} occurrence(s) of <type>boolean</type> with <type>checkbox</type>")
