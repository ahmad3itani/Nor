"""Collector Drone boss test fixtures (M7 M4), written with roomgen.

Run from redline/ (-B: do not rewrite the tracked __pycache__):
    python3 -B tools/roomgen/fixtures_boss.py          # write tests/fixtures/boss_*.tscn
    python3 -B tools/roomgen/fixtures_boss.py --check  # exit 1 if the fixtures drifted

boss_collector_arena.tscn is exactly the CollectorBay arena (room task R6):
same bounds, walls, catwalks, gate and BossArena, so test_boss_collector does
not depend on the room task. Its doors are plugged (a fixture has no
neighbours) and the reward is a placeholder Collectible scene with a fixed
persist_id (boss_reward_collectible.tscn), since the real cache lands with
the room.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roomgen
from roomgen import RoomGen, finish
from undercity_style import BIG

OUT = "tests/fixtures/"
REWARD = "res://tests/fixtures/boss_reward_collectible.tscn"
REWARD_ID = "test_collector_reward"


def write_text(path, text):
    """Plain-text fixture with the same --check drift rule as RoomGen.write."""
    if roomgen.CHECK:
        try:
            current = open(path).read()
        except OSError:
            current = None
        if current != text:
            roomgen._drift.append(path)
        return
    open(path, "w").write(text)


def write_reward():
    write_text(OUT + "boss_reward_collectible.tscn", "\n".join([
        '[gd_scene load_steps=2 format=3]', '',
        '[ext_resource type="Script" path="res://interactables/Collectible.gd" id="1_collect"]', '',
        '[node name="BossRewardCollectible" type="Area2D"]',
        'script = ExtResource("1_collect")',
        'persist_id = "%s"' % REWARD_ID,
        'scrap_amount = 10', '']))


def write_arena():
    c = RoomGen("boss_collector_arena", (0, -240, 480, 270), "undercity", "Test", "Collector Bay fixture")
    c.block(0, -240, 480, 16, "Ceiling")
    c.block(0, -224, 16, 128, "WallLeftUpper")
    c.block(16, -224, 48, 88, "VentRoof")
    c.block(448, -224, 32, 128, "WallRightUpper")
    c.block(0, 0, 480, BIG, "Floor")
    # CollectorBay's doors (x 0..16 and 464..480) are exits there; plugged here.
    c.block(0, -96, 16, 96, "DoorLeftPlug")
    c.block(464, -96, 16, 96, "DoorRightPlug")
    c.gate(40, -92, 16, 92, name="ArenaGateLeft")
    c.gate(448, -96, 16, 96, closed=True, open_flag="collector_drone_defeated", name="ExitGate")
    c.oneway(96, -40, 64)
    c.oneway(200, -80, 104)
    c.oneway(344, -40, 64)
    c.oneway(16, -92, 56)  # vent lip (x 16..72)
    c.spawn("start", 28, 0, 1, default=True)
    boss = c.enemy("CollectorDrone", 252, -144, -1)
    c.raw("Triggers", "BossArena", "Area2D", ['position = Vector2(72, -224)', 'script = %s' % c._script("arena"),
          'size = Vector2(376, 224)', 'boss_id = "collector_drone"', 'boss_title = "COLLECTOR DRONE"',
          'boss_subtitle = "Undercity Recovery Unit"', 'intro_time = 2.6', 'reward_position = Vector2(252, 0)',
          'boss_path = NodePath("../../Enemies/%s")' % boss,
          'gate_paths = [NodePath("../../Geometry/ArenaGateLeft")]',
          'reward_scene = %s' % c._res("scene_reward", "PackedScene", REWARD)])
    c.write(OUT + "boss_collector_arena.tscn")


if __name__ == "__main__":
    write_reward()
    write_arena()
    finish()
