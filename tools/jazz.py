"""카페 배경 재즈 (저작권이 끝난 재즈 스탠다드·전통곡을 앱이 직접 연주해 만듦).
피아노 트리오(+비브라폰): 피아노 컴핑(왼손 화음), 워킹 베이스(현을 뜯는 소리), 브러시·라이드 심벌 드럼, 멜로디(비브라폰 또는 피아노).
- 전통곡(When the Saints Go Marching In, Greensleeves, Amazing Grace)은 멜로디를 그대로 연주한 뒤 이어서 즉흥 연주
- 1930년 이전에 나온 스탠다드(I Got Rhythm, Sweet Georgia Brown, Honeysuckle Rose, St. Louis Blues, Indiana)와 블루스는
  그 곡의 코드 진행 위에서 즉흥 멜로디를 연주 (원곡 멜로디를 그대로 옮긴 것은 아님)
곡마다 짧은 도입 → 중요 부분(1~2코러스) → 마무리 화음. 앱은 이 조각들을 무작위로 이어 틂.
결과: <out>/jazz_XX.m4a (맥의 afconvert 가 있으면 AAC, 없으면 wav) + <out>/jazz.json (파일·길이)"""
import json
import math
import os
import shutil
import subprocess
import wave

import numpy as np

SR = 32000
NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
QUAL = {'': (0, 4, 7), '6': (0, 4, 7, 9), 'maj7': (0, 4, 7, 11), '7': (0, 4, 7, 10), 'm7': (0, 3, 7, 10), 'm': (0, 3, 7),
        'm6': (0, 3, 7, 9), 'dim7': (0, 3, 6, 9), 'm7b5': (0, 3, 6, 10), '9': (0, 4, 7, 10, 14)}
SCALE = {'maj': (0, 2, 4, 5, 7, 9, 11), 'dom': (0, 2, 4, 5, 7, 9, 10), 'min': (0, 2, 3, 5, 7, 9, 10),
         'hdim': (0, 1, 3, 5, 6, 8, 10), 'dim': (0, 2, 3, 5, 6, 8, 9, 11)}
VOICE = {'dom': [(4, 9, 10, 14), (10, 14, 16, 21)], 'min': [(3, 7, 10, 14), (10, 14, 15, 19)], 'maj': [(4, 7, 11, 14), (11, 14, 16, 19)],
         '6': [(4, 7, 9, 14), (9, 14, 16, 19)], 'hdim': [(3, 6, 10, 12), (10, 12, 15, 18)], 'dim': [(0, 3, 6, 9), (3, 6, 9, 12)],
         'minor': [(3, 7, 9, 14), (9, 14, 15, 19)]}


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def parse(sym):
    r = NOTE[sym[0]]
    i = 1
    if len(sym) > 1 and sym[1] in '#b':
        r += 1 if sym[1] == '#' else -1
        i = 2
    q = sym[i:]
    return r % 12, q


def kind(q):
    if q in ('7', '9'):
        return 'dom'
    if q in ('m7', 'm', 'm6'):
        return 'min' if q != 'm6' else 'minor'
    if q == 'm7b5':
        return 'hdim'
    if q == 'dim7':
        return 'dim'
    if q == '6':
        return '6'
    return 'maj'


def scale_of(q):
    k = kind(q)
    return SCALE['dom' if k == 'dom' else ('min' if k in ('min', 'minor') else ('hdim' if k == 'hdim' else ('dim' if k == 'dim' else 'maj')))]


# ───────── 악기 ─────────
def _t(n):
    return np.arange(n) / SR


def piano(f, dur, vel, rng):
    """피아노 한 음: 약간 어긋난 배음(현의 굳기), 높은 배음일수록 빨리 사라짐, 두 줄의 맥놀이, 해머 소리, 손을 떼면 댐퍼"""
    n = int(SR * (dur + 0.6))
    t = _t(n)
    out = np.zeros(n)
    B = 0.0004
    bright = 0.6 + 0.6 * vel
    k = 1
    while k * f < 7000 and k <= 16:
        fk = k * f * math.sqrt(1 + B * k * k)
        amp = (1 / k ** 1.25) * (bright ** (k - 1) if k > 1 else 1)
        dec = 0.9 + 0.55 * k + f / 600
        env = 0.65 * np.exp(-t * dec) + 0.35 * np.exp(-t * dec * 0.12)
        det = 0.0007 * fk
        out += amp * env * (np.sin(2 * np.pi * fk * t) + 0.8 * np.sin(2 * np.pi * (fk + det) * t + k))
        k += 1
    ham = rng.standard_normal(int(SR * 0.006)) * np.exp(-_t(int(SR * 0.006)) * 900) * 0.15
    out[:len(ham)] += ham
    att = np.minimum(1, t / 0.003)
    rel = np.where(t > dur, np.exp(-(t - dur) * 14), 1.0)
    return out * att * rel * vel


def vibes(f, dur, vel, rng):
    """비브라폰: 맑은 기본음 + 4배·10배 배음, 모터 떨림, 길게 울리다 손으로 막음"""
    n = int(SR * (dur + 0.5))
    t = _t(n)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t * 0.9)
    out += 0.22 * np.sin(2 * np.pi * f * 3.98 * t) * np.exp(-t * 4)
    out += 0.06 * np.sin(2 * np.pi * f * 9.9 * t) * np.exp(-t * 12)
    out *= 1 + 0.22 * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6))
    mallet = rng.standard_normal(int(SR * 0.004)) * 0.08
    out[:len(mallet)] += mallet
    rel = np.where(t > dur, np.exp(-(t - dur) * 9), 1.0)
    return out * np.minimum(1, t / 0.002) * rel * vel


