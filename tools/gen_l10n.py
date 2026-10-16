#!/usr/bin/env python3
"""Convert upstream adarkroom lang/<locale>/strings.js into adarkroom/l10n/<locale>.lua.
Usage: gen_l10n.py <adarkroom checkout> <locale>"""
import json, re, sys
src, loc = sys.argv[1], sys.argv[2]
# 纯离线：去掉云存档（Dropbox）、分享、应用商店/平台推广、交叉推广（Penrose）等联网功能的文案
ONLINE = re.compile(r"dropbox|get the app|app store|github|^ios\.?$|android|penrose|thrumming|inviting\. it would be so easy|^give in$|^share\.?$|signout|kickstarter", re.I)
s = open(f"{src}/lang/{loc}/strings.js", encoding="utf-8").read()
j = json.loads(s[s.index("(") + 1:s.rindex(")")])
def q(x): return '"' + x.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "") + '"'
out = [f"-- Generated from doublespeakgames/adarkroom lang/{loc}/strings.js (MPL-2.0). Do not edit by hand;",
       "-- regenerate with tools/gen_l10n.py.", "return {"]
out += ["    [%s] = %s," % (q(k), q(j[k])) for k in sorted(j) if isinstance(j[k], str) and j[k] and not ONLINE.search(k)]
out.append("}")
open(f"adarkroom.koplugin/adarkroom/l10n/{loc}.lua", "w", encoding="utf-8").write("\n".join(out) + "\n")
