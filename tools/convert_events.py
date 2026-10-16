#!/usr/bin/env python3
# Convert upstream adarkroom event data (script/events/{setpieces,encounters}.js) to Lua.
# Usage: tools/convert_events.py <in.js> <out.lua> "<header comment>"
import re,sys,json
TOK=re.compile(r"""\s+|//[^\n]*|/\*.*?\*/|(?P<s>'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|`(?:\\.|[^`\\])*`)|(?P<n>\d+\.\d*|\.\d+|\d+)|(?P<i>[A-Za-z_$][\w$]*)|(?P<p>=>|===|!==|==|!=|<=|>=|&&|\|\||\?\?|\.\.\.|[{}\[\]():,;.=<>!+\-*/?%&|])""",re.S)
def tokenize(s):
    out=[];pos=0
    while pos<len(s):
        m=TOK.match(s,pos)
        if not m: raise Exception("bad at %d: %r"%(pos,s[pos:pos+40]))
        pos=m.end()
        for k in 'snip':
            if m.group(k) is not None: out.append((k,m.group(k)));break
    return out
"""Convert adarkroom event data files (JS object literals) to Lua. Usage: conv.py in.js out.lua header-comment"""
import sys,json,re

src,dst,title=sys.argv[1],sys.argv[2],sys.argv[3]
T=tokenize(open(src).read())
i=0
def peek(o=0): return T[i+o]
def nxt():
    global i; t=T[i]; i+=1; return t
def expect(v):
    t=nxt()
    if t[1]!=v: raise Exception("expected %s got %s at %d: %s"%(v,t,i,' '.join(x[1] for x in T[i-10:i+10])))
def jsstr(s):
    q=s[0]; body=s[1:-1]
    body=re.sub(r"\\(.)",lambda m:{'n':'\n','t':'\t'}.get(m.group(1),m.group(1)),body)
    return body
def lstr(v): return '"'+v.replace('\\','\\\\').replace('"','\\"').replace('\n','\\n')+'"'
CONST={'Events._LEAVE_COOLDOWN':'1'}
def ident_chain():
    parts=[nxt()[1]]
    while peek()[1]=='.' : nxt(); parts.append(nxt()[1])
    return '.'.join(parts)
def func():
    # function ( ) { ... }  or ( ) => { ... } / x => { ... }
    if peek()[1]=='function': nxt()
    params=[]
    if peek()[0]=='i':
        params.append(nxt()[1])
    else:
        expect('(')
        while peek()[1]!=')':
            t=nxt()
            if t[1]!=',': params.append(t[1])
        expect(')')
    if peek()[1]=='=>': nxt()
    expect('{'); d=1; body=[]
    while True:
        t=nxt()
        if t[1]=='{': d+=1
        elif t[1]=='}':
            d-=1
            if d==0: break
        body.append(t)
    key=''.join(t[1] for t in body)
    lua=OVERRIDES.get(key)
    if lua is None: lua=body_lua(body)
    return 'function(%s)\n'%', '.join(['engine']+params)+lua+'end'
# 少数 JS 写法（key 为去掉空白的源码）（for 循环、数组 filter）手工对应
OVERRIDES0={
 "for ( let i = 0 ; i < 3 ; i + + ) { World . applyMap ( ) ; }":
   "    local world = engine.modules.world\n    for _i = 1, 3 do world:applyMap() end\n",
 "Events . _lastSpecial = 'none' ;":
   "    engine.events.lastSpecial = \"none\"\n",
 "const last = Events . _lastSpecial ? ? 'none' ; const possible = [ 'shield' , 'enraged' , 'meditation' ] . filter ( p = > p ! = = last ) ; const status = possible [ Math . floor ( Math . random ( ) * possible . length ) ] ; Events . setStatus ( fighter , status ) ; Events . _lastSpecial = status ; return status ;":
   "    local last = engine.events.lastSpecial or \"none\"\n    local possible = {}\n    for _, p in ipairs({ \"shield\", \"enraged\", \"meditation\" }) do\n        if p ~= last then possible[#possible + 1] = p end\n    end\n    local status = possible[math.random(#possible)]\n    engine.events:setStatus(fighter, status)\n    engine.events.lastSpecial = status\n    return status\n",
}
OVERRIDES={k.replace(' ',''):v for k,v in OVERRIDES0.items()}
def body_lua(b):
    out=[];k=0
    def tk(o=0): return b[k+o][1] if k+o<len(b) else None
    line=[]
    while k<len(b):
        t=b[k]; v=t[1]
        if v=='World' and tk(1)=='.':
            name=tk(2)
            if tk(3)=='(' : line.append('world:'+name); k+=3; continue
            if name=='curPos' and tk(3)=='[':
                line.append('world.curPos[%d]'%(int(tk(4))+1)); k+=6; continue
            line.append('world.'+name); k+=3; continue
        if v=='Events' and tk(1)=='.' and tk(2)=='setStatus': line.append('engine.events:setStatus'); k+=3; continue
        if v=='$SM' and tk(1)=='.': line.append('sm:'+tk(2)); k+=3; continue
        if v=='Notifications' and tk(2)=='notify': line.append('engine:notify'); k+=3; continue
        if v=='Prestige' and tk(2)=='collectStores': line.append('engine:prestigeCollect'); k+=3; continue
        if v=='_' and tk(1)=='(' and b[k+2][0]=='s' and tk(3)==')':
            line.append('L(%s)'%lstr(jsstr(tk(2)))); k+=4; continue
        if t[0]=='s': line.append(lstr(jsstr(v))); k+=1; continue
        m={'&&':'and','||':'or','===':'==','==':'==','!==':'~=','!=':'~=','null':'nil','!':'not '}
        if v==';':
            out.append('    '+' '.join(line)); line=[]; k+=1; continue
        line.append(m.get(v,v)); k+=1
    if line: out.append('    '+' '.join(line))
    s='\n'.join(out)
    s=re.sub(r'\s*\(\s*',lambda m:'(',s); s=re.sub(r'\s*\)',')',s); s=re.sub(r'\s*,',',',s); s=re.sub(r'\s*\.\s*','.',s)
    s=s.replace(':(','(')  # no-op safeguard
    need=[]
    if 'sm:' in s: need.append(('sm','engine.state'))
    if 'world' in s: need.append(('world','engine.modules.world'))
    hdr=''
    if need: hdr='    local %s = %s\n'%(', '.join(n for n,_ in need),', '.join(e for _,e in need))
    return hdr+s+'\n'