def bass(f, dur, vel, rng):
    """콘트라베이스 뜯는 소리 (카플러스-스트롱 현 모형)"""
    n = int(SR * (dur + 0.12))
    N = max(2, int(round(SR / f)))
    ex = rng.standard_normal(N)
    for _ in range(3):                                         # 손가락으로 뜯어 둥근 소리
        ex = 0.5 * (ex + np.roll(ex, 1))
    buf = ex.copy()
    out = np.zeros(n)
    idx = 0
    damp = 0.4985
    for i in range(n):
        j = idx
        k = idx + 1 if idx + 1 < N else 0
        v = buf[j]
        out[i] = v
        buf[j] = damp * (v + buf[k])
        idx = k
    t = _t(n)
    rel = np.where(t > dur, np.exp(-(t - dur) * 30), 1.0)
    thump = np.sin(2 * np.pi * f * t) * np.exp(-t * 6) * 0.5     # 몸통 울림
    return (out * 1.6 + thump) * rel * vel


def _ride_sample(rng):
    n = int(SR * 2.2)
    t = _t(n)
    out = np.zeros(n)
    for _ in range(36):
        f = rng.uniform(2500, 9000)
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * rng.uniform(0.3, 1) * np.exp(-t * rng.uniform(1.2, 3.5))
    ping = np.sin(2 * np.pi * 5200 * t) * np.exp(-t * 30) * 4
    nz = rng.standard_normal(n)
    nz = nz - np.convolve(nz, np.ones(4) / 4, mode='same')
    out = out / 36 + ping * 0.1 + nz * np.exp(-t * 9) * 0.25
    return out


def _hat_sample(rng):
    n = int(SR * 0.08)
    nz = rng.standard_normal(n)
    nz = nz - np.convolve(nz, np.ones(3) / 3, mode='same')
    return nz * np.exp(-_t(n) * 70)


def _brush_sample(rng, dur):
    n = int(SR * dur)
    nz = rng.standard_normal(n)
    nz = np.convolve(nz, np.ones(3) / 3, mode='same') - np.convolve(nz, np.ones(24) / 24, mode='same')
    env = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return nz * env


def _kick(rng):
    n = int(SR * 0.25)
    t = _t(n)
    return np.sin(2 * np.pi * (52 + 30 * np.exp(-t * 30)) * t) * np.exp(-t * 14)


def place(buf, x, at):
    i = int(at * SR)
    if i < 0:
        x = x[-i:]
        i = 0
    if i >= len(buf) or len(x) == 0:
        return
    m = min(len(x), len(buf) - i)
    buf[i:i + m] += x[:m]


# ───────── 연주 만들기 ─────────
class Tune:
    def __init__(self, name, bpm, meter, style, bars, melody=None, inst='vibes', choruses=1, solo=1, key_center=None, blues=False):
        self.name, self.bpm, self.meter, self.style = name, bpm, meter, style
        self.bars = bars                    # [[chord, ...], ...] 마디마다 화음 (1~2개)
        self.melody = melody                # [(박, 길이, 음)] 머리 멜로디 (없으면 즉흥)
        self.inst = inst
        self.choruses = choruses            # 머리를 몇 번
        self.solo = solo                    # 이어서 즉흥 몇 코러스
        self.blues = blues
        self.key_center = key_center        # 오르골: 옮길 반음 수


def chords_at(bars, meter):
    """박마다 화음 목록"""
    out = []
    for b in bars:
        per = meter // len(b)
        for c in b:
            out += [c] * per
        out += [b[-1]] * (meter - per * len(b))
    return out


def swing(beat, amt):
    """엇박(0.5)을 셋잇단 느낌으로 늦춤"""
    fl = math.floor(beat)
    fr = beat - fl
    if abs(fr - 0.5) < 1e-6:
        return fl + 0.5 + (2 / 3 - 0.5) * amt
    return beat


def walk_bass(chs, meter, rng, style):
    """워킹 베이스: 박마다 한 음. 첫 박은 근음, 마지막 박은 다음 근음으로 반음 다가감"""
    notes = []
    prev = 40
    n = len(chs)
    two = style in ('two', 'ballad', 'latin')
    for i in range(n):
        r, q = parse(chs[i])
        bar_beat = i % meter
        nxt = parse(chs[(i + 1) % n])[0]
        tones = [r + x for x in QUAL.get(q, (0, 4, 7))]
        if bar_beat == 0 or (i > 0 and chs[i] != chs[i - 1]):
            pc = r
        elif two and meter == 4 and bar_beat == 2:
            pc = r + 7
        elif bar_beat == meter - 1 and chs[(i + 1) % n] != chs[i] or (bar_beat == meter - 1 and rng.random() < 0.6):
            pc = nxt + rng.choice([-1, 1, 7 - 12])
        else:
            pc = rng.choice(tones[1:] + [r + scale_of(q)[1]])
        m = prev + ((pc - prev) % 12)
        if m - prev > 6:
            m -= 12
        while m < 28:
            m += 12
        while m > 50:
            m -= 12
        notes.append(m)
        prev = m
    return notes


def voicing(sym, prev):
    r, q = parse(sym)
    best, bs = None, 1e9
    for v in VOICE[kind(q)]:
        for octv in (48, 60):
            ps = sorted(octv + r + x for x in v)
            while ps[0] < 50:
                ps = [p + 12 for p in ps]
            while ps[0] > 62:
                ps = [p - 12 for p in ps]
            s = sum(abs(a - b) for a, b in zip(ps, prev)) if prev else abs(ps[0] - 55)
            if s < bs:
                best, bs = ps, s
    return best


