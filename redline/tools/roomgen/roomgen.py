"""Room authoring helper (M6 content pipeline): builds REDLINE Room .tscn
files from compact layout calls (block, oneway, spawn, exit, anchor, npc,
enemy, collectible, wall, hint, neon, decor, gate, mapmarker, switch...).
Python 3 standard library only. See tools/roomgen/lowlight.py for usage and
Docs/CONTENT_PIPELINE.md for the conventions (48 px steps, doorways...).

M7 helper contract (binding for every room generator; property names are
what the node scripts export): weapon_pickup, tracker, breaker, shutter,
clamp, scanner, chase, respawn_point, declare_flags. Exit targets containing
"/" are folder-qualified ("undercity/Wake"); bare names stay in Lowlight.
Scripts named here are only loaded when a room uses the helper, so they can
land with the task that owns them.
"""
import sys

CHECK = "--check" in sys.argv
_drift = []


def finish():
    """Call at the end of a room script: reports drift in --check mode."""
    if CHECK:
        if _drift:
            print("rooms differ from the script: " + ", ".join(_drift))
            sys.exit(1)
        print("all rooms match the script")
    else:
        print("rooms written")

ROOMS = "res://world/rooms/"
LL = ROOMS + "lowlight/"
SCRIPTS = {
 "room": "res://world/rooms/Room.gd", "block": "res://world/graybox/GrayboxBlock.gd",
 "spawn": "res://world/rooms/SpawnMarker.gd", "exit": "res://world/transitions/RoomExit.gd",
 "anchor": "res://world/anchors/Anchor.gd", "npc": "res://interactables/NPC.gd",
 "repeater": "res://interactables/SignalRepeater.gd", "collect": "res://interactables/Collectible.gd",
 "wall": "res://interactables/BreakableWall.gd", "spikes": "res://world/hazards/SpikeHazard.gd",
 "flow": "res://world/rooms/FlowZone.gd", "hint": "res://world/props/HintTrigger.gd",
 "neon": "res://world/props/NeonSign.gd", "lever": "res://interactables/FlagSwitch.gd",
 "gate": "res://world/transitions/Gate.gd", "arena": "res://bosses/BossArena.gd",
 "director": "res://enemies/base/EncounterDirector.gd",
 "marker": "res://world/map/MapMarker.gd", "switch": "res://world/props/WorldStateSwitch.gd",
 # M7 set pieces.
 "breaker": "res://interactables/Breaker.gd", "shutter": "res://world/transitions/PowerShutter.gd",
 "clamp": "res://world/transitions/GridClamp.gd", "scanner": "res://world/hazards/ScannerBeam.gd",
 "chase": "res://world/hazards/ChaseDirector.gd", "chase_cp": "res://world/hazards/ChaseCheckpoint.gd",
 "respawn": "res://interactables/EntryCheckpoint.gd", "flagdecl": "res://world/rooms/FlagDeclaration.gd",
}
SCENES = {n: "res://enemies/variants/%s.tscn" % n for n in ["Needle", "Shield", "ScoutDrone", "Hopper", "Watcher", "Enforcer"]}
SCENES["WardenKrail"] = "res://bosses/WardenKrail.tscn"
SCENES["DashModule"] = "res://interactables/DashModule.tscn"
SCENES["CollectorDrone"] = "res://bosses/CollectorDrone.tscn"
SCENES["PulseBladeRack"] = "res://interactables/PulseBladeRack.tscn"
SCENES["ServicePistolDrop"] = "res://interactables/ServicePistolDrop.tscn"
SCENES["CollectorEye"] = "res://world/props/CollectorEye.tscn"

