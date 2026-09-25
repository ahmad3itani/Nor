"""M7 scaffold test fixtures, written with roomgen, plus a self-test of the
M7 helper contract.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_scaffold.py             # write tests/fixtures/scaffold_*.tscn (incl. scaffold_m8_*)
    python3 -B tools/roomgen/fixtures_scaffold.py --check     # self-test, then exit 1 if the fixtures drifted
    python3 -B tools/roomgen/fixtures_scaffold.py --selftest  # only the in-memory helper assertions

The self-test builds throwaway rooms in memory and asserts on the emitted
node text: the room scripts those helpers name (ScannerBeam, GridClamp...)
land in later tasks, so no fixture scene can use them yet.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roomgen import RoomGen, finish
from undercity_style import BIG

OUT = "tests/fixtures/"


def _gen(name="T", max_attackers=2):
    return RoomGen(name, (0, -270, 480, 400), "undercity", "Test", "Test", max_attackers)


def _node(text, name):
    """The block of lines of the node called `name` in a rendered scene."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.startswith('[node name="%s"' % name):
            out = []
            for l in lines[i + 1:]:
                if l.startswith("[") or l == "":
                    break
                out.append(l)
            return out
    raise AssertionError("node %s not emitted" % name)


def selftest():
    fails = []

    def expect(cond, what):
        if not cond:
            fails.append(what)

    def has(lines, prefix):
        return any(l.startswith(prefix) for l in lines)

    # scanner: offline_* only when they differ from 5.5 / 1.5.
    r = _gen()
    r.scanner("a", 100, "low", -120, 0)
    r.scanner("b", 100, "low", -120, 0, circuit="c", offline_open=4.0, offline_warn=1.0)
    t = r.render()
    a, b = _node(t, "Scanner_a"), _node(t, "Scanner_b")
    expect(not has(a, "offline_open") and not has(a, "offline_warn") and not has(a, "circuit"), "scanner a emits defaults")
    expect("offline_open = 4.00" in b and "offline_warn = 1.00" in b and 'circuit = &"c"' in b, "scanner b overrides")
    for prop in ["position = Vector2(100, 0)", 'beam_id = "a"', "top_y = -120", "bottom_y = 0"]:
        expect(prop in a, "scanner a: " + prop)
    expect(has(a, "data = ExtResource") and 'path="res://data/level/scanner_low.tres"' in t, "scanner data resource")
    # flow: drain_* only when set.
    r = _gen()
    r.flow(0, -100, 100, 100)
    r.flow(0, -100, 100, 100, drain_scale=0.5, drain_floor=1.0)
    t = r.render()
    f1, f2 = _node(t, "Flow1"), _node(t, "Flow2")
    expect(not has(f1, "drain_scale") and not has(f1, "drain_floor"), "flow defaults")
    expect("drain_scale = 0.50" in f2 and "drain_floor = 1.0" in f2, "flow drain")
    # Director cap.
    expect(not has(_node(_gen(max_attackers=2).render(), "EncounterDirector"), "max_attackers"), "max_attackers 2 omitted")
    expect("max_attackers = 1" in _node(_gen(max_attackers=1).render(), "EncounterDirector"), "max_attackers 1")
    # Enemy variants.
    r = _gen()
    r.enemy("Needle", 100, 0, ai=False, data="needle_dormant")
    t = r.render()
    n = _node(t, "Needle1")
    expect("ai_enabled = false" in n and has(n, "data = ExtResource"), "enemy ai/data props")
    expect('path="res://data/enemies/needle_dormant.tres"' in t, "enemy data ext_resource")
    # Folder-qualified exits.
    r = _gen()
    r.exit(0, -96, 16, 96, "undercity/Wake", "from_x")
    r.exit(0, -96, 16, 96, "FloodedAlley", "from_x")
    t = r.render()
    expect('target_room = "res://world/rooms/undercity/Wake.tscn"' in _node(t, "Exit1"), "qualified exit")
    expect('target_room = "res://world/rooms/lowlight/FloodedAlley.tscn"' in _node(t, "Exit2"), "bare exit")
    # NPC present_when.
    r = _gen()
    r.npc("orr", 10, 0, present_when=("flag:a", "!flag:b"))
    expect('present_when = PackedStringArray("flag:a", "!flag:b")' in _node(r.render(), "NPC_orr"), "npc present_when")
    # The other M7 helpers: property names are the contract.
    r = _gen()
    r.weapon_pickup("PulseBladeRack", "pulse_blade", "got_pulse_blade", 50, 0)
    r.breaker("b1", "grid_a", 60, -24)
    r.shutter("s1", 200, -96, 16, 96, "grid_a", "shutter_std", "uc_latch")
    r.clamp("c1", 300, -200, 64, -120, "clamp_std", ["grid_a", "grid_b"])
    r.clamp("c2", 400, -200, 64, -120, "clamp_std", ["grid_a"], hint_id="arm", hint="Hit the breaker")
    r.respawn_point("mid", 100, -96, 32, 96)
    r.declare_flags("f1", "f2")
    r.tracker("Eye1", (100, 900), -200, 150, 850, "collector_eye", visible_when="!flag:x")
    r.chase("rc", "sweeper", [(0, 0), (500, 0)], [1.0, 1.2], (0, -96, 32, 96), (480, -96, 32, 96), [(100, 0), (300, 0)])
    t = r.render()
    want = {
        "Pickup_pulse_blade": ["position = Vector2(50, 0)", 'weapon_id = "pulse_blade"', 'flag_id = "got_pulse_blade"'],
        "Breaker_b1": ["position = Vector2(60, -24)", 'breaker_id = "b1"', 'circuit = &"grid_a"'],
        "Shutter_s1": ["position = Vector2(200, -96)", "size = Vector2(16, 96)", 'shutter_id = "s1"', 'circuit = &"grid_a"', "timing = ", 'latch_flag = "uc_latch"'],
        "Clamp_c1": ["position = Vector2(300, -200)", 'clamp_id = "c1"', "width = 64", "raised_bottom = -120", "timing = ",
                     'circuits = Array[StringName]([&"grid_a", &"grid_b"])', "attack = "],
        "Clamp_c2": ['arm_hint_id = "arm"', 'arm_hint = "Hit the breaker"'],
        "Respawn_mid": ["position = Vector2(100, -96)", "size = Vector2(32, 96)", 'spawn_id = &"mid"'],
        "FlagDeclaration": ['produces = PackedStringArray("f1", "f2")'],
        "Eye1": ["position = Vector2(100, -200)", "rail_min = 100", "rail_max = 900", "wake_x = 150", "lost_x = 850", "config = ", 'visible_when = "!flag:x"'],
        "Chase_rc": ['chase_id = "rc"', "data = ", "path = PackedVector2Array(0, 0, 500, 0)", "speed_scale = PackedFloat32Array(1, 1.2)",
                     "start_area = Rect2(0, -96, 32, 96)", "end_area = Rect2(480, -96, 32, 96)"],
        "CP1": ["position = Vector2(100, 0)"],
        "CP2": ["position = Vector2(300, 0)"],
    }
    for node, props in want.items():
        lines = _node(t, node)
        for prop in props:
            expect(any(l.startswith(prop) for l in lines), "%s: %s" % (node, prop))
    expect(not has(_node(t, "Clamp_c1"), "arm_hint"), "clamp without hint")
    expect('[node name="CP1" type="Marker2D" parent="Triggers/Chase_rc"]' in t, "chase checkpoints are children")
    expect('[node name="Pickup_pulse_blade" parent="Interactables" instance=' in t, "pickup is an instance")
    expect('[node name="Eye1" parent="Hazards" instance=' in t, "tracker is an instance")
    for path in ["res://interactables/PulseBladeRack.tscn", "res://world/props/CollectorEye.tscn", "res://interactables/Breaker.gd",
                 "res://world/transitions/PowerShutter.gd", "res://world/transitions/GridClamp.gd", "res://data/level/shutter_std.tres",
                 "res://data/level/clamp_std.tres", "res://data/combat/grid_clamp_attack.tres", "res://interactables/EntryCheckpoint.gd",
                 "res://world/rooms/FlagDeclaration.gd", "res://data/props/collector_eye.tres", "res://world/hazards/ChaseDirector.gd",
                 "res://world/hazards/ChaseCheckpoint.gd", "res://data/world/chase/sweeper.tres"]:
        expect('path="%s"' % path in t, "ext_resource " + path)
    # Unchanged helpers keep their old output.
    r = _gen()
    r.enemy("Needle", 100, 0)
    expect(_node(r.render(), "Needle1") == ["position = Vector2(100, 0)"], "plain enemy unchanged")
    # M8 helpers: nested switches, a second NPC post, NOTE markers.
    r = _gen()
    outer = r.switch("Outer", "flag:a")
    inner = r.switch("Inner", "!flag:b", parent=outer)
    expect(outer == "Props/Outer" and inner == "Props/Outer/Inner", "switch returns its full path")
    r.npc("mara", 10, 0)
    r.npc("mara", 200, 0, name="NPC_mara_post", present_when=("flag:act1_complete",))
    r.mapmarker(50, -20, "Dash gap", "ability:dash")
    r.mapmarker(90, -40, "Signal here?", "flag:c", kind=2, shown_when="flag:d")
    t = r.render()
    expect('[node name="Inner" type="Node2D" parent="Props/Outer"]' in t and 'visible_when = "!flag:b"' in _node(t, "Inner"), "nested switch")
    expect('[node name="NPC_mara" type="Area2D" parent="Interactables"]' in t, "first post keeps NPC_<profile>")
    expect('[node name="NPC_mara_post" type="Area2D" parent="Interactables"]' in t
           and 'present_when = PackedStringArray("flag:act1_complete")' in _node(t, "NPC_mara_post"), "npc name=")
    expect(not has(_node(t, "MapMarker1"), "shown_when"), "mapmarker without shown_when unchanged")
    expect(_node(t, "MapMarker1") == ["position = Vector2(50, -20)", 'script = ExtResource("marker")', "kind = 0",
                                      'label = "Dash gap"', 'resolved_when = "ability:dash"'], "plain mapmarker output unchanged")
    m2 = _node(t, "MapMarker2")
    expect("kind = 2" in m2 and 'shown_when = "flag:d"' in m2, "NOTE mapmarker shown_when")
    # M8 sequence_trigger: named node, defaults omitted, options emitted.
    r = _gen()
    r.sequence_trigger("SeqPlain", "uc_opening", 10, -96, 64, 96)
    r.sequence_trigger("SeqFull", "relay_arrival", -48, -240, 112, 96, play_when=["flag:a", "!flag:b"],
                       autoplay=True, require_spawn="from_x", once=False)
    t = r.render()
    plain, full = _node(t, "SeqPlain"), _node(t, "SeqFull")
    expect('[node name="SeqPlain" type="Area2D" parent="Triggers"]' in t, "sequence trigger keeps its name")
    expect(plain == ["position = Vector2(10, -96)", 'script = ExtResource("sequence")', "size = Vector2(64, 96)",
                     'sequence = ExtResource("seq_uc_opening")'], "plain sequence trigger emits no defaults: %s" % plain)
    for prop in ['play_when = PackedStringArray("flag:a", "!flag:b")', "autoplay = true", 'require_spawn = &"from_x"', "once = false"]:
        expect(prop in full, "sequence trigger: " + prop)
    expect('path="res://world/props/SequenceTrigger.gd"' in t and 'path="res://data/sequences/relay_arrival.tres"' in t,
           "sequence trigger ext_resources")
    return fails


