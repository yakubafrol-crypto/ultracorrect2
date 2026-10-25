"""Оценка потолка для клавиатурных опечаток (одна операция на слово, без контекста).
Чистые предложения -> синтетический шум ЙЦУКЕН -> кандидаты DL<=1 из словаря -> P(w)*P(s|w).
Аргументы: normative.utf8 ru_full.txt corpus.jsonl [corpus.jsonl ...]"""
import json, math, random, re, sys, collections

NORM, FREQ, *CORPORA = sys.argv[1:]
random.seed(7)
norm = set(w.decode() for w in open(NORM, 'rb').read().split(b'\0') if w)
freq = collections.Counter()
for line in open(FREQ, encoding='utf8'):
    p = line.split()
    if len(p) == 2:
        freq[p[0].replace('ё', 'е')] += int(p[1])
TOTAL = sum(freq.values())
ROWS = ['йцукенгшщзхъ', 'фывапролджэ', 'ячсмитьбю']
pos = {c: (r, i) for r, row in enumerate(ROWS) for i, c in enumerate(row)}
def neighbors(c):
    if c not in pos: return []
    r, i = pos[c]; out = []
    for dr, cols in ((0, (i - 1, i + 1)), (-1, (i, i + 1)), (1, (i - 1, i))):
        rr = r + dr
        if 0 <= rr < 3:
            for j in cols:
                if 0 <= j < len(ROWS[rr]): out.append(ROWS[rr][j])
    return out
ALPHA = 'абвгдежзийклмнопрстуфхцчшщъыьэюя'
def known(w): return w in norm
def logp_word(w): return math.log((freq.get(w, 0) + 0.5) / TOTAL)

# Модель канала: вероятности типов операций (оценка) и равномерность внутри типа.
P_OP = {'sub_adj': 0.40, 'del': 0.25, 'ins': 0.20, 'trans': 0.15}
def corrupt(w):
    op = random.choices(list(P_OP), weights=P_OP.values())[0]
    i = random.randrange(len(w))
    if op == 'sub_adj':
        nb = neighbors(w[i])
        return (w[:i] + random.choice(nb) + w[i+1:], op) if nb else (None, op)
    if op == 'del':
        return w[:i] + w[i+1:], op
    if op == 'ins':  # соседняя клавиша или удвоение
        c = random.choice(neighbors(w[i]) + [w[i]]) if neighbors(w[i]) else w[i]
        return w[:i] + c + w[i:], op
    if i == len(w) - 1 or w[i] == w[i+1]: return None, op
    return w[:i] + w[i+1] + w[i] + w[i+2:], op

def cands(s):
    """Слова словаря на расстоянии Дамерау-Левенштейна 1 с лог-вероятностью канала."""
    out = {}
    L = len(s)
    def add(w, lp):
        if known(w) and (w not in out or out[w] < lp): out[w] = lp
    for i in range(L):  # набранное s получено вставкой символа s[i] -> исходное без него
        nb = neighbors(s[i-1]) if i > 0 else []
        nb2 = neighbors(s[i+1]) if i + 1 < L else []
        dup = (i > 0 and s[i-1] == s[i]) or (i + 1 < L and s[i+1] == s[i])
        p = 0.20 / L * (0.5 if (s[i] in nb or s[i] in nb2 or dup) else 0.05)
        add(s[:i] + s[i+1:], math.log(p))
    for i in range(L + 1):  # пропуск буквы
        for c in ALPHA: add(s[:i] + c + s[i:], math.log(0.25 / (L + 1) / 33))
    for i in range(L):  # замена
        nb = neighbors(s[i])
        for c in ALPHA:
            if c == s[i]: continue
            p = 0.40 / L * (1 / max(len(nb), 1) if c in nb else 0.003)
            add(s[:i] + c + s[i+1:], math.log(p))
    for i in range(L - 1):
        if s[i] != s[i+1]: add(s[:i] + s[i+1] + s[i] + s[i+2:], math.log(0.15 / L))
    return out

WORD = re.compile(r'^[а-яё]+$')
sents = []
for path in CORPORA:
    for line in open(path, encoding='utf8'):
        sents.append(json.loads(line)['correction'].replace('﻿', '').lower().replace('ё', 'е'))
tokens = [t for s in sents for t in re.findall(r'[а-яё]+', s)]
words = [t for t in tokens if len(t) >= 3]
print(f'предложений {len(sents)}, токенов {len(tokens)}, слов >=3 букв {len(words)}')
oov = sum(1 for w in words if not known(w)); print(f'верных слов вне словаря: {oov} ({oov/len(words):.1%})')

# Вред на верных незнакомых словах: есть ли кандидат, который заберёт слово.
res = []  # (posterior_top1, correct?)
stats = collections.Counter()
sample = random.sample(words, min(20000, len(words)))
for w in sample:
    s, op = corrupt(w)
    if not s or s == w: continue
    stats['errors'] += 1
    if not known(w): stats['target_oov'] += 1
    if known(s): stats['realword'] += 1; continue
    c = cands(s)
    if not c: stats['nocand'] += 1; continue
    sc = {k: v + logp_word(k) for k, v in c.items()}
    m = max(sc.values()); z = sum(math.exp(v - m) for v in sc.values())
    best = max(sc, key=sc.get)
    res.append((math.exp(sc[best] - m) / z, best == w))
print(dict(stats))
E = stats['errors']
print(f"ошибка = реальное слово: {stats['realword']/E:.1%}; без кандидатов: {stats['nocand']/E:.1%}; верное слово вне словаря: {stats['target_oov']/E:.1%}")
acc = sum(ok for _, ok in res) / len(res)
print(f'топ-1 верен среди нон-слов с кандидатами: {acc:.1%}')
for th in (0.0, 0.5, 0.7, 0.8, 0.9, 0.95, 0.98):
    fired = [(p, ok) for p, ok in res if p >= th]
    tp = sum(ok for _, ok in fired)
    print(f'порог {th:.2f}: полнота {tp/E:.1%} от всех ошибок, точность {tp/max(len(fired),1):.1%}')

# Негативы: верные слова вне словаря (не известны) — сколько получили бы замену при пороге.
neg = [w for w in words if not known(w)]
for th in (0.5, 0.9):
    harm = 0
    for w in neg:
        c = cands(w)
        if not c: continue
        sc = {k: v + logp_word(k) for k, v in c.items()}
        m = max(sc.values()); z = sum(math.exp(v - m) for v in sc.values())
        if max(math.exp(v - m) / z for v in sc.values()) >= th: harm += 1
    print(f'порог {th}: испорчено бы {harm} из {len(neg)} верных незнакомых слов ({harm/len(words)*1000:.1f} на 1000 слов текста)')
