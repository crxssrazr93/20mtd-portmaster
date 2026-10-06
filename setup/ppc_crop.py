"""Sets the crop frame flags of every Pixel Perfect Camera (com.unity.2d.pixel-perfect) in a level.

The game's cameras use a reference resolution of 800x450 with Crop Frame X and Y and Stretch Fill,
which letterboxes a 4:3 screen. Serialized layout after the MonoBehaviour header and empty name:
m_AssetsPPU, m_RefResolutionX, m_RefResolutionY (int32), then m_UpscaleRT, m_PixelSnapping,
m_CropFrameX, m_CropFrameY, m_StretchFill (bool, 4 byte aligned each). Same size edit in place.

Usage: python ppc_crop.py <Data dir> <cropX 0|1> <cropY 0|1> [level files...]
"""
import os, struct, sys
import UnityPy


def main():
    data, cx, cy = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    files = sys.argv[4:] or ['level0', 'level1']
    g = UnityPy.load(os.path.join(data, 'globalgamemanagers.assets'))
    ppc = {o.path_id for o in g.objects if o.type.name == 'MonoScript' and o.read().m_ClassName == 'PixelPerfectCamera'}
    for f in files:
        path = os.path.join(data, f)
        env = UnityPy.load(path)
        edits = []
        for o in env.objects:
            if o.type.name != 'MonoBehaviour':
                continue
            raw = o.get_raw_data()
            if struct.unpack_from('<q', raw, 20)[0] not in ppc:
                continue
            assert len(raw) == 64 and struct.unpack_from('<i', raw, 28)[0] == 0, (f, o.path_id)
            edits.append(o.byte_start + 52)
        with open(path, 'r+b') as fh:
            for off in edits:
                fh.seek(off); fh.write(struct.pack('<ii', cx, cy))
        print(f'{f}: {len(edits)} cameras set to crop X={cx} Y={cy}')


if __name__ == '__main__':
    main()