COMP_SWING = [[(0, 1.2)], [(1.5, 0.4), (3, 0.8)], [(0, 0.6), (1.5, 0.5)], [(0.5, 0.4), (2.5, 0.4)], [(1, 0.6), (2.5, 0.4)], [(0, 0.5), (2, 0.6), (3.5, 0.4)]]
COMP_LATIN = [[(0, 0.9), (1.5, 0.4), (3, 0.4)], [(0, 0.45), (1.5, 0.9), (3, 0.4)], [(0.5, 0.4), (2, 0.4), (3.5, 0.4)]]


def improvise(chs, meter, rng, lo, hi, motif_bank, blues=False, busy=0.5):
    """즉흥 멜로디: 2마디씩 한 악구. 센박엔 화음 음, 사이엔 음계를 따라 걷고, 악구 끝은 긴 화음 음. 앞 악구 리듬을 되풀이해 흥얼거리는 느낌"""
    notes = []
    nb = len(chs)
    cur = (lo + hi) // 2
    phrase = meter * 2
    for p0 in range(0, nb, phrase):
        if rng.random() < 0.18:
            continue                                            # 쉬는 악구
        # 리듬: 반박 단위 자리들
        if motif_bank and rng.random() < 0.45:
            slots = motif_bank[int(rng.integers(len(motif_bank)))]
        else:
            slots = []
            b = rng.choice([0, 0.5, 1])
            while b < phrase - 1.0:
                slots.append(b)
                b += rng.choice([0.5, 0.5, 1, 1, 1.5]) if rng.random() < busy else rng.choice([1, 1.5, 2])
            motif_bank.append(slots)
        for j, b in enumerate(slots):
            bi = p0 + int(b)
            if bi >= nb:
                break
            r, q = parse(chs[bi])
            tones = [r + x for x in QUAL.get(q, (0, 4, 7))]
            sc = [r + x for x in scale_of(q)]
            if blues:
                sc += [r + 3, r + 6, r + 10]
            strong = abs(b - round(b)) < 1e-6 and int(b) % 2 == 0
            pool = tones if strong else sc
            cands = []
            for pc in pool:
                for o in range(3, 8):
                    m = pc % 12 + 12 * o
                    if lo <= m <= hi and abs(m - cur) <= 7:
                        cands.append(m)
            if not cands:
                cands = [cur]
            # 가까운 음을 더 자주
            w = np.array([1.0 / (1 + abs(m - cur)) for m in cands])
            m = int(rng.choice(cands, p=w / w.sum()))
            last = j == len(slots) - 1
            ln = (slots[j + 1] - b) if not last else rng.choice([1.5, 2, 2.5])
            notes.append((p0 + b, min(ln, 3) * (0.9 if not last else 1), m, 0.6 + 0.3 * strong + rng.uniform(-0.1, 0.1)))
            cur = m
    return notes