def value(ind,key=None):
    t=peek()
    if t[1]=='{':
        return obj(ind,key)
    if t[1]=='[':
        nxt(); items=[]
        while peek()[1]!=']':
            items.append(value(ind+1))
            if peek()[1]==',': nxt()
        nxt()
        pad='    '*(ind+1)
        return '{\n'+''.join(pad+x+',\n' for x in items)+'    '*ind+'}'
    if t[1]=='function' or (t[1]=='(' and T[i+1][1]==')' and T[i+2][1]=='=>') \
       or (t[0]=='i' and T[i+1][1]=='=>') or (t[1]=='(' and T[i+1][0]=='i' and T[i+2][1]==')' and T[i+3][1]=='=>'):
        f=func()
        return f.replace('\n','\n'+'    '*ind)
    if t[0]=='s': nxt(); return lstr(jsstr(t[1]))
    if t[0]=='n': nxt(); return t[1]
    if t[1]=='-': nxt(); return '-'+nxt()[1]
    if t[1]=='_' and T[i+1][1]=='(':
        nxt(); nxt(); s=nxt(); expect(')'); return 'L(%s)'%lstr(jsstr(s[1]))
    if t[0]=='i':
        ch=ident_chain()
        if ch in ('true','false'): return ch
        if ch in CONST: return CONST[ch]
        if ch.startswith('AudioLibrary.'): return None
        raise Exception('unknown ident '+ch)
    raise Exception('bad value %s'%(t,))
def keyname(t):
    if t[0]=='i' and re.match(r'^[A-Za-z_]\w*$',t[1]) and t[1] not in ('end','and','or','not','function','local','nil','repeat','until','then','elseif','in','do','while','for','if','else','return','break','goto','true','false'):
        return t[1]+' = '
    if t[0]=='n': return '[%s] = '%t[1]
    v=jsstr(t[1]) if t[0]=='s' else t[1]
    return '[%s] = '%lstr(v)
def obj(ind,parentkey=None):
    expect('{'); entries=[]; spread=None
    while peek()[1]!='}':
        if peek()[1]=='...':
            nxt(); spread='Enemies.'+ident_chain().split('.')[-1]
            if peek()[1]==',': nxt()
            continue
        kt=nxt(); expect(':')
        raw=jsstr(kt[1]) if kt[0]=='s' else kt[1]
        v=value(ind+1,raw)
        if v is not None:
            entries.append((kt,raw,v))
        if peek()[1]==',': nxt()
    nxt()
    pad='    '*(ind+1)
    if parentkey=='buttons':
        # ordered array with id
        out=[]
        for kt,raw,v in entries:
            assert v.startswith('{')
            out.append(pad+'{ id = %s,%s'%(lstr(raw),v[1:])+',\n')
        return '{\n'+''.join(out)+'    '*ind+'}'
    body='{\n'+''.join(pad+keyname(kt)+v+',\n' for kt,raw,v in entries)+'    '*ind+'}'
    if spread: return 'merge(%s, %s)'%(spread,body)
    return body
# top level: 一条或多条 `A.B = value;`。Enemies.* 成为局部表，Events.* 成为返回值。
chunks=[]
while i<len(T):
    if peek()[0]=='i' and T[i+1][1]=='.' and T[i+3][1]=='=' and T[i][1] in ('Events','Enemies'):
        target=T[i][1]; i+=4
        v=value(0)
        chunks.append((target,v))
    else:
        nxt()
body=''
for target,v in chunks:
    if target=='Enemies': body+='local Enemies = '+v+'\n\n'
for target,v in chunks:
    if target=='Events': body+='return '+v
if 'merge(' in body:
    body='''--- 原版用对象展开 `...Enemies.X` 复用敌人数据
local function merge(base, over)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(over) do t[k] = v end
    return t
end

'''+body
hdr='''-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- %s
-- Generated by tools/convert_events.py from upstream doublespeakgames/adarkroom; edit the converter, not this file.
local L = require("adarkroom.l10n")

''' % title
open(dst,'w').write(hdr+body+'\n')
