"""Writes the fixed-offset byte edits the launcher applies to the game's level files (supported
Steam build, macOS depot) as port/20minutestilldawn/tools/level_edits.txt lines:
  kind file offset original-bytes new-bytes [name]     (bytes in hex)
Three kinds:
  crop   Crop Frame X/Y flags of the Pixel Perfect Cameras (two int32 per camera); the launcher
         turns them off only on screens up to 800 pixels wide
  ui     Reference resolution of the screen space Canvas Scalers (Scale With Screen Size, Expand),
         800x450 -> UI_REF: the UI is drawn at 0.8x on a 640x480 screen, which blurs the pixel
         fonts; 640x360 draws it at 1:1 there (and larger on bigger screens). The canvas is then
         640 units wide instead of 800, so the weapon grid (GunMenu/Buttons, parent width - 366)
         gets the width it had (434 units, six columns) back through its size delta.
  pool   ObjectPooler initial pool sizes (int32 amountToPool per item; every changed item has
         shouldExpand set, so a pool grows on demand when a run needs more)
Usage: python byte_edits.py <Data dir> > port/20minutestilldawn/tools/level_edits.txt
"""
import os, struct, sys
import UnityPy

UI_REF = (640.0, 450.0)
GUN_GRID = ('Buttons', 'GunMenu', -206.0)   # name, parent, new size delta x (was -365.96)

# initial pool sizes (original in the comment); items not listed keep theirs
POOL = {'DamagePopup': 200,        # 3000, TextMeshPro text objects
        'BulletImpact': 100,       # 1000
        'SmallXP': 200,            # 1000
        'EnemyDeathFX': 60,        # 400
        'ExplosionFX': 20,         # 100
        'Burn': 20,                # 100
        'FireExplosionSmall': 10}  # 50


def a4(n): return (n + 3) & ~3


def main():
    d = sys.argv[1]
    g = UnityPy.load(os.path.join(d, 'globalgamemanagers.assets'))
    names = {o.path_id: o.read().m_ClassName for o in g.objects if o.type.name == 'MonoScript'}
    for f in ['level0', 'level1', 'sharedassets0.assets']:
        env = UnityPy.load(os.path.join(d, f))
        for o in env.objects:
            if o.type.name == 'RectTransform' and f == 'level0':
                rt = o.read()
                if (rt.m_GameObject.read().m_Name == GUN_GRID[0] and rt.m_Father.path_id and
                        rt.m_Father.read().m_GameObject.read().m_Name == GUN_GRID[1]):
                    # m_AnchoredPosition and m_SizeDelta (4 floats) are the last but one field
                    raw = o.get_raw_data(); off = len(raw) - 24
                    ax, ay, sx, sy = struct.unpack_from('<4f', raw, off)
                    assert (ax, ay, sx, sy) == (rt.m_AnchoredPosition.x, rt.m_AnchoredPosition.y,
                                                rt.m_SizeDelta.x, rt.m_SizeDelta.y)
                    grow = GUN_GRID[2] - sx            # wider by this, centred: move right by half
                    new = struct.pack('<4f', ax + grow / 2, ay, sx + grow, sy)
                    print(f'ui {f} {o.byte_start + off} {raw[off:off + 16].hex()} {new.hex()} GunMenu/Buttons')
                continue
            if o.type.name != 'MonoBehaviour':
                continue
            raw = o.get_raw_data()
            cls = names.get(struct.unpack_from('<q', raw, 20)[0])
            if cls == 'PixelPerfectCamera':
                print(f'crop {f} {o.byte_start + 52} {raw[52:60].hex()} {bytes(8).hex()}')
            elif cls == 'CanvasScaler':
                mode, = struct.unpack_from('<i', raw, 32)
                if mode == 1 and struct.unpack_from('<2f', raw, 44) == (800.0, 450.0):
                    print(f'ui {f} {o.byte_start + 44} {raw[44:52].hex()} {struct.pack("<2f", *UI_REF).hex()}')
            elif cls == 'ObjectPooler':
                p = a4(32 + struct.unpack_from('<i', raw, 28)[0])
                n, = struct.unpack_from('<i', raw, p); p += 4
                for _ in range(n):
                    sl, = struct.unpack_from('<i', raw, p); tag = raw[p + 4:p + 4 + sl].decode()
                    p = a4(p + 4 + sl) + 12
                    amt, = struct.unpack_from('<i', raw, p); expand = raw[p + 4]
                    if tag in POOL:
                        assert expand == 1, tag
                        print(f'pool {f} {o.byte_start + p} {raw[p:p + 4].hex()} {struct.pack("<i", POOL[tag]).hex()} {tag}')
                    p += 8


if __name__ == '__main__':
    main()
