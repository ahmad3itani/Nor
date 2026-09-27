"""peek.py sheet.png cellw cellh row:frames,... out.png [scale] -> contact image for review."""
import sys
from PIL import Image
im = Image.open(sys.argv[1]); cw, ch = int(sys.argv[2]), int(sys.argv[3])
spec = [tuple(map(int, s.split(':'))) for s in sys.argv[4].split(',')]
sc = int(sys.argv[6]) if len(sys.argv) > 6 else 5
cols = max(n for _, n in spec)
out = Image.new('RGBA', (cw * cols, ch * len(spec)), (60, 64, 74, 255))
for k, (r, n) in enumerate(spec):
    out.alpha_composite(im.crop((0, r * ch, cw * n, r * ch + ch)), (0, k * ch))
out.resize((out.width * sc, out.height * sc), Image.NEAREST).save(sys.argv[5])
