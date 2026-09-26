"""NG+ remix data for Act I (M9 D3 §2.6, D-154): writes one RoomRemix file per
room, data/remix/<RoomBasename>.tres, from the single table below.

    python3 -B tools/roomgen/remix_act1.py           # write data/remix/*.tres
    python3 -B tools/roomgen/remix_act1.py --check   # exit 1 if a file drifted

Ops name nodes of the current room scenes. A room generator that renames a
node (Needle3 -> Needle4) turns the op into a RemixRules RM-2 error, never a
silent no-op: after any room edit run ValidateContent and this --check.
Wake (the calm waking beat) and the Relay (the hub) have no remix.
The variant EnemyData files (*_remix) keep scrap_drop 0 (RM-5); a SET/SWAP
replacement pays the replaced enemy's drop at runtime (R09.11).
Python 3 standard library only.
"""
import os, sys

CHECK = "--check" in sys.argv
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = "data/remix/"
UC = "res://world/rooms/undercity/"
LL = "res://world/rooms/lowlight/"
ACTIVE = "flag:ng_remix"

# Op helpers: each returns a dict the renderer turns into a RemixOp.
def enemy_data(name): return ("res", "res://data/enemies/%s.tres" % name)
def level(name): return ("res", "res://data/level/%s.tres" % name)
def scene(path): return ("scene", path)
def names(*ids): return ("names", list(ids))
def vecs(*pts): return ("vecs", list(pts))

def set_(target, prop, value): return {"kind": 3, "target": target, "property": prop, "value": value}
def swap(target, kind, data): return {"kind": 2, "target": target, "scene_kind": kind, "data": enemy_data(data)}
def add(beside, kind, data, dx, dy=0): return {"kind": 0, "target": beside, "scene_kind": kind, "data": enemy_data(data), "offset": (dx, dy)}
def data_of(target, variant): return set_(target, "data", enemy_data(variant))

E = "Enemies/"
ROOMS = [
    (UC + "MedicalRuin.tscn", "The first fight already combines: a faster Needle and a Hopper. Needle1 stays the dormant practice dummy.", [
        data_of(E + "Needle3", "needle_remix"),
        swap(E + "Needle4", "Hopper", "hopper_remix"),
    ]),
    (UC + "MaintenanceShaft.tscn", "Floor 2 is a three-body composition under two drones that fire pairs.", [
        data_of(E + "ScoutDrone1", "scout_drone_remix"),
        data_of(E + "ScoutDrone2", "scout_drone_remix"),
        add(E + "Needle2", "Needle", "needle_remix", 56),
    ]),
    (UC + "FirstPursuit.tscn", "A Shield under the eye: get behind it while moving.", [
        swap(E + "Needle1", "Shield", "shield_remix"),
    ]),
    (UC + "BrokenLift.tscn", "The teaching Flow Zone becomes a real zone.", [
        data_of(E + "Needle1", "needle_ledge_remix"),
        set_("Zones/Flow1", "drain_scale", 1.0),
        set_("Zones/Flow1", "drain_floor", 0.0),
    ]),
    (UC + "CollectorBay.tscn", "A known fight in a new order; phase 2 comes sooner and moves faster.", [
        data_of(E + "CollectorDrone1", "collector_drone_remix"),
        set_(E + "CollectorDrone1/Behavior", "phase2_threshold", 0.6),
        set_(E + "CollectorDrone1/Behavior", "phase2_speed_mult", 1.3),
        set_(E + "CollectorDrone1/Behavior", "first_deck", names("collector_tag_volley", "collector_claw_dive", "collector_drop_press", "collector_hook_sweep")),
        set_(E + "CollectorDrone1/Behavior", "rng_seed", 23),
    ]),
    (UC + "EscapeTunnel.tscn", "The first elite, before the Relay.", [
        data_of(E + "Watcher1", "watcher_remix"),
        add(E + "Hopper1", "Enforcer", "enforcer_remix", 80),
    ]),
    (LL + "FloodedAlley.tscn", "The alley pair becomes a pounce and a flank.", [
        swap(E + "Needle2", "Hopper", "hopper_remix"),
        add(E + "Needle1", "Needle", "needle_remix", -64),
    ]),
    (LL + "MarketRun.tscn", "Faster Needles around a Shield in the stalls.", [
        data_of(E + "Needle1", "needle_remix"),
        data_of(E + "Needle2", "needle_remix"),
        data_of(E + "Needle3", "needle_remix"),
        swap(E + "Hopper2", "Shield", "shield_remix"),
    ]),
    (LL + "ApartmentStack.tscn", "Vertical crossfire.", [
        swap(E + "Needle3", "Watcher", "watcher_remix"),
        data_of(E + "ScoutDrone1", "scout_drone_remix"),
        data_of(E + "ScoutDrone2", "scout_drone_remix"),
    ]),
    (LL + "NeonRoofs.tscn", "An elite on the roofs, Watchers firing sooner.", [
        swap(E + "Needle2", "Enforcer", "enforcer_remix"),
        data_of(E + "Watcher1", "watcher_remix"),
        data_of(E + "Watcher2", "watcher_remix"),
        data_of(E + "Watcher3", "watcher_remix"),
    ]),
    (LL + "PowerBlock.tscn", "A tighter Grid on the same routes (shutter margins stay above the D-099 floor).", [
        set_("Geometry/Shutter_S2", "timing", level("shutter_run_remix")),
        set_("Geometry/Shutter_S3", "timing", level("shutter_run_remix")),
        set_("Geometry/Shutter_S4a", "timing", level("shutter_l3_remix")),
        set_("Geometry/Shutter_S4b", "timing", level("shutter_l3_remix")),
        data_of(E + "Needle1", "needle_remix"),
        data_of(E + "Needle2", "needle_remix"),
    ]),
    (LL + "SecurityStation.tscn", "Faster sweeps in the lobby; the calibration lane is untouched (tutorial).", [
        set_("Hazards/Scanner_ss_full_1", "data", level("scanner_full_pulse_10_remix")),
        set_("Hazards/Scanner_ss_high_2", "phase", 0.5),
        swap(E + "Hopper1", "Shield", "shield_remix"),
    ]),
    (LL + "RainlineChase.tscn", "The Sweeper runs a little hotter.", [
        set_("Triggers/Chase_rainline", "data", ("res", "res://data/world/chase/rainline_remix.tres")),
        data_of(E + "Needle1", "needle_remix"),
        data_of(E + "Needle2", "needle_remix"),
    ]),
    (LL + "SmugglerRoute.tscn", "A quicker pump shutter and a second drone over the den.", [
        set_("Geometry/Shutter_SR", "timing", level("shutter_run_remix")),
        add(E + "ScoutDrone1", "ScoutDrone", "scout_drone_remix", 120, -20),
    ]),
    (LL + "BellTower.tscn", "Two elites in the tower.", [
        swap(E + "Shield2", "Enforcer", "enforcer_remix"),
        data_of(E + "Hopper1", "hopper_remix"),
    ]),
    (LL + "WardenTower.tscn", "Summons change, phase 2 comes earlier, the clamp punish comes back sooner.", [
        data_of(E + "WardenKrail1", "warden_krail_remix"),
        set_(E + "WardenKrail1/Behavior", "phase2_threshold", 0.65),
        set_(E + "WardenKrail1/Behavior", "phase2_telegraph_scale", 0.75),
        set_(E + "WardenKrail1/Behavior", "summon_scene", scene("res://enemies/variants/Hopper.tscn")),
        set_(E + "WardenKrail1/Behavior", "summon_offsets", vecs((-170, 0), (170, 0), (0, -40))),
        set_(E + "WardenKrail1/Behavior", "phase_pause", 0.9),
        set_("Geometry/Clamp_wt_clamp", "timing", ("res", "res://data/level/clamp_krail_remix.tres")),
    ]),
]


