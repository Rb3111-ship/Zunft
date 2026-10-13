import json, glob, re, os
BS = chr(92)
src = json.load(open('D:/tmp/strings_all.json', encoding='utf-8'))


def unesc(s):
    return s.replace(BS + "'", "'").replace(BS + 'n', '\n').replace(BS + '$', '$').replace(BS + BS, BS)


def dq(s):
    s = s.replace(BS, BS + BS).replace('"', BS + '"').replace('$', BS + '$').replace('\n', BS + 'n')
    return '"' + s + '"'


import os
alltext = ''
for d, _, fs in os.walk('lib'):
    if 'core/i18n' in d.replace(BS, '/'):
        continue
    for f in fs:
        if f.endswith('.dart'):
            alltext += open(os.path.join(d, f), encoding='utf-8').read()
used = set(i for i, k in enumerate(src) if ("'" + k + "'") in alltext)
print('unused keys:', len(src) - len(used))
out = ['// GENERATED from D:/tmp/gen_tr.py - German text -> translation. Missing entries stay German.',
       'const Map<String, Map<String, String>> translations = {']
for lang in ['en', 'tr', 'ar', 'sq', 'pl', 'ro', 'ru', 'uk']:
    out.append("  '%s': {" % lang)
    seen = {}
    for f in sorted(glob.glob('D:/tmp/tr_%s*.txt' % lang)):
        for line in open(f, encoding='utf-8').read().splitlines():
            if not line.strip():
                continue
            i, t = line.split('|', 1)
            seen[int(i)] = t.replace(chr(92)+'n', chr(10))
    missing = [i for i in range(len(src)) if i not in seen and i in used]
    if missing:
        print(lang, 'missing', len(missing), missing[:10])
    for i, t in sorted(seen.items()):
        if i not in used:
            continue
        out.append('    %s: %s,' % (dq(unesc(src[i])), dq(t)))
    out.append('  },')
out.append('};')
open('lib/core/i18n/translations.dart', 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print('ok', len(src))
