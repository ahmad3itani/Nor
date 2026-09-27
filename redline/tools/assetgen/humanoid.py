"""Generic side-view humanoid rig (facing right) on top of pixrig.

Pose keys (degrees / px):
  x, y        hip offset from the rest hip position
  lean        torso tilt, + = forward
  head        extra head tilt
  fa_s, fa_e  front arm: shoulder angle rel. to torso-down (+ = forward/up), elbow bend (+ = forward)
  ba_s, ba_e  back arm
  fl_h, fl_k  front leg: thigh angle from vertical (+ = forward), knee bend (+ = shin swings back)
  bl_h, bl_k  back leg
  f_toe, b_toe  foot tilt (+ = toe down)
  wpn         weapon angle relative to the forearm; wpn_on 0/1
  drag        coat/scarf backward drag (deg), lift = coat lift (+ = hem rises)
  ph          flutter phase (radians)
  ground      1 = snap lowest foot to the ground line
  crouch      extra torso drop (px) used for low poses
  torso_k, neck_k  optional torso / neck length scale (foreshortening in low poses; default 1)
  sh_x        optional shoulder x shift (torso twist, px; default 0)
"""
from __future__ import annotations

import math

from pixrig import Layer, Frame, dirv, add, mul, rot, lerp2, tup, tfwd, tdn

REST = dict(x=0, y=0, lean=0, head=0, fa_s=10, fa_e=15, ba_s=-8, ba_e=15,
            fl_h=4, fl_k=4, bl_h=-4, bl_k=4, f_toe=0, b_toe=0, wpn=0, wpn_on=1,
            drag=6, lift=0, ph=0.0, ground=1, flutter=1.0, arm_front=1)


class Skeleton:
    def __init__(self, dims: dict):
        # dims: hip(x,y) rest, thigh, shin, foot, torso, neck, head_r, uarm, farm, shoulder_drop
        self.d = dims

    def solve(self, p: dict) -> dict:
        d = self.d
        hip = (d["hip"][0] + p["x"], d["hip"][1] + p["y"])
        up = tup(p["lean"])  # torso direction (up, leaning forward)
        neck = add(hip, mul(up, d["torso"] * p.get("torso_k", 1.0)))
        head_c = add(neck, mul(tup(p["lean"] + p["head"]), d["neck"] * p.get("neck_k", 1.0)))
        sh = add(add(neck, mul(up, -d["shoulder_drop"])), (p.get("sh_x", 0), 0))
        j = dict(hip=hip, neck=neck, head=head_c, up=up, sh=sh)
        tdown = p["lean"]  # torso-down angle in limb convention (0=down) mirrored
        for side, s, e in (("fa", p["fa_s"], p["fa_e"]), ("ba", p["ba_s"], p["ba_e"])):
            ua = s + tdown * 0.25
            el = add(sh, dirv(ua, d["uarm"]))
            fa = ua + e
            ha = add(el, dirv(fa, d["farm"]))
            j[side] = (sh, el, ha, ua, fa)
        for side, h, k, toe in (("fl", p["fl_h"], p["fl_k"], p["f_toe"]), ("bl", p["bl_h"], p["bl_k"], p["b_toe"])):
            hp = add(hip, (0.5 if side == "fl" else -0.5, 0))
            kn = add(hp, dirv(h, d["thigh"]))
            sa = h - k
            an = add(kn, dirv(sa, d["shin"]))
            ft = add(an, tfwd(toe, d["foot"]))
            j[side] = (hp, kn, an, ft, h, sa)
        if p.get("ground", 1):
            low = max(j["fl"][2][1], j["bl"][2][1], j["fl"][3][1], j["bl"][3][1])
            dy = d["ground"] - low
            for k, v in list(j.items()):
                if k != "up":
                    j[k] = _shift_any(v, dy)
        return j


def _shift_any(v, dy):
    if isinstance(v, tuple) and len(v) == 2 and all(isinstance(t, (int, float)) for t in v):
        return (v[0], v[1] + dy) if v is not None else v
    if isinstance(v, tuple):
        return tuple(_shift_any(t, dy) if isinstance(t, tuple) else t for t in v)
    return v


def chain(start, base_deg, seg, n, drag, ph, amp, grow=0.0, lift=0.0):
    """A hanging cloth edge: n segments; angle bends backward with drag, flutters with phase."""
    pts = [start]
    p = start
    for i in range(n):
        a = base_deg - drag * (i + 1) / n - lift * (i + 1) / n + math.sin(ph + i * 1.3) * amp * (i + 1) / n
        p = add(p, dirv(a, seg * (1 + grow * i)))
        pts.append(p)
    return pts