def q(s): return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
def num(v):
    """Ints print as ints, floats always with a decimal point (Godot reads 1 as int)."""
    if isinstance(v, int):
        return "%d" % v
    s = "%g" % v
    return s if "." in s or "e" in s else s + ".0"


def render(room, intent, ops):
    ext = {"RoomRemix": ("Script", "res://world/remix/RoomRemix.gd"), "RemixOp": ("Script", "res://world/remix/RemixOp.gd")}
    order = ["RoomRemix", "RemixOp"]

    def res_id(kind, path):
        key = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        if key not in ext:
            ext[key] = (kind, path)
            order.append(key)
        return 'ExtResource("%s")' % key

    def value(v):
        if isinstance(v, tuple):
            tag, arg = v
            if tag == "res":
                return res_id("Resource", arg)
            if tag == "scene":
                return res_id("PackedScene", arg)
            if tag == "names":
                return "Array[StringName]([%s])" % ", ".join("&" + q(n) for n in arg)
            if tag == "vecs":
                return "Array[Vector2]([%s])" % ", ".join("Vector2(%s, %s)" % (num(x), num(y)) for x, y in arg)
        if isinstance(v, bool):
            return "true" if v else "false"
        return num(v)

    subs = []
    for i, op in enumerate(ops):
        lines = ['[sub_resource type="Resource" id="Op%d"]' % (i + 1), 'script = ExtResource("RemixOp")', 'kind = %d' % op["kind"],
                 'target = NodePath(%s)' % q(op["target"])]
        if "scene_kind" in op:
            lines.append('scene_kind = %s' % q(op["scene_kind"]))
        if "data" in op:
            lines.append('data = %s' % value(op["data"]))
        if "offset" in op:
            lines.append('offset = Vector2(%s, %s)' % (num(op["offset"][0]), num(op["offset"][1])))
        if "property" in op:
            lines.append('property = &%s' % q(op["property"]))
            lines.append('value = %s' % value(op["value"]))
        subs.append("\n".join(lines))
    out = ['[gd_resource type="Resource" script_class="RoomRemix" load_steps=%d format=3]' % (len(order) + len(ops) + 1), '']
    for k in order:
        t, p = ext[k]
        out.append('[ext_resource type="%s" path="%s" id="%s"]' % (t, p, k))
    out.append('')
    for s in subs:
        out += [s, '']
    out += ['[resource]', 'script = ExtResource("RoomRemix")', 'room = %s' % q(room), 'active_when = %s' % q(ACTIVE),
            'ops = Array[ExtResource("RemixOp")]([%s])' % ", ".join('SubResource("Op%d")' % (i + 1) for i in range(len(ops))),
            'intent = %s' % q(intent), '']
    return "\n".join(out)


def main():
    drift = []
    for room, intent, ops in ROOMS:
        path = os.path.join(ROOT, OUT, room.rsplit("/", 1)[-1].replace(".tscn", ".tres"))
        text = render(room, intent, ops)
        if CHECK:
            try:
                current = open(path).read()
            except OSError:
                current = None
            if current != text:
                drift.append(os.path.relpath(path, ROOT))
            continue
        open(path, "w").write(text)
    if CHECK:
        if drift:
            print("remix files differ from the script: " + ", ".join(drift))
            sys.exit(1)
        print("all remix files match the script")
    else:
        print("remix files written")


if __name__ == "__main__":
    main()
