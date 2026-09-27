"""Where the asset tools read and write (repo layout, D-next presentation overhaul).

    redline/assets/            game files (PNG, SpriteSheetSpec .tres, sidecar .json, OGG)
    redline/assets/audio/      sfx/, ui/, footsteps/, ambience/, music/
    redline/art/source/        source material Godot never imports (art/.gdignore)
    redline/art/source/raw/    raw downloads (compressed PNG only; raw audio is never committed)
    redline/tools/assetgen/    these scripts + their data (palettes.json, manifests)
    tools/assetgen/_preview/   x3 review copies (git- and Godot-ignored)

Environment overrides (assetgen.py --check uses them to rebuild into a temp dir):
    ASSETGEN_OUT      replaces redline/assets (and art/source outputs go to <it>/_source)
    ASSETGEN_RAW      where raw downloads live (the raw MP3s are kept outside the repo)
    ASSETGEN_PREVIEW  where review copies go
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REDLINE = os.path.dirname(os.path.dirname(HERE))
DATA = HERE
REPO_ASSETS = os.path.join(REDLINE, "assets")
SOURCE = os.path.join(REDLINE, "art", "source")

ASSETS = os.environ.get("ASSETGEN_OUT") or REPO_ASSETS
AUDIO = os.path.join(ASSETS, "audio")
SOURCE_OUT = os.path.join(os.environ["ASSETGEN_OUT"], "_source") if os.environ.get("ASSETGEN_OUT") else SOURCE
RAW = os.environ.get("ASSETGEN_RAW") or os.path.join(SOURCE, "raw")
PREVIEW = os.environ.get("ASSETGEN_PREVIEW") or os.path.join(HERE, "_preview")
