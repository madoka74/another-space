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
    rng = np.random.default_rng(seed)
    meter = tune.meter
    spb = 60.0 / tune.bpm
    form = chords_at(tune.bars, meter)
    reps = tune.choruses
    chs = form * reps
    nb = len(chs)
    # 박 → 초: 끝 두 마디는 태엽이 풀리듯 천천히 (리타르단도)
    slow0 = max(0, nb - meter * 2)

    def T(b):
        if b <= slow0:
            return b * spb
        k = (b - slow0) / max(1, nb - slow0)
        return slow0 * spb + (b - slow0) * spb * (1 + 0.45 * k * k)
    total = T(nb + meter) + 6.0
    n = int(SR * total)
    acc = np.zeros(n)
    mel_buf = np.zeros(n)
    tr = tune.key_center or 0                                       # 오르골 음역으로 옮김

    def put(buf, x, at):
        place(buf, x, at + rng.uniform(-0.004, 0.004))
    # 반주: 마디마다 화음을 낮은 음역에서 펼침 (근음 → 5음 → 3음 …)
    for bi in range(nb // meter):
        for half in range(2 if meter == 4 else 1):
            beat0 = bi * meter + half * 2
            sym = chs[min(nb - 1, beat0)]
            r, q = parse(sym)
            iv = QUAL.get(q, (0, 4, 7))
            root = 48 + ((r - 48) % 12) + tr
            while root > 55:
                root -= 12
            tones = [root, root + 7, root + 12 + iv[1], root + 12 + iv[2] if len(iv) > 2 else root + 19]
            if meter == 3:
                pat = [(0, tones[0], 0.62), (1, tones[1], 0.4), (1.5, tones[2], 0.34), (2, tones[3], 0.36), (2.5, tones[2], 0.3)]
            else:
                pat = [(0, tones[0], 0.6), (0.5, tones[1], 0.36), (1, tones[2], 0.34), (1.5, tones[3], 0.3)]
            for (b, m, v) in pat:
                put(acc, tine(mtof(m), v * rng.uniform(0.9, 1.05), rng), T(beat0 + b))
    # 멜로디: 긴 음은 오르골처럼 한 번 더 살짝 튕김, 박 첫 음엔 한 옥타브 아래를 겹쳐 두께
    for c in range(reps):
        for (b, ln, m) in tune.melody:
            bb = c * len(form) + b
            if bb < 0 or bb >= nb:
                continue
            mm = m + tr + 12
            v = 0.85 * rng.uniform(0.92, 1.05)
            put(mel_buf, tine(mtof(mm), v, rng), T(bb))
            if abs(bb - round(bb)) < 1e-6 and int(round(bb)) % meter == 0 and ln >= 1:
                put(mel_buf, tine(mtof(mm - 12), 0.32, rng), T(bb) + 0.012)
            if ln >= 2:
                put(mel_buf, tine(mtof(mm), 0.38, rng), T(bb + ln / 2))
    # 마지막 으뜸화음 (넓게 펼쳐 끝맺음)
    r0, q0 = parse(tune.bars[-1][-1])
    iv = QUAL.get(q0, (0, 4, 7))
    root = 48 + ((r0 - 48) % 12) + tr
    while root > 55:
        root -= 12
    for k, m in enumerate([root, root + 7, root + 12, root + 12 + iv[1], root + 19, root + 24]):
        put(acc, tine(mtof(m), 0.45, rng), T(nb) + k * 0.09)

    def norm(x):
        return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)
    out = 0.55 * norm(acc) + 0.9 * norm(mel_buf)
    # 나무 상자 울림: 아주 짧은 잔향 + 높은 소리 살짝 깎기
    ir_n = int(SR * 0.6)
    ir = rng.standard_normal(ir_n) * np.exp(-_t(ir_n) * 9)
    ir = np.convolve(ir, np.ones(8) / 8, mode='same')
    wet = np.fft.irfft(np.fft.rfft(out, n + ir_n) * np.fft.rfft(ir, n + ir_n), n + ir_n)[:n]
    out = out + norm(wet) * 0.18
    out = np.convolve(out, np.array([0.25, 0.5, 0.25]), mode='same')
    # 끝 소리가 다 사라진 뒤 자름
    end = int(SR * (T(nb) + 5.0))
    out = out[:end]
    fade = int(SR * 1.5)
    out[-fade:] *= np.linspace(1, 0, fade) ** 2
    return out / (np.max(np.abs(out)) + 1e-9) * 0.85


