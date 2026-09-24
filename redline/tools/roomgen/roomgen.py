"""Room authoring helper (M6 content pipeline): builds REDLINE Room .tscn
files from compact layout calls (block, oneway, spawn, exit, anchor, npc,
enemy, collectible, wall, hint, neon, decor, gate, mapmarker, switch...).
Python 3 standard library only. See tools/roomgen/lowlight.py for usage and
Docs/CONTENT_PIPELINE.md for the conventions (48 px steps, doorways...).
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

LL = "res://world/rooms/lowlight/"
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
}
SCENES = {n: "res://enemies/variants/%s.tscn" % n for n in ["Needle", "Shield", "ScoutDrone", "Hopper", "Watcher", "Enforcer"]}
SCENES["WardenKrail"] = "res://bosses/WardenKrail.tscn"
SCENES["DashModule"] = "res://interactables/DashModule.tscn"

def q(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'

class RoomGen:
    def __init__(self, name, bounds, theme, district, room_name):
        self.name, self.bounds, self.theme, self.district, self.room_name = name, bounds, theme, district, room_name
        self.ext = {}
        self.nodes = []  # (parent, name, type, props list)
        self.counts = {}
        for group in ["Geometry", "Hazards", "Zones", "Props", "Interactables", "Enemies", "Spawns", "Triggers"]:
            self.nodes.append((".", group, "Node2D", []))
        self._res("director", "Script", SCRIPTS["director"])
        self.nodes.append((".", "EncounterDirector", "Node", ['script = ExtResource("director")']))

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
             'target_room = %s' % q(LL + target + ".tscn"), 'target_entry = &%s' % q(entry)]
        if flag: p.append('requires_flag = %s' % q(flag))
        return self.add("Triggers", "Exit", "Area2D", p)
    def anchor(self, aid, x, y, facing=1):
        self.spawn(aid, x, y, facing)
        return self.add("Interactables", "Anchor", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("anchor"), 'anchor_id = &%s' % q(aid)])
    def npc(self, profile, x, y, facing=-1):
        prof = self._res("npc_" + profile, "Resource", "res://data/npcs/%s.tres" % profile)
        return self.add("Interactables", "NPC_" + profile, "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("npc"), 'profile = %s' % prof, 'facing = %d' % facing], "NPC_" + profile)
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
    def enemy(self, kind, x, y, facing=-1):
        sc = self._res("scene_" + kind, "PackedScene", SCENES[kind])
        p = ['position = Vector2(%d, %d)' % (x, y)]
        if facing != -1: p.append('facing = %d' % facing)
        return self.add("Enemies", kind, "", p + ['__instance__ = %s' % sc])
    def flow(self, x, y, w, h):
        return self.add("Zones", "Flow", "Area2D", ['position = Vector2(%d, %d)' % (x, y), 'script = %s' % self._script("flow"), 'size = Vector2(%d, %d)' % (w, h)])
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

    def raw(self, parent, name, typ, props):
        self.nodes.append((parent, name, typ, props))

    def write(self, path):
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
        text = "\n".join(out)
        if CHECK:
            try:
                current = open(path).read()
            except OSError:
                current = None
            if current != text:
                _drift.append(path)
            return
        open(path, "w").write(text)