def render(tune, seed):
    rng = np.random.default_rng(seed)
    meter = tune.meter
    spb = 60.0 / tune.bpm
    sw = 0 if tune.style in ('latin', 'ballad') else (0.85 if tune.bpm < 190 else 0.6)
    form = chords_at(tune.bars, meter)
    intro = chords_at(tune.bars[-2:], meter)                 # 도입: 마지막 두 마디
    total_forms = tune.choruses + tune.solo
    chs = intro + form * total_forms
    ending_bars = 2
    end_ch = [tune.bars[0][0]] * (meter * ending_bars)
    all_ch = chs + end_ch
    nbeats = len(all_ch)
    dur = nbeats * spb + 3.0
    n = int(SR * dur)
    mix = {k: np.zeros(n) for k in ('piano', 'bass', 'drums', 'mel')}

    # 드럼
    ride = _ride_sample(rng)
    hat = _hat_sample(rng)
    kick = _kick(rng)
    for i in range(len(chs)):
        t0 = i * spb
        bb = i % meter
        h = rng.uniform(-0.006, 0.006)
        if tune.style == 'ballad':
            place(mix['drums'], _brush_sample(rng, spb * 0.95) * 0.35, t0)
            if bb in (1, 3) if meter == 4 else bb == 1:
                place(mix['drums'], hat * 0.35, t0 + h)
        elif tune.style == 'latin':
            place(mix['drums'], hat * (0.5 if bb % 2 == 0 else 0.35), t0 + h)
            place(mix['drums'], hat * 0.3, t0 + spb * 0.5 + h)
            if bb in (0, 2):
                place(mix['drums'], kick * 0.35, t0)
            if (i % (meter * 2)) in (0, 3, 6, 10, 12):            # 림 클릭 (2마디 클라베)
                place(mix['drums'], _hat_sample(rng)[:200] * 1.2, t0 + h)
        else:
            vel = 0.55 + 0.1 * (bb % 2)
            place(mix['drums'], ride * vel, t0 + h)
            if (meter == 4 and bb in (1, 3)) or (meter == 3 and bb == 2):
                place(mix['drums'], ride * 0.35, t0 + spb * swing(0.5, sw) + h)     # 칭-치-칭
            if (meter == 4 and bb in (1, 3)) or (meter == 3 and bb in (1, 2)):
                place(mix['drums'], hat * 0.5, t0 + h)
            place(mix['drums'], _brush_sample(rng, spb * 0.9) * 0.12, t0)
            place(mix['drums'], kick * 0.12, t0)                                      # 페더링
    # 마무리 심벌
    place(mix['drums'], ride * 0.8, len(chs) * spb)

    # 베이스
    bl = walk_bass(chs, meter, rng, tune.style)
    two = tune.style in ('two', 'ballad')
    for i, m in enumerate(bl):
        bb = i % meter
        if two and meter == 4 and bb in (1, 3) and i >= meter * 2:
            continue
        ln = spb * (1.9 if (two and meter == 4) else 0.95)
        if tune.style == 'latin':
            if bb in (1, 3):
                continue
            place(mix['bass'], bass(mtof(m), spb * 1.4, 0.8, rng), i * spb)
            place(mix['bass'], bass(mtof(m + 7 if m + 7 <= 52 else m - 5), spb * 0.45, 0.6, rng), i * spb + spb * 1.5)
            continue
        place(mix['bass'], bass(mtof(m), ln, 0.85 + rng.uniform(-0.1, 0.1), rng), i * spb + rng.uniform(-0.004, 0.004))
    r0, q0 = parse(tune.bars[0][0])
    tonic = 28 + ((r0 - 28) % 12)
    place(mix['bass'], bass(mtof(tonic), 3.0, 1.0, rng), len(chs) * spb)

    # 피아노 컴핑
    prev = None
    bar_n = len(chs) // meter
    for bi in range(bar_n):
        pats = COMP_LATIN if tune.style == 'latin' else COMP_SWING
        if tune.style == 'ballad':
            pats = [[(0, meter - 0.2)], [(0, 1.8), (2, 1.8)]] if meter == 4 else [[(0, 2.8)]]
        if meter == 3 and tune.style != 'ballad':
            pats = [[(0, 0.8), (1.5, 0.4)], [(1, 0.6), (2, 0.6)], [(0, 1.6)]]
        pat = pats[rng.integers(len(pats))]
        for (b, ln) in pat:
            gi = bi * meter + int(b)
            if gi >= len(chs):
                continue
            v = voicing(chs[gi], prev)
            prev = v
            at = (bi * meter + swing(b, sw)) * spb
            for k, m in enumerate(v):
                place(mix['piano'], piano(mtof(m), ln * spb, 0.42 + rng.uniform(-0.06, 0.06), rng), at + k * 0.004 + rng.uniform(-0.004, 0.004))
    # 마무리 화음 (넓게 펼침)
    v = voicing(tune.bars[0][0], prev)
    for k, m in enumerate([tonic + 12 + 12] + v + [v[-1] + 12]):
        place(mix['piano'], piano(mtof(m), 2.8, 0.45, rng), len(chs) * spb + k * 0.05)

    # 멜로디
    mel_fn = vibes if tune.inst == 'vibes' else piano
    lo, hi = (62, 86) if tune.inst == 'vibes' else (60, 84)
    off = len(intro)
    events = []
    form_n = len(form)
    if tune.melody:
        for c in range(tune.choruses):
            for (b, ln, m) in tune.melody:
                events.append((off + c * form_n + b, ln, m, 0.75))
    else:
        bank = []
        for c in range(tune.choruses):
            for (b, ln, m, v) in improvise(form, meter, rng, lo, hi, bank, tune.blues, busy=0.35):
                events.append((off + c * form_n + b, ln, m, v))
    bank = []
    for c in range(tune.solo):
        base = off + (tune.choruses + c) * form_n
        for (b, ln, m, v) in improvise(form, meter, rng, lo, hi, bank, tune.blues, busy=0.6):
            events.append((base + b, ln, m, v * 0.9))
    for (b, ln, m, v) in events:
        if b < 0:
            continue
        at = swing(b, sw) * spb + rng.uniform(-0.006, 0.006)
        if tune.inst == 'piano':
            m = m if m >= 60 else m + 12
        place(mix['mel'], mel_fn(mtof(m), ln * spb * 0.95, v, rng), at)
    # 섞기
    def norm(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)
    out = 0.55 * norm(mix['piano']) + 0.62 * norm(mix['bass']) + 0.2 * norm(mix['drums']) + 0.7 * norm(mix['mel'])
    # 작은 방 울림
    ir_n = int(SR * 0.9)
    ir = rng.standard_normal(ir_n) * np.exp(-_t(ir_n) * 6.5)
    ir = np.convolve(ir, np.ones(6) / 6, mode='same')
    wet = np.fft.irfft(np.fft.rfft(out, n + ir_n) * np.fft.rfft(ir, n + ir_n), n + ir_n)[:n]
    out = out + norm(wet) * 0.22
    # 끝은 천천히 줄임, 앞뒤 살짝 열고 닫기
    fade = int(SR * 2.0)
    out[-fade:] *= np.linspace(1, 0, fade) ** 1.5
    out[:int(SR * 0.02)] *= np.linspace(0, 1, int(SR * 0.02))
    out = np.tanh(out / (np.max(np.abs(out)) + 1e-9) * 1.4)
    return out / (np.max(np.abs(out)) + 1e-9) * 0.89


def B(*ch):
    return [list(c) if isinstance(c, tuple) else [c] for c in ch]


def mel(seq, start=0.0):
    """[(음 또는 None, 박)] → [(박, 길이, 음)]"""
    out = []
    b = start
    for m, ln in seq:
        if m is not None:
            out.append((b, ln, m))
        b += ln
    return out