def write_fixtures():
    # A floor with a 100 px pit (x 300..400) for Room.pit_override.
    r = RoomGen("scaffold_pit", (-64, -270, 800, 400), "undercity", "Test", "Scaffold pit")
    r.block(-48, 0, 348, BIG, "FloorLeft")
    r.block(400, 0, 336, BIG, "FloorRight")
    r.spawn("start", 40, 0, 1, default=True)
    r.write(OUT + "scaffold_pit.tscn")
    # The ContentValidator content protocol: a stub flag declaration and a
    # probe that reports one warning and one error.
    r = RoomGen("scaffold_protocol", (-64, -270, 800, 400), "undercity", "Test", "Scaffold protocol")
    r.block(-48, 0, 784, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    r.declare_flags("t_declared")
    r.ext["probe"] = ("Script", "res://tests/fixtures/ProtocolProbe.gd")
    r.raw("Triggers", "ProtocolProbe", "Node", ['script = ExtResource("probe")'])
    r.write(OUT + "scaffold_protocol.tscn")
    # M8 lint cases (new files; the two above stay byte-identical).
    # A WorldStateSwitch holding collision: the one error is the GrayboxBlock.
    r = RoomGen("scaffold_m8_switch_bad", (-64, -270, 800, 400), "undercity", "Test", "Scaffold M8 switch")
    r.block(-48, 0, 784, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    sw = r.switch("BadSwitch", "flag:t_switch")
    r.raw(sw, "Lamp", "Node2D", ["position = Vector2(200, -40)"])
    r.raw(sw, "SolidCrate", "StaticBody2D", ["position = Vector2(300, -32)", 'script = %s' % r._script("block"), "size = Vector2(32, 32)"])
    r.lever("t_switch", 100, 0)
    r.write(OUT + "scaffold_m8_switch_bad.tscn")
    # A NOTE map marker 40 px from a memory fragment (bible §20: never where).
    r = RoomGen("scaffold_m8_note_bad", (-64, -270, 800, 400), "undercity", "Test", "Scaffold M8 note")
    r.block(-48, 0, 784, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    r.collectible(1, "t_m8_fragment", 400, -16, fragment="mf_lowlight_01")
    r.mapmarker(440, -16, "Something here", "", kind=2)
    r.mapmarker(600, -16, "Far enough", "", kind=2)
    r.write(OUT + "scaffold_m8_note_bad.tscn")
    # A SequenceTrigger placed in its own room (T07): autoplay from "start",
    # playing a theatre-only one-SeqWait fixture sequence.
    r = RoomGen("scaffold_m8_sequence", (-64, -270, 800, 400), "undercity", "Test", "Scaffold M8 sequence")
    r.block(-48, 0, 784, BIG, "Floor")
    r.spawn("start", 40, 0, 1, default=True)
    r.spawn("side", 600, 0, -1)
    r.sequence_trigger("SeqTest", "test_scaffold_trigger", -48, -140, 150, 140, autoplay=True, require_spawn="start")
    r.write(OUT + "scaffold_m8_sequence.tscn")


if __name__ == "__main__":
    if "--selftest" in sys.argv or "--check" in sys.argv:
        failures = selftest()
        if failures:
            print("roomgen self-test failed: " + "; ".join(failures))
            sys.exit(1)
        print("roomgen self-test passed")
        if "--selftest" in sys.argv:
            sys.exit(0)
    write_fixtures()
    finish()