def box_tunes():
    T = []
    # 브람스 자장가 (1868) — C, 3박
    BL = B('C', 'C', 'C', 'F', 'C', 'G7', 'G7', 'G7', 'C', 'F', 'C', 'F', 'C', 'F', 'C', 'G7', 'C')
    BLm = mel([(None, 2), (64, 0.5), (64, 0.5),
               (67, 2), (64, 0.5), (64, 0.5), (67, 2), (64, 0.5), (67, 0.5), (72, 1), (71, 1.5), (69, 0.5), (69, 1), (67, 1), (62, 0.5), (64, 0.5),
               (65, 1), (62, 1), (62, 0.5), (64, 0.5), (65, 2), (62, 0.5), (65, 0.5), (71, 0.5), (69, 0.5), (67, 1), (71, 1), (72, 2), (60, 0.5), (60, 0.5),
               (72, 2), (69, 0.5), (65, 0.5), (67, 2), (64, 0.5), (60, 0.5), (65, 1), (67, 1), (69, 1), (67, 2), (60, 0.5), (60, 0.5),
               (72, 2), (69, 0.5), (65, 0.5), (67, 2), (64, 0.5), (60, 0.5), (65, 1), (64, 1), (62, 1), (60, 3)])
    T.append(Tune('lullaby', 76, 3, 'box', BL, melody=BLm, choruses=2, key_center=0))
    # 반짝반짝 작은 별 (프랑스 민요, 모차르트 변주곡 주제) — C, 4박
    TW = B(('C', 'C'), ('F', 'C'), ('F', 'C'), ('G7', 'C'), ('C', 'F'), ('C', 'G7'), ('C', 'F'), ('C', 'G7'), ('C', 'C'), ('F', 'C'), ('F', 'C'), ('G7', 'C'))
    seq = [60, 60, 67, 67, 69, 69, (67, 2), 65, 65, 64, 64, 62, 62, (60, 2), 67, 67, 65, 65, 64, 64, (62, 2), 67, 67, 65, 65, 64, 64, (62, 2),
           60, 60, 67, 67, 69, 69, (67, 2), 65, 65, 64, 64, 62, 62, (60, 2)]
    TWm = mel([x if isinstance(x, tuple) else (x, 1) for x in seq])
    T.append(Tune('twinkle', 92, 4, 'box', TW, melody=TWm, choruses=2, key_center=0))
    # 환희의 송가 (베토벤 9번, 1824) — C, 4박
    OD = B('C', 'G7', 'C', ('C', 'G7'), 'C', 'G7', 'C', ('G7', 'C'), ('G7', 'C'), ('G7', 'C'), ('G7', 'C'), ('C', 'G7'), 'C', 'G7', 'C', ('G7', 'C'))
    a = [(64, 1), (64, 1), (65, 1), (67, 1), (67, 1), (65, 1), (64, 1), (62, 1), (60, 1), (60, 1), (62, 1), (64, 1)]
    ODm = mel(a + [(64, 1.5), (62, 0.5), (62, 2)] + a + [(62, 1.5), (60, 0.5), (60, 2)]
              + [(62, 1), (62, 1), (64, 1), (60, 1), (62, 1), (64, 0.5), (65, 0.5), (64, 1), (60, 1),
                 (62, 1), (64, 0.5), (65, 0.5), (64, 1), (62, 1), (60, 1), (62, 1), (55, 2)]
              + a + [(62, 1.5), (60, 0.5), (60, 2)])
    T.append(Tune('ode', 100, 4, 'box', OD, melody=ODm, choruses=2, key_center=0))
    # 엘리제를 위하여 (베토벤, 1810) — A단조, 1박 = 8분음표
    FE = B('Am', 'E7', 'Am', 'E7', 'Am', 'E7', 'Am', 'E7', 'Am')
    b1 = [(76, 0.5), (75, 0.5), (76, 0.5), (71, 0.5), (74, 0.5), (72, 0.5)]
    FEm = mel([(None, 2), (76, 0.5), (75, 0.5)] + b1
              + [(69, 1), (None, 0.5), (60, 0.5), (64, 0.5), (69, 0.5), (71, 1), (None, 0.5), (64, 0.5), (68, 0.5), (71, 0.5),
                 (72, 1), (None, 0.5), (64, 0.5), (76, 0.5), (75, 0.5)] + b1
              + [(69, 1), (None, 0.5), (60, 0.5), (64, 0.5), (69, 0.5), (71, 1), (None, 0.5), (64, 0.5), (72, 0.5), (71, 0.5), (69, 3)])
    T.append(Tune('elise', 132, 3, 'box', FE, melody=FEm, choruses=3, key_center=-12))
    # 짐노페디 1번 (사티, 1888) — 느린 3박, Gmaj7 / Dmaj7 흔들림
    GY = B(*(['Gmaj7', 'Dmaj7'] * 10 + ['Gmaj7', 'D']))
    ph = [(None, 1), (78, 1), (81, 1), (79, 1), (78, 1), (73, 1), (71, 1), (73, 1), (74, 1), (69, 3)]
    GYm = mel([(None, 6)] + ph + [(66, 3), (None, 3), (None, 3)] + [(None, 3)] + ph + [(73, 3), (78, 3), (76, 3), (None, 3)]
              + [(74, 3), (73, 3), (71, 3), (74, 3)])
    T.append(Tune('gymnopedie', 72, 3, 'box', GY, melody=GYm, choruses=1, key_center=-12))
    # 파헬벨 카논 (1680년대) — D, 2박마다 화음
    CA = B(('D', 'A'), ('Bm', 'F#m'), ('G', 'D'), ('G', 'A'))
    c1 = [(78, 2), (76, 2), (74, 2), (73, 2), (71, 2), (69, 2), (71, 2), (73, 2)]
    c2 = [(74, 2), (73, 2), (71, 2), (69, 2), (67, 2), (66, 2), (67, 2), (64, 2)]
    c3 = [(74, 1), (78, 1), (81, 1), (79, 1), (78, 1), (74, 1), (78, 1), (76, 1), (74, 1), (71, 1), (74, 1), (81, 1), (79, 1), (83, 1), (81, 1), (79, 1)]
    CAm = mel(c1 + c2 + c3 + c1 + [(74, 8)])
    T.append(Tune('canon', 84, 4, 'box', CA * 4 + B('D', 'D'), melody=CAm, choruses=1, key_center=-12))
    # 그린슬리브스 (전통곡) — A단조, 3박
    GA = B('Am', 'C', 'G', 'Em', 'Am', 'E7', 'E7', 'Am', 'Am', 'C', 'G', 'Em', 'Am', 'E7', 'Am', 'Am',
           'C', 'G', 'G', 'Em', 'Am', 'E7', 'E7', 'Am', 'C', 'G', 'G', 'Em', 'Am', 'E7', 'Am', 'Am')
    GAm = mel([(None, 2), (69, 1),
               (72, 2), (74, 1), (76, 1.5), (77, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 2), (69, 1), (69, 1.5), (68, 0.5), (69, 1), (71, 2), (68, 1), (64, 2), (69, 1),
               (72, 2), (74, 1), (76, 1.5), (77, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 1.5), (71, 0.5), (69, 1), (68, 1.5), (66, 0.5), (68, 1), (69, 3), (69, 2), (None, 1),
               (79, 3), (79, 1.5), (78, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 2), (69, 1), (69, 1.5), (68, 0.5), (69, 1), (71, 2), (68, 1), (64, 3),
               (79, 3), (79, 1.5), (78, 0.5), (76, 1), (74, 2), (71, 1), (67, 1.5), (69, 0.5), (71, 1),
               (72, 1.5), (71, 0.5), (69, 1), (68, 1.5), (66, 0.5), (68, 1), (69, 3)])
    T.append(Tune('greensleeves', 96, 3, 'box', GA, melody=GAm, choruses=1, key_center=-12))
    # 어메이징 그레이스 (전통곡) — G, 3박
    AG = B('G', 'G', 'G', 'D7', 'G', 'G7', 'C', 'G', 'G', 'Em', 'D7', 'D7', 'G', 'C', 'G', 'G')
    AGm = mel([(None, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 2), (64, 1), (62, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (74, 3), (74, 2), (71, 1),
               (74, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 2), (64, 1), (62, 2), (62, 1),
               (67, 2), (71, 0.5), (67, 0.5), (71, 2), (69, 1), (67, 3)])
    T.append(Tune('grace', 66, 3, 'box', AG, melody=AGm, choruses=2, key_center=0))
    # 성자들의 행진 (전통곡) — F, 느긋하게
    SA = B('F', 'F', 'F', 'F', 'F', 'F', 'C7', 'C7', 'F', 'F7', 'Bb', 'Bbm6', 'F', 'C7', 'F', 'F')
    SAm = mel([(None, 1), (65, 1), (69, 1), (70, 1),
               (72, 4), (None, 1), (65, 1), (69, 1), (70, 1), (72, 4), (None, 1), (65, 1), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (69, 2), (67, 4), (None, 1), (69, 1), (69, 1), (67, 1),
               (65, 3), (65, 1), (69, 2), (72, 2), (72, 2), (70, 2), (None, 2), (69, 1), (70, 1),
               (72, 2), (69, 2), (65, 2), (67, 2), (65, 4)])
    T.append(Tune('saints', 104, 4, 'box', SA, melody=SAm, choruses=2, key_center=-5))
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
