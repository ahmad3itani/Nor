"""Lowlight palette and constants for new per-room Lowlight generators
(tools/roomgen/ll_<snake_room>.py). Copied from lowlight.py, which keeps its
own copies so its output stays byte-identical.
"""
BIG = 96  # floor thickness
OUT = "world/rooms/lowlight/"
RED, CYAN, AMBER, GREEN, VIOLET = "0.91, 0.16, 0.24, 1", "0.35, 0.88, 0.91, 1", "1, 0.81, 0.35, 1", "0.49, 1, 0.6, 1", "0.7, 0.45, 1, 1"