def tunes():
    T = []
    # I Got Rhythm (거슈윈, 1930) 코드 진행 — Bb, 빠른 스윙
    A1 = B(('Bb6', 'G7'), ('Cm7', 'F7'), ('Dm7', 'G7'), ('Cm7', 'F7'), ('Fm7', 'Bb7'), ('Eb6', 'Ebm6'), ('Dm7', 'G7'), ('Cm7', 'F7'))
    A2 = B(('Bb6', 'G7'), ('Cm7', 'F7'), ('Dm7', 'G7'), ('Cm7', 'F7'), ('Fm7', 'Bb7'), ('Eb6', 'Ebm6'), ('Cm7', 'F7'), 'Bb6')
    BR = B('D7', 'D7', 'G7', 'G7', 'C7', 'C7', 'F7', 'F7')
    T.append(Tune('rhythm', 168, 4, 'swing', A1 + A2 + BR + A2, inst='vibes', choruses=1, solo=0))
    # Sweet Georgia Brown (1925) 코드 진행 — F
    SG = B('D7', 'D7', 'G7', 'G7', 'C7', 'C7', 'F6', ('Gm7', 'C7'), 'D7', 'D7', 'G7', 'G7', ('Gm7', 'C7'), ('F6', 'D7'), ('Gm7', 'C7'), 'F6')
    T.append(Tune('georgia', 150, 4, 'swing', SG, inst='piano', choruses=1, solo=1))
    # Honeysuckle Rose (패츠 월러, 1929) 코드 진행 — F, 미디엄 스윙
    HA = B(('Gm7', 'C7'), ('Gm7', 'C7'), ('Gm7', 'C7'), ('Gm7', 'C7'), 'F6', 'F6', ('Gm7', 'C7'), 'F6')
    HB = B('F7', 'F7', 'Bb6', 'Bb6', 'G7', 'G7', 'Gm7', 'C7')
    T.append(Tune('honeysuckle', 124, 4, 'swing', HA + HA + HB + HA, inst='vibes', choruses=1, solo=0))
    # St. Louis Blues (W.C. 핸디, 1914) — G 블루스 + 단조 하바네라 부분, 라틴 느낌
    BL = B('G7', 'C7', 'G7', 'G7', 'C7', 'C7', 'G7', 'G7', 'D7', 'C7', 'G7', 'D7')
    MN = B('Gm', 'D7', 'D7', 'Gm', 'Gm', 'D7', 'D7', 'Gm')
    T.append(Tune('stlouis', 112, 4, 'latin', BL + MN, inst='piano', choruses=1, solo=0, blues=True))
    # Indiana (1917) 코드 진행 — F, 빠른 스윙
    IN = B('F6', 'F6', 'D7', 'D7', 'G7', 'G7', 'C7', 'C7', 'F6', 'F6', 'D7', 'D7', 'G7', 'C7', ('F6', 'D7'), ('Gm7', 'C7'))
    T.append(Tune('indiana', 176, 4, 'swing', IN, inst='vibes', choruses=1, solo=1))
    # When the Saints Go Marching In (전통곡) — F, 투 비트로 멜로디 → 스윙 즉흥
    SA = B('F6', 'F6', 'F6', 'F6', 'F6', 'F6', 'C7', 'C7', 'F6', 'F7', 'Bb6', 'Bbm6', 'F6', 'C7', 'F6', 'F6')
    SAm = mel([(None, 1), (65, 1), (69, 1), (70, 1),            # (못갖춘마디처럼 첫 마디 2~4박) Oh when the
               (72, 4), (None, 1), (65, 1), (69, 1), (70, 1), (72, 4), (None, 1), (65, 1), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (69, 2), (67, 4), (None, 1), (69, 1), (69, 1), (67, 1),
               (65, 3), (65, 1), (69, 2), (72, 2), (72, 2), (70, 2), (None, 2), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (67, 2), (65, 4)])
    T.append(Tune('saints', 132, 4, 'two', SA, melody=SAm, inst='piano', choruses=1, solo=1))
    # Greensleeves (전통곡) — A단조 재즈 왈츠
    GA = B('Am', 'C6', 'G6', 'Em', 'Am', 'E7', 'E7', 'Am', 'Am', 'C6', 'G6', 'Em', 'Am', 'E7', 'Am', 'Am',
           'C6', 'G6', 'G6', 'Em', 'Am', 'E7', 'E7', 'Am', 'C6', 'G6', 'G6', 'Em', 'Am', 'E7', 'Am', 'Am')
    GAm = mel([(None, 2), (69, 1),
               (72, 2), (74, 1), (76, 1.5), (77, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 2), (69, 1), (69, 1.5), (68, 0.5), (69, 1), (71, 2), (68, 1), (64, 2), (69, 1),
               (72, 2), (74, 1), (76, 1.5), (77, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 1.5), (71, 0.5), (69, 1), (68, 1.5), (66, 0.5), (68, 1), (69, 3), (69, 2), (None, 1),
               (79, 3), (79, 1.5), (78, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 2), (69, 1), (69, 1.5), (68, 0.5), (69, 1), (71, 2), (68, 1), (64, 3),
               (79, 3), (79, 1.5), (78, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 1.5), (71, 0.5), (69, 1), (68, 1.5), (66, 0.5), (68, 1), (69, 3)])
    T.append(Tune('greensleeves', 150, 3, 'swing', GA, melody=GAm, inst='vibes', choruses=1, solo=0))
    # Amazing Grace (전통곡) — G, 느린 3박 발라드
    AG = B('G6', 'G6', ('G6',), 'D7', 'G6', 'G7', 'C6', 'G6', 'G6', 'Em', 'D7', 'D7', 'G6', 'C6', ('G6',), 'G6')
    AGm = mel([(None, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 2), (64, 1), (62, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (74, 3), (74, 2), (71, 1),
               (74, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 2), (64, 1), (62, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 3)])
    T.append(Tune('grace', 74, 3, 'ballad', AG, melody=AGm, inst='piano', choruses=1, solo=0))
    # F 블루스 (카운트 베이시 풍 미디엄 스윙)
    FB = B('F7', 'Bb7', 'F7', ('Cm7', 'F7'), 'Bb7', 'Bdim7', 'F7', ('Am7', 'D7'), 'Gm7', 'C7', ('F7', 'D7'), ('Gm7', 'C7'))
    T.append(Tune('fblues', 118, 4, 'swing', FB, inst='piano', choruses=1, solo=1, blues=True))
    # C단조 블루스 (느리게)
    MB = B('Cm7', 'Fm7', 'Cm7', 'Cm7', 'Fm7', 'Fm7', 'Cm7', 'Cm7', 'Ab7', 'G7', 'Cm7', 'G7')
    T.append(Tune('minorblues', 96, 4, 'swing', MB, inst='vibes', choruses=1, solo=1, blues=True))
    return T


# ───────── 오르골 ─────────
# 카페 배경음: 재즈 트리오 대신 오르골 (쇠빗살을 핀이 튕기는 소리). 저작권이 끝난 옛 곡·전통곡만.
# 빗살 하나 = 끝이 붙들린 쇠막대 → 배음이 1 : 6.27 : 17.55 (정수배가 아니라 맑고 투명한 소리), 높은 음일수록 빨리 사라짐

def tine(f, vel, rng, ln=None):
    """오르골 빗살 한 번 튕김"""
    tau = float(np.clip(3.2 * (440.0 / f) ** 0.75, 0.35, 4.0))     # 낮은 음은 길게, 높은 음은 짧게
    if ln is None:
        ln = min(6 * tau, 7.0)
    n = int(SR * ln)
    t = _t(n)
    det = rng.uniform(0.15, 0.5)                                    # 빗살이 살짝 맥놀이
    x = np.sin(2 * np.pi * f * t) * 0.8 + np.sin(2 * np.pi * (f + det) * t + rng.uniform(0, 6)) * 0.2
    x *= np.exp(-t / tau)
    for ratio, amp, dk in ((6.27, 0.22, 7.0), (17.55, 0.06, 18.0)):
        if f * ratio < SR / 2 - 500:
            x += amp * np.sin(2 * np.pi * f * ratio * t + rng.uniform(0, 6)) * np.exp(-t / tau * dk)
    # 핀이 빗살을 튕기는 딸깍
    cn = int(SR * 0.006)
    click = rng.standard_normal(cn) * np.exp(-np.linspace(0, 6, cn))
    click = click - np.convolve(click, np.ones(4) / 4, mode='same')
    x[:cn] += click * 0.12
    a = int(SR * 0.0015)
    x[:a] *= np.linspace(0, 1, a)
    return x * vel


def render_box(tune, seed):
    """오르골 연주. style:
    - 'rag'  : 래그타임 (2박, 곧은 박) — 낮은 근음 → 화음 → 5음 → 화음을 번갈아 치는 스트라이드 반주
    - 'swing': 스윙 (4박) — 엇박을 셋잇단 느낌으로 늦추고, 1·3박 낮은 근음/5음 + 2·4박 7화음 (스트라이드)
    - 'two'  : 딕시랜드 투 비트 (스윙과 같지만 반주가 가벼움)
    멜로디가 없는 곡은 그 곡의 코드 진행 위에서 재즈 즉흥 멜로디(블루 노트·반음 접근음)를 만듦"""
    rng = np.random.default_rng(seed)
    meter = tune.meter
    spb = 60.0 / tune.bpm
    form = chords_at(tune.bars, meter)
    reps = tune.choruses
    chs = form * reps
    nb = len(chs)
    sw = 0.0 if tune.style == 'rag' else 0.75
    slow0 = max(0, nb - meter * 2)

    def T0(b):
        if b <= slow0:
            return b * spb
        k = (b - slow0) / max(1, nb - slow0)
        return slow0 * spb + (b - slow0) * spb * (1 + 0.45 * k * k)

    def T(b):
        return T0(swing(b, sw) if sw > 0 else b)
    total = T0(nb + meter) + 6.0
    n = int(SR * total)
    acc = np.zeros(n)
    mel_buf = np.zeros(n)
    tr = tune.key_center or 0

    def put(buf, x, at):
        place(buf, x, at + rng.uniform(-0.004, 0.004))

    def low_root(r):
        root = 48 + ((r - 48) % 12) + tr
        while root > 52:
            root -= 12
        while root < 40:
            root += 12
        return root
    # 반주 (스트라이드): 센박 = 낮은 근음(또는 5음), 여린박 = 가운데 음역 화음 (7음 포함)
    for beat in range(nb):
        sym = chs[beat]
        r, q = parse(sym)
        iv = QUAL.get(q, (0, 4, 7))
        root = low_root(r)
        chord = sorted(60 + ((root + x - 60) % 12) for x in iv[1:])          # 3·5·7음을 C4~B4 사이로
        pos = beat % meter
        strong = pos % 2 == 0
        if tune.style == 'rag':
            put(acc, tine(mtof(root if pos == 0 else root + 7), 0.62, rng), T(beat))
            for m in chord[:3]:
                put(acc, tine(mtof(m), 0.24, rng), T(beat + 0.5))
        else:
            if strong:
                put(acc, tine(mtof(root if pos == 0 or chs[beat] != chs[beat - 1] else root + 7), 0.6, rng), T(beat))
            else:
                light = 0.2 if tune.style == 'two' else 0.26
                for m in chord[:3]:
                    put(acc, tine(mtof(m), light * rng.uniform(0.9, 1.05), rng), T(beat))
                if rng.random() < 0.18:                                       # 가끔 엇박 화음 (밀어 치기)
                    for m in chord[:2]:
                        put(acc, tine(mtof(m), 0.16, rng), T(beat + 0.5))
    # 멜로디: 머리 멜로디가 있으면 그대로, 없으면 코드 진행 위 즉흥
    melody = tune.melody
    if melody is None:
        bank = []
        imp = improvise(form, meter, rng, 64, 82, bank, blues=tune.blues, busy=0.42)
        melody = [(b, ln, m) for (b, ln, m, _v) in imp]
    for c in range(reps):
        for (b, ln, m) in melody:
            bb = c * len(form) + b
            if bb < 0 or bb >= nb:
                continue
            mm = m + tr + 12
            v = 0.85 * rng.uniform(0.92, 1.05)
            put(mel_buf, tine(mtof(mm), v, rng), T(bb))
            if abs(bb - round(bb)) < 1e-6 and int(round(bb)) % meter == 0 and ln >= 1:
                put(mel_buf, tine(mtof(mm - 12), 0.3, rng), T(bb) + 0.012)
            if ln >= 2:
                put(mel_buf, tine(mtof(mm), 0.34, rng), T(bb + ln / 2))
    # 마지막 화음 (6음·9음을 얹어 재즈답게 넓게 펼쳐 끝맺음)
    r0, q0 = parse(tune.bars[-1][-1])
    if q0 in ('7', '9'):                                   # 딸림화음으로 끝나는 진행이면 으뜸화음으로 풀어 끝냄
        r0, q0 = (r0 + 5) % 12, '6'
    root = low_root(r0)
    third = 3 if 'm' in q0 and 'maj' not in q0 else 4
    for k, m in enumerate([root, root + 7, root + 12 + third, root + 21, root + 26, root + 31]):
        put(acc, tine(mtof(m), 0.45, rng), T0(nb) + k * 0.09)

    def norm(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)
    out = 0.55 * norm(acc) + 0.9 * norm(mel_buf)
    ir_n = int(SR * 0.6)
    ir = rng.standard_normal(ir_n) * np.exp(-_t(ir_n) * 9)
    ir = np.convolve(ir, np.ones(8) / 8, mode='same')
    wet = np.fft.irfft(np.fft.rfft(out, n + ir_n) * np.fft.rfft(ir, n + ir_n), n + ir_n)[:n]
    out = out + norm(wet) * 0.18
    out = np.convolve(out, np.array([0.25, 0.5, 0.25]), mode='same')
    end = int(SR * (T0(nb) + 5.0))
    out = out[:end]
    fade = int(SR * 1.5)
    out[-fade:] *= np.linspace(1, 0, fade) ** 2
    return out / (np.max(np.abs(out)) + 1e-9) * 0.85


def box_tunes():
    """카페 오르골: 재즈 곡만 (동요·클래식 없음).
    저작권이 끝난 곡(1928년 이전에 나온 곡·전통곡)만 씀 — 'Autumn Leaves'처럼 아직 저작권이 있는 스탠다드의 멜로디는 옮길 수 없음.
    - 멜로디까지 연주: The Entertainer (조플린, 1902), When the Saints Go Marching In (딕시랜드 전통곡)
    - 그 시대 스탠다드의 코드 진행 위 즉흥 (재즈 연주자들이 하듯 멜로디를 새로 지어 연주):
      Sweet Georgia Brown (1925), Indiana (1917), St. Louis Blues (1914), Tea for Two (1924),
      Bye Bye Blackbird (1926), Avalon (1920), F 블루스, C 단조 블루스"""
    T = []
    # The Entertainer (스콧 조플린, 1902) — C, 2박, 16분음표 = 0.25박
    EN = B('C', 'C', 'C', 'G7', 'C', 'C', 'D7', 'D7', 'G7', 'C', 'C', 'G7', 'C', 'C', 'C', 'G7', 'C')
    p1 = [(74, 0.25), (75, 0.25)]
    a1 = [(76, 0.25), (84, 0.5), (76, 0.25), (84, 0.5), (76, 0.25), (84, 1.25),
          (84, 0.25), (86, 0.25), (87, 0.25), (88, 0.25),
          (84, 0.25), (86, 0.25), (88, 0.5), (83, 0.25), (86, 0.5), (84, 1.25), (None, 0.5)]
    a2 = [(76, 0.25), (84, 0.5), (76, 0.25), (84, 0.5), (76, 0.25), (84, 1.25),
          (81, 0.25), (79, 0.25), (78, 0.25), (81, 0.25),
          (84, 0.25), (88, 0.5), (86, 0.25), (84, 0.25), (81, 0.25), (86, 1.5), (None, 0.5)]
    a4 = [(84, 0.25), (86, 0.25), (88, 0.25), (84, 0.25), (86, 0.25), (88, 0.5), (84, 0.25),
          (86, 0.25), (84, 0.25), (88, 0.25), (84, 0.25), (86, 0.25), (88, 0.5), (84, 0.25),
          (86, 0.25), (84, 0.25), (88, 0.25), (84, 0.25), (86, 0.25), (88, 0.5), (83, 0.25),
          (86, 0.5), (84, 1.5)]
    ENm = mel([(None, 1.5)] + p1 + a1 + p1 + a2 + p1 + a1 + a4)
    T.append(Tune('entertainer', 76, 2, 'rag', EN, melody=ENm, choruses=2, key_center=-12))
    # When the Saints Go Marching In (전통곡) — F, 딕시랜드 투 비트
    SA = B('F6', 'F6', 'F6', 'F6', 'F6', 'F6', 'C7', 'C7', 'F6', 'F7', 'Bb6', 'Bbm6', 'F6', 'C7', 'F6', 'F6')
    SAm = mel([(None, 1), (65, 1), (69, 1), (70, 1),
               (72, 4), (None, 1), (65, 1), (69, 1), (70, 1), (72, 4), (None, 1), (65, 1), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (69, 2), (67, 4), (None, 1), (69, 1), (69, 1), (67, 1),
               (65, 3), (65, 1), (69, 2), (72, 2), (72, 2), (70, 2), (None, 2), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (67, 2), (65, 4)])
    T.append(Tune('saints', 120, 4, 'two', SA, melody=SAm, choruses=2, key_center=-5))
    # Sweet Georgia Brown (1925) 코드 진행 — F
    SG = B('D7', 'D7', 'G7', 'G7', 'C7', 'C7', 'F6', ('Gm7', 'C7'), 'D7', 'D7', 'G7', 'G7', ('Gm7', 'C7'), ('F6', 'D7'), ('Gm7', 'C7'), 'F6')
    T.append(Tune('georgia', 132, 4, 'swing', SG, choruses=2, key_center=-5))
    # Indiana (1917) 코드 진행 — F
    IN = B('F6', 'F6', 'D7', 'D7', 'G7', 'G7', 'C7', 'C7', 'F6', 'F6', 'D7', 'D7', 'G7', 'C7', ('F6', 'D7'), ('Gm7', 'C7'))
    T.append(Tune('indiana', 140, 4, 'swing', IN, choruses=2, key_center=-5))
    # St. Louis Blues (W.C. 핸디, 1914) — G 블루스
    BL = B('G7', 'C7', 'G7', 'G7', 'C7', 'C7', 'G7', 'G7', 'D7', 'C7', 'G7', 'D7')
    T.append(Tune('stlouis', 104, 4, 'swing', BL, choruses=3, key_center=-7, blues=True))
    # Tea for Two (1924) 코드 진행 — Ab → C
    TF = B(('Bbm7', 'Eb7'), ('Bbm7', 'Eb7'), 'Ab6', 'Ab6', ('Bbm7', 'Eb7'), ('Bbm7', 'Eb7'), 'Ab6', 'Ab6',
           ('Dm7', 'G7'), ('Dm7', 'G7'), 'C6', 'C6', ('Dm7', 'G7'), ('Dm7', 'G7'), 'C6', ('Bbm7', 'Eb7'))
    T.append(Tune('teafortwo', 126, 4, 'swing', TF, choruses=2, key_center=-8))
    # Bye Bye Blackbird (1926) 코드 진행 — F
    BB = B('F6', 'F6', ('Gm7', 'C7'), 'F6', 'F6', 'F7', 'Bb6', 'Bbm6', 'F6', 'D7', 'Gm7', 'C7', 'F6', ('Gm7', 'C7'), 'F6', ('Gm7', 'C7'))
    T.append(Tune('blackbird', 116, 4, 'swing', BB, choruses=2, key_center=-5))
    # Avalon (1920) 코드 진행 — C
    AV = B('G7', 'G7', 'C6', 'C6', 'G7', 'G7', 'C6', 'C6', 'A7', 'A7', 'Dm7', 'Dm7', 'D7', 'D7', 'G7', 'G7')
    T.append(Tune('avalon', 138, 4, 'swing', AV, choruses=2, key_center=0))
    # F 블루스 (미디엄 스윙)
    FB = B('F7', 'Bb7', 'F7', ('Cm7', 'F7'), 'Bb7', 'Bdim7', 'F7', ('Am7', 'D7'), 'Gm7', 'C7', ('F7', 'D7'), ('Gm7', 'C7'))
    T.append(Tune('fblues', 112, 4, 'swing', FB, choruses=3, key_center=-5, blues=True))
    # C 단조 블루스 (느리게)
    MB = B('Cm7', 'Fm7', 'Cm7', 'Cm7', 'Fm7', 'Fm7', 'Cm7', 'Cm7', 'Ab7', 'G7', 'Cm7', 'G7')
    T.append(Tune('minorblues', 92, 4, 'swing', MB, choruses=3, key_center=0, blues=True))
    return T


def save_wav(path, x):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


def make_all(out):
    os.makedirs(out, exist_ok=True)
    items = []
    conv = shutil.which('afconvert')
    for i, tu in enumerate(box_tunes()):
        x = render_box(tu, 5000 + i)
        base = os.path.join(out, f'jazz_{i:02d}')
        save_wav(base + '.wav', x)
        ext = 'wav'
        if conv:
            r = subprocess.run([conv, '-f', 'm4af', '-d', 'aac', '-b', '96000', base + '.wav', base + '.m4a'], capture_output=True)
            if r.returncode == 0 and os.path.exists(base + '.m4a'):
                os.remove(base + '.wav')
                ext = 'm4a'
        items.append({'file': f'jazz_{i:02d}', 'ext': ext, 'dur': round(len(x) / SR, 2), 'name': tu.name})
        print('오르골:', tu.name, round(len(x) / SR, 1), '초', flush=True)
    with open(os.path.join(out, 'jazz.json'), 'w') as f:
        json.dump(items, f, ensure_ascii=False)


if __name__ == '__main__':
    import sys
    make_all(sys.argv[1] if len(sys.argv) > 1 else '.')
