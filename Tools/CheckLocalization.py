"""Проверка сгенерированного словаря локализации.

Ищет ровно то, что ломает вывод в игре: потерянные и переехавшие форматные
коды, съеденные отступы, невидимые символы, непереведённые строки.
"""
import io
import re
import sys
from collections import Counter

BSLASH = chr(92)
PATH = sys.argv[1]
src = io.open(PATH, encoding="utf-8").read()

ENTRY = re.compile(r'^\s*\[("(?:[^"' + BSLASH + BSLASH + r']|' + BSLASH + BSLASH + r'.)*")\]'
                   r'\s*=\s*("(?:[^"' + BSLASH + BSLASH + r']|' + BSLASH + BSLASH + r'.)*")\s*,\s*$', re.M)
BRANCH = re.compile(r'^\s*(?:if|elseif)\s+locale\s*(==|~=)\s*"(\w+)"', re.M)

# %d %s %1$s, цветовые коды |cffRRGGBB и |r, иконки |T...|t
FMT = re.compile(r'%\d*[$]?[-+ #0]*\d*(?:[.]\d+)?[diouxXeEfgGqcs%]'
                 r'|[|]c[0-9a-fA-F]{8}|[|]r|[|]T[^|]*[|]t')
INVISIBLE = re.compile('[' + chr(0x200b) + chr(0x200c) + chr(0x200d) + chr(0xa0) + chr(0xfeff) + ']')
CYRILLIC = re.compile('[' + chr(0x410) + '-' + chr(0x44f) + ']')


def unquote(text):
    return text[1:-1].replace(BSLASH + '"', '"').replace(BSLASH + BSLASH, BSLASH)


branches = []
for m in BRANCH.finditer(src):
    op, name = m.group(1), m.group(2)
    branches.append((m.start(), name if op == "==" else "enUS"))


def locale_at(pos):
    best = "?"
    for start, name in branches:
        if start < pos:
            best = name
    return best


problems = Counter()
examples = {}


def report(kind, locale, key, value, note=""):
    problems[(locale, kind)] += 1
    examples.setdefault((locale, kind), (key, value, note))


total = Counter()
for m in ENTRY.finditer(src):
    key, value = unquote(m.group(1)), unquote(m.group(2))
    loc = locale_at(m.start())
    total[loc] += 1

    ktok, vtok = FMT.findall(key), FMT.findall(value)
    if Counter(ktok) != Counter(vtok):
        missing = Counter(ktok) - Counter(vtok)
        extra = Counter(vtok) - Counter(ktok)
        report("токены потеряны/лишние", loc, key, value,
               "нет: %s  лишние: %s" % (dict(missing) or "-", dict(extra) or "-"))
    elif ktok != vtok:
        report("токены переставлены", loc, key, value,
               "%s -> %s" % (" ".join(ktok), " ".join(vtok)))

    # Токен, уехавший в начало строки (или из начала), меняет то, что он красит.
    if bool(FMT.match(key.lstrip())) != bool(FMT.match(value.lstrip())):
        report("токен уехал в начало", loc, key, value)

    kl, vl = len(key) - len(key.lstrip()), len(value) - len(value.lstrip())
    kt, vt = len(key) - len(key.rstrip()), len(value) - len(value.rstrip())
    if kl != vl or kt != vt:
        report("съедены отступы", loc, key, value,
               "было %d/%d, стало %d/%d" % (kl, kt, vl, vt))

    if INVISIBLE.search(value):
        report("невидимые символы", loc, key, value,
               "коды: %s" % sorted({hex(ord(c)) for c in INVISIBLE.findall(value)}))

    if CYRILLIC.search(value):
        report("кириллица в переводе", loc, key, value)

print("Разобрано записей:", dict(total))
print()
for (loc, kind), count in sorted(problems.items(), key=lambda kv: (kv[0][0], -kv[1])):
    key, value, note = examples[(loc, kind)]
    print("%-6s %-24s %4d" % (loc, kind, count))
    print("        %r" % key)
    print("     -> %r" % value)
    if note:
        print("        %s" % note)
    print()