def q(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'
def num(v):
    """Integral values print as ints (like the rest of the file), others as %g."""
    return "%d" % v if float(v).is_integer() else "%g" % v
def strings(items): return "PackedStringArray(%s)" % ", ".join(q(i) for i in items)

class RoomGen:
    def __init__(self, name, bounds, theme, district, room_name, max_attackers=2):
        self.name, self.bounds, self.theme, self.district, self.room_name = name, bounds, theme, district, room_name
        self.ext = {}
        self.nodes = []  # (parent, name, type, props list)
        self.counts = {}
        for group in ["Geometry", "Hazards", "Zones", "Props", "Interactables", "Enemies", "Spawns", "Triggers"]:
            self.nodes.append((".", group, "Node2D", []))
        self._res("director", "Script", SCRIPTS["director"])
        director = ['script = ExtResource("director")']
        # Undercity rooms cap simultaneous attackers lower (one concept at a time).
        if max_attackers != 2: director.append('max_attackers = %d' % max_attackers)
        self.nodes.append((".", "EncounterDirector", "Node", director))

    def _res(self, key, typ, path):
        if key not in self.ext:
            self.ext[key] = (typ, path)
        return 'ExtResource("%s")' % key

    def _script(self, k): return self._res(k, "Script", SCRIPTS[k])

    def _name(self, base):
        self.counts[base] = self.counts.get(base, 0) + 1
        return "%s%d" % (base, self.counts[base])

    def add(self, parent, base, typ, props, name=None):
        n = name or self._name(base)
        assert all(not (pp == parent and nn == n) for pp, nn, _, _ in self.nodes), "duplicate node %s/%s" % (parent, n)
        self.nodes.append((parent, n, typ, props))
        return n

    def block(self, x, y, w, h, name=None):
        return self.add("Geometry", "Block", "StaticBody2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("block"), 'size = Vector2(%d, %d)' % (w, h)], name)
    def oneway(self, x, y, w):
        return self.add("Geometry", "OneWay", "StaticBody2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("block"), 'size = Vector2(%d, 8)' % w, 'one_way = true'])
    def spikes(self, x, y, w):
        return self.add("Hazards", "Spikes", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("spikes"), 'size = Vector2(%d, 8)' % w])
    def wall(self, pid, x, y, w, h, hp=30, heavy=False, scrap=0):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("wall"), 'size = Vector2(%d, %d)' % (w, h), 'persist_id = %s' % q(pid), 'max_health = %.1f' % hp]
        if heavy: p.append('needs_heavy = true')
        if scrap: p.append('scrap_inside = %d' % scrap)
        return self.add("Geometry", "Breakable", "StaticBody2D", p)
    def spawn(self, sid, x, y, facing=1, default=False, label=""):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("spawn"), 'spawn_id = &%s' % q(sid)]
        if default: p.append('is_default = true')
        if facing != 1: p.append('facing = %d' % facing)
        if label: p.append('label = %s' % q(label))
        return self.add("Spawns", "Spawn_", "Marker2D", p, "Spawn_" + sid)
    def exit(self, x, y, w, h, target, entry, flag=""):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("exit"), 'size = Vector2(%d, %d)' % (w, h),
             'target_room = %s' % q((ROOMS if "/" in target else LL) + target + ".tscn"), 'target_entry = &%s' % q(entry)]
        if flag: p.append('requires_flag = %s' % q(flag))
        return self.add("Triggers", "Exit", "Area2D", p)
    def anchor(self, aid, x, y, facing=1):
        self.spawn(aid, x, y, facing)
        return self.add("Interactables", "Anchor", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("anchor"), 'anchor_id = &%s' % q(aid)])
    def npc(self, profile, x, y, facing=-1, present_when=()):
        prof = self._res("npc_" + profile, "Resource", "res://data/npcs/%s.tres" % profile)
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("npc"), 'profile = %s' % prof, 'facing = %d' % facing]
        if present_when: p.append('present_when = %s' % strings(present_when))
        return self.add("Interactables", "NPC_" + profile, "Area2D", p, "NPC_" + profile)
    def repeater(self, flag, x, y):
        return self.add("Interactables", "Repeater", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("repeater"), 'flag_id = %s' % q(flag)])
    def lever(self, flag, x, y, text=""):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("lever"), 'flag_id = %s' % q(flag)]
        if text: p.append('used_text = %s' % q(text))
        return self.add("Interactables", "Lever", "Area2D", p)
    def collectible(self, kind, pid, x, y, scrap=25, fragment=None):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("collect"), 'persist_id = %s' % q(pid), 'kind = %d' % kind]
        if kind == 0: p.append('scrap_amount = %d' % scrap)
        if fragment: p.append('fragment = %s' % self._res("frag_" + fragment, "Resource", "res://data/lore/%s.tres" % fragment))
        return self.add("Interactables", "Collectible", "Area2D", p)
    def enemy(self, kind, x, y, facing=-1, ai=True, data=""):
        sc = self._res("scene_" + kind, "PackedScene", SCENES[kind])
        p = ['position = Vector2(%d, %d)' % (x, y)]
        if facing != -1: p.append('facing = %d' % facing)
        if not ai: p.append('ai_enabled = false')
        # A data variant (e.g. needle_dormant: no scrap) on the same scene.
        if data: p.append('data = %s' % self._res("enemy_" + data, "Resource", "res://data/enemies/%s.tres" % data))
        return self.add("Enemies", kind, "", p + ['__instance__ = %s' % sc])
    def flow(self, x, y, w, h, drain_scale=1.0, drain_floor=0.0):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("flow"), 'size = Vector2(%d, %d)' % (w, h)]
        # Gentle teaching zones drain slower and never below a floor (M2).
        if drain_scale != 1.0: p.append('drain_scale = %.2f' % drain_scale)
        if drain_floor != 0.0: p.append('drain_floor = %.1f' % drain_floor)
        return self.add("Zones", "Flow", "Area2D", p)
    def hint(self, hid, x, y, w, h, text, action=""):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("hint"), 'size = Vector2(%d, %d)' % (w, h), 'hint_id = %s' % q(hid), 'text = %s' % q(text)]
        if action: p.append('action = &%s' % q(action))
        return self.add("Triggers", "Hint", "Area2D", p)
    def mapmarker(self, x, y, label, resolved_when, kind=0):
        return self.add("Props", "MapMarker", "Node2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("marker"),
            'kind = %d' % kind, 'label = %s' % q(label), 'resolved_when = %s' % q(resolved_when)])
    def switch(self, name, condition):
        self.add("Props", name, "Node2D", ['script = %s' % self._script("switch"), 'visible_when = %s' % q(condition)], name)
        return "Props/" + name
    def neon(self, x, y, w, h, color, strokes=3, flicker=True, parent="Props"):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("neon"), 'size = Vector2(%d, %d)' % (w, h), 'color = Color(%s)' % color, 'strokes = %d' % strokes]
        if not flicker: p.append('flicker = false')
        return self.add(parent, "Neon", "Node2D", p)
    def gate(self, x, y, w, h, closed=False, open_flag="", name=None):
        p = ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("gate"), 'size = Vector2(%d, %d)' % (w, h)]
        if closed: p.append('closed = true')
        if open_flag: p.append('open_flag = %s' % q(open_flag))
        return self.add("Geometry", "Gate", "StaticBody2D", p, name)
    KIND = {"pillar": 0, "lamp": 1, "crates": 2, "bench": 3, "train": 4, "radio": 5, "workbench": 6, "pipes": 7, "ac": 8, "banner": 9, "planter": 10, "cables": 11}
    def decor(self, kind, x, y, w, h, color="0.23, 0.2, 0.28, 1", accent="1, 0.81, 0.35, 1", parent="Props"):
        return self.add(parent, "Decor", "Node2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._res("decor", "Script", "res://world/props/Decor.gd"),
            'kind = %d' % self.KIND[kind], 'size = Vector2(%d, %d)' % (w, h), 'color = Color(%s)' % color, 'accent = Color(%s)' % accent])

    # --- M7 set-piece helpers (text only; the property names are a contract) ---
    def weapon_pickup(self, scene, weapon_id, flag, x, y):
        sc = self._res("scene_" + scene, "PackedScene", SCENES[scene])
        return self.add("Interactables", "Pickup_", "", ['position = Vector2(%d, %d)' % (x, y), 'weapon_id = %s' % q(weapon_id),
            'flag_id = %s' % q(flag), '__instance__ = %s' % sc], "Pickup_" + weapon_id)
    def tracker(self, name, rail, y, wake_x, lost_x, config, visible_when=""):
        sc = self._res("scene_CollectorEye", "PackedScene", SCENES["CollectorEye"])
        p = ['position = Vector2(%s, %s)' % (num(rail[0]), num(y)), 'rail_min = %s' % num(rail[0]), 'rail_max = %s' % num(rail[1]),
             'wake_x = %s' % num(wake_x), 'lost_x = %s' % num(lost_x),
             'config = %s' % self._res("props_" + config, "Resource", "res://data/props/%s.tres" % config)]
        if visible_when: p.append('visible_when = %s' % q(visible_when))
        return self.add("Hazards", name, "", p + ['__instance__ = %s' % sc], name)
    def breaker(self, bid, circuit, x, y):
        """(x, y) is the top-left of the 16x24 breaker box."""
        return self.add("Interactables", "Breaker_", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("breaker"),
            'breaker_id = %s' % q(bid), 'circuit = &%s' % q(circuit)], "Breaker_" + bid)
    def shutter(self, sid, x, y, w, h, circuit, timing, latch_flag):
        return self.add("Geometry", "Shutter_", "StaticBody2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("shutter"),
            'size = Vector2(%d, %d)' % (w, h), 'shutter_id = %s' % q(sid), 'circuit = &%s' % q(circuit),
            'timing = %s' % self._level(timing), 'latch_flag = %s' % q(latch_flag)], "Shutter_" + sid)
    def clamp(self, cid, x, top_y, width, raised_bottom, timing, circuits, hint_id="", hint=""):
        p = ['position = Vector2(%d, %d)' % (x, top_y), 'script = %s' % self._script("clamp"), 'clamp_id = %s' % q(cid),
             'width = %s' % num(width), 'raised_bottom = %s' % num(raised_bottom), 'timing = %s' % self._level(timing),
             'circuits = Array[StringName]([%s])' % ", ".join("&" + q(c) for c in circuits),
             'attack = %s' % self._res("clamp_attack", "Resource", "res://data/combat/grid_clamp_attack.tres")]
        if hint_id:
            p.append('arm_hint_id = %s' % q(hint_id))
            p.append('arm_hint = %s' % q(hint))
        return self.add("Geometry", "Clamp_", "StaticBody2D", p, "Clamp_" + cid)
    def scanner(self, sid, x, data, top_y, bottom_y, circuit="", offline_open=5.5, offline_warn=1.5, phase=0.0):
        p = ['position = Vector2(%d, 0)' % x, 'script = %s' % self._script("scanner"), 'beam_id = %s' % q(sid),
             'data = %s' % self._level("scanner_" + data), 'top_y = %s' % num(top_y), 'bottom_y = %s' % num(bottom_y)]
        if circuit: p.append('circuit = &%s' % q(circuit))
        if offline_open != 5.5: p.append('offline_open = %.2f' % offline_open)
        if offline_warn != 1.5: p.append('offline_warn = %.2f' % offline_warn)
        if phase: p.append('phase = %.2f' % phase)
        return self.add("Hazards", "Scanner_", "Area2D", p, "Scanner_" + sid)
    def chase(self, cid, data, path, speed_scale, start_area, end_area, checkpoints):
        name = self.add("Triggers", "Chase_", "Node2D", ['script = %s' % self._script("chase"), 'chase_id = %s' % q(cid),
            'data = %s' % self._res("chase_" + data, "Resource", "res://data/world/chase/%s.tres" % data),
            'path = PackedVector2Array(%s)' % ", ".join("%s, %s" % (num(px), num(py)) for px, py in path),
            'speed_scale = PackedFloat32Array(%s)' % ", ".join(num(v) for v in speed_scale),
            'start_area = Rect2(%s)' % ", ".join(num(v) for v in start_area),
            'end_area = Rect2(%s)' % ", ".join(num(v) for v in end_area)], "Chase_" + cid)
        for i, (cx, cy) in enumerate(checkpoints):
            self.add("Triggers/" + name, "CP", "Marker2D", ['position = Vector2(%d, %d)' % (cx, cy), 'script = %s' % self._script("chase_cp")], "CP%d" % (i + 1))
        return name
    def respawn_point(self, spawn_id, x, y, w, h):
        """Mid-room checkpoint; the room must also spawn(spawn_id, ...)."""
        return self.add("Triggers", "Respawn_", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("respawn"),
            'size = Vector2(%d, %d)' % (w, h), 'spawn_id = &%s' % q(spawn_id)], "Respawn_" + spawn_id)
    def declare_flags(self, *flags):
        """Stub rooms only: stands in for flags a later room will set."""
        return self.add("Triggers", "FlagDeclaration", "Node", ['script = %s' % self._script("flagdecl"), 'produces = %s' % strings(flags)], "FlagDeclaration")
    def _level(self, name):
        return self._res("level_" + name, "Resource", "res://data/level/%s.tres" % name)

    def raw(self, parent, name, typ, props):
        self.nodes.append((parent, name, typ, props))

    def write(self, path):
        text = self.render()
        if CHECK:
            try:
                current = open(path).read()
            except OSError:
                current = None
            if current != text:
                _drift.append(path)
            return
        open(path, "w").write(text)

    def render(self):
        """The scene text write() would produce (fixture self-tests read it)."""
        keys = list(self.ext.keys())
        room_script = self._script("room")
        theme = self._res("theme", "Resource", "res://data/districts/%s.tres" % self.theme)
        keys = list(self.ext.keys())
        out = ['[gd_scene load_steps=%d format=3]' % (len(keys) + 1), '']
        for k in keys:
            t, p = self.ext[k]
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, k))
        out += ['', '[node name="%s" type="Node2D"]' % self.name, 'script = %s' % room_script,
                'room_name = %s' % q(self.room_name), 'bounds = Rect2(%d, %d, %d, %d)' % self.bounds,
                'draw_grid = false', 'world_room = true', 'district_name = %s' % q(self.district), 'theme = %s' % theme, '']
        for parent, name, typ, props in self.nodes:
            inst = [p for p in props if p.startswith('__instance__')]
            props = [p for p in props if not p.startswith('__instance__')]
            if inst:
                out.append('[node name="%s" parent="%s" instance=%s]' % (name, parent, inst[0].split(' = ')[1]))
            else:
                out.append('[node name="%s" type="%s" parent="%s"]' % (name, typ, parent))
            out += props
            out.append('')
        return "\n".join(out)
