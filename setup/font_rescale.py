"""Redraws the game's small pixel font (TextMeshPro asset "Express", ChevyRay Express, 9 px) at
12 px, so the text the port enlarges from 9 to 12 is drawn pixel for pixel.

Scaling the 9 px atlas by 4/3 at draw time doubles every third pixel column and row: 1 px strokes
come out 1 or 2 px wide (bold, uneven) and the 1 px gaps between letters close up. Here each glyph
is redrawn once: source pixel i goes to floor(i * 4 / 3), counted from the glyph origin and the
baseline so every glyph uses the same grid, and the pixel left free after every third one is set
only where the source has set pixels on both sides of it (a horizontal or vertical line carries on
through it). Strokes stay 1 px, the glyphs and the gaps between them grow.

The font asset keeps its point size (9): glyph metrics are stored in the font's units (12 px *
0.75), so the font size 12 is drawn at scale 1 and the texts left at 9 still lay out as before.
Kerning (-1 unit) becomes -1 px. The atlas becomes static so nothing is added to it at run time.

Usage: python font_rescale.py <Data dir>   (edits sharedassets0.assets in place)
"""
import math, os, sys
import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

FONT = 'Express'
ATLAS = 'Express Atlas'
UNIT = 0.75          # font units per output pixel (9 / 12)


def d(i):
    return math.floor(i * 4 / 3)


def rescale(pix, x0, y0):
    """pix: rows (bottom first) of 0/1, its bottom left pixel at (x0, y0) from origin/baseline.
    Returns (rows, x0', y0') at 4/3."""
    h, w = len(pix), len(pix[0])

    def axis(n, start, get):
        out = {}
        for i in range(n):
            out[d(start + i)] = get(i)
            a = start + i
            if d(a + 1) - d(a) == 2 and i + 1 < n:          # free pixel between a and a + 1
                out[d(a) + 1] = [x & y for x, y in zip(get(i), get(i + 1))]
        lo = d(start)
        return [out.get(lo + k, [0] * len(get(0))) for k in range(d(start + n - 1) - lo + 1)], lo

    cols, nx = axis(w, x0, lambda c: [pix[r][c] for r in range(h)])        # columns of length h
    tmp = [[cols[c][r] for c in range(len(cols))] for r in range(h)]       # back to rows
    rows, ny = axis(h, y0, lambda r: tmp[r])
    return rows, nx, ny


def main():
    data = sys.argv[1]
    gen = TypeTreeGenerator('2019.4.40f1')
    gen.load_local_game(os.path.dirname(os.path.abspath(data)))
    path = os.path.join(data, 'sharedassets0.assets')
    env = UnityPy.load(path)
    env.typetree_generator = gen
    font = tex = None
    for o in env.objects:
        if o.type.name == 'Texture2D' and o.peek_name() == ATLAS:
            tex = o
        elif o.type.name == 'MonoBehaviour':
            try:
                t = o.read_typetree()
            except Exception:
                continue
            if t.get('m_Name') == FONT and 'm_GlyphTable' in t:
                font = o
    ft, tt = font.read_typetree(), tex.read_typetree()
    W, H = tt['m_Width'], tt['m_Height']
    assert tt['m_TextureFormat'] == 1 and ft['m_FaceInfo']['m_PointSize'] == 9, 'already converted?'
    src = tt['image data']
    pad = ft['m_AtlasPadding']
    out = bytearray(W * H)
    x = y = pad
    line_h = 0
    for g in ft['m_GlyphTable']:
        r, m = g['m_GlyphRect'], g['m_Metrics']
        gw, gh = r['m_Width'], r['m_Height']
        adv = round(m['m_HorizontalAdvance'] * 4 / 3)
        if gw == 0 or gh == 0:
            m['m_HorizontalAdvance'] = adv * UNIT
            continue
        pix = [[1 if src[(r['m_Y'] + row) * W + r['m_X'] + c] >= 128 else 0 for c in range(gw)]
               for row in range(gh)]
        bx, by = int(m['m_HorizontalBearingX']), int(m['m_HorizontalBearingY'])
        rows, nx, ny = rescale(pix, bx, by - gh)
        nw, nh = len(rows[0]), len(rows)
        if x + nw + pad > W:
            x, y, line_h = pad, y + line_h + pad, 0
        for row in range(nh):
            for c in range(nw):
                if rows[row][c]:
                    out[(y + row) * W + x + c] = 255
        r.update(m_X=x, m_Y=y, m_Width=nw, m_Height=nh)
        m.update(m_Width=nw * UNIT, m_Height=nh * UNIT, m_HorizontalBearingX=nx * UNIT,
                 m_HorizontalBearingY=(ny + nh) * UNIT, m_HorizontalAdvance=adv * UNIT)
        x += nw + pad
        line_h = max(line_h, nh)
    assert y + line_h + pad <= H
    for rec in ft['m_FontFeatureTable']['m_GlyphPairAdjustmentRecords']:
        for side in ('m_FirstAdjustmentRecord', 'm_SecondAdjustmentRecord'):
            v = rec[side]['m_GlyphValueRecord']
            for k in v:
                v[k] = round(v[k] * 4 / 3) * UNIT
    ft['m_AtlasPopulationMode'] = 0
    ft['m_UsedGlyphRects'] = []
    ft['m_FreeGlyphRects'] = []
    tt['image data'] = bytes(out)
    font.save_typetree(ft)
    tex.save_typetree(tt)
    with open(path + '.tmp', 'wb') as fh:
        fh.write(list(env.files.values())[0].save())
    os.replace(path + '.tmp', path)
    print(FONT, len(ft['m_GlyphTable']), 'glyphs redrawn at 12 px')


if __name__ == '__main__':
    main()
