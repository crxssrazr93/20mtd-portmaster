"""Static UI and pool changes to the game's two scenes (level0: title and menus, level1: a run),
written into the files in place (patches a copy; the port ships the result as xdelta patches).

* Canvas Scalers (Scale With Screen Size, Expand) 800x450 -> 640x450: the UI is drawn at 1:1 on a
  640x480 screen instead of 0.8x (which blurs the pixel fonts). 16:9 screens keep the original
  800x450 canvas (scale = min(w/640, h/450)), square ones get 640x640.
  On 4:3 and square screens the canvas is 640 units wide instead of 800, so:
  - the weapon grid (GunMenu/Buttons, parent width - 365.96) gets its old width back,
  - the Ember Path banner on the title screen moves right by the 80 units its side lost,
  - panels wider than 640 units are scaled down (PANEL_SCALE) or narrowed (PANEL_WIDTH) to fit.
* Text: the small pixel font (Express, 9) goes to 12, which font_rescale.py redraws it for, at a
  fixed size (auto sizing would land between sizes and squeeze its pixels); also its texts in
  sharedassets1 prefabs. The large font (Lantern, 17) stays crisp at 17 (LARGE_SIZE to test others).
* ObjectPooler initial pool sizes (all of them grow on demand): fewer objects to create when a run
  loads, less memory.

Needs UnityPy 1.25 with TypeTreeGeneratorAPI (reads the game's MonoBehaviours from its assemblies).
Usage: python ui_levels.py <Data dir>
"""
import os, struct, sys
import UnityPy
from UnityPy.helpers.TypeTreeGenerator import TypeTreeGenerator

UI_REF = (640.0, 450.0)
SMALL = 9.0                        # Express, redrawn at 12 px by font_rescale.py
TEXT_SIZES = {SMALL: 12.0, 17.0: float(os.environ.get('LARGE_SIZE', 17))}
TEXT_KEEP = ('Canvas/MapSelectPanel/ToggleGroup/', 'Canvas/TitleScreen/EmberpathBanner/')
PANEL_SCALE = {'Canvas/GunEvoMenu/HorizontalLayout': 0.8}   # 800 units wide
# panels whose scale the game animates to 1 when they open get narrower instead: width per path
PANEL_WIDTH = {'Canvas/ConfirmModePanel': 620.0,                    # 700; 3 x 200 + 2 x 30 inside
               'Canvas/ConfirmModePanel/ToggleGroup/StandardMode': 180.0,
               'Canvas/ConfirmModePanel/ToggleGroup/QuickPlayMode': 180.0,
               'Canvas/ConfirmModePanel/ToggleGroup/EndlessMode': 180.0,
               'Canvas/RunesPanel/Description': 180.0,               # 200
               'Canvas/TitleScreen/EmberpathBanner/WishlistTMP': 180.0}   # 140: 2 lines at 12, not 4
# start of run control hints: three "key - action" groups side by side, 135 units each; at 12 the
# texts need 620 units in all, split by text length, and the keys move clear of the "(Hold)" /
# "(Toggle)" prompts
for _g, _w in (('KBMControls/MoveControls', 170.0), ('KBMControls/ShootControls', 200.0),
               ('KBMControls/AutoAimControls', 250.0), ('GamepadControls/MoveControls', 200.0),
               ('GamepadControls/AimControls', 200.0), ('GamepadControls/ShootControls', 220.0)):
    PANEL_WIDTH['Canvas/ControlsDisplay/' + _g] = _w
# x positions: the runes panel (440 units) and its description box beside it spanned 671 units
PANEL_X = {'Canvas/RunesPanel': -94.0,                              # -120
           'Canvas/RunesPanel/Description': 98.0,                   # 131.43, now 8 units from the panel
           'Canvas/ControlsDisplay/KBMControls/ShootControls/Keybind': -58.0,     # -38
           'Canvas/ControlsDisplay/KBMControls/AutoAimControls/Keybind': -74.0}   # -48
# hint rows: "key - action" with the dash in the middle; 2 more units on each side of the dash
for _g in ('KBMControls/MoveControls', 'KBMControls/ShootControls', 'KBMControls/AutoAimControls',
           'GamepadControls/MoveControls', 'GamepadControls/AimControls', 'GamepadControls/ShootControls'):
    PANEL_X['Canvas/ControlsDisplay/%s/Action' % _g] = 6.0                    # 4
    PANEL_X.setdefault('Canvas/ControlsDisplay/%s/Keybind' % _g, -6.0)        # -4
for _g in ('KBMControls/ShootControls', 'KBMControls/AutoAimControls'):
    PANEL_X['Canvas/ControlsDisplay/%s/HoldPrompt' % _g] = -6.0               # -4
# keyboard key names that the game draws on a key icon sit 3 units low; the icon is not visible
# at this size, so they go up to the line of the other texts
PANEL_Y = {'Canvas/ControlsDisplay/KBMControls/MoveControls/Keybind': 3.0,
           'Canvas/ControlsDisplay/KBMControls/ShootControls/Keybind': 3.0}
GUN_GRID = 'Canvas/GunMenu/Buttons'
GUN_GRID_SIZE_X = -205.96          # was -365.96 (434 units wide on the 640 unit canvas again)
BANNER = 'Canvas/TitleScreen/EmberpathBanner'
BANNER_SHIFT_X = 100.0           # 80 lost on the left, 20 for the wider wishlist text
POOL = {'DamagePopup': 200,        # 3000, TextMeshPro text objects
        'BulletImpact': 100,       # 1000
        'SmallXP': 200,            # 1000
        'EnemyDeathFX': 60,        # 400
        'ExplosionFX': 20,         # 100
        'Burn': 20,                # 100
        'FireExplosionSmall': 10}  # 50


def go_path(go):
    names = [go.m_Name]
    tr = next((c.read() for c in (getattr(x, 'component', x) for x in go.m_Component)
               if c.read().object_reader.type.name in ('RectTransform', 'Transform')), None)
    while tr is not None and tr.m_Father.path_id:
        tr = tr.m_Father.read()
        names.append(tr.m_GameObject.read().m_Name)
    return '/'.join(reversed(names))


def main():
    data = sys.argv[1]
    gen = TypeTreeGenerator('2019.4.40f1')
    gen.load_local_game(os.path.dirname(os.path.abspath(data)))
    for f in ('level0', 'level1', 'sharedassets1.assets'):
        path = os.path.join(data, f)
        env = UnityPy.load(path)
        env.typetree_generator = gen
        counts = {}
        for o in env.objects:
            kind = o.type.name
            if kind == 'RectTransform':
                rt = o.read()
                p = go_path(rt.m_GameObject.read())
                if p in PANEL_WIDTH or p in PANEL_X or p in PANEL_Y:
                    t = o.read_typetree()
                    if p in PANEL_WIDTH:
                        t['m_SizeDelta']['x'] = PANEL_WIDTH[p]
                    if p in PANEL_X:
                        t['m_AnchoredPosition']['x'] = PANEL_X[p]
                    if p in PANEL_Y:
                        t['m_AnchoredPosition']['y'] = PANEL_Y[p]
                    o.save_typetree(t)
                    counts[p] = 1
                elif p in PANEL_SCALE:
                    t = o.read_typetree()
                    for k in ('x', 'y'):
                        t['m_LocalScale'][k] *= PANEL_SCALE[p]
                    o.save_typetree(t)
                    counts[p] = 1
                elif p in (GUN_GRID, BANNER):
                    t = o.read_typetree()
                    if p == GUN_GRID:
                        grow = GUN_GRID_SIZE_X - t['m_SizeDelta']['x']
                        t['m_SizeDelta']['x'] = GUN_GRID_SIZE_X
                        t['m_AnchoredPosition']['x'] += grow / 2     # centred: keep the left edge
                    else:
                        t['m_AnchoredPosition']['x'] += BANNER_SHIFT_X
                    o.save_typetree(t)
                    counts[p] = 1
                continue
            if kind != 'MonoBehaviour':
                continue
            try:
                t = o.read_typetree()
            except ValueError:          # a few scripts in sharedassets1 use [SerializeReference]
                continue
            if 'm_UiScaleMode' in t:
                ref = t['m_ReferenceResolution']
                if t['m_UiScaleMode'] == 1 and (ref['x'], ref['y']) == (800.0, 450.0):
                    ref['x'], ref['y'] = UI_REF
                    o.save_typetree(t)
                    counts['canvas'] = counts.get('canvas', 0) + 1
            elif 'm_fontSize' in t and t['m_fontSize'] in TEXT_SIZES:
                p = go_path(o.read().m_GameObject.read())
                old = t['m_fontSize']
                new = TEXT_SIZES[old]
                if new == old or (old != SMALL and p.startswith(TEXT_KEEP)):
                    continue
                # fixed size: the small font is redrawn for exactly 12 px (font_rescale.py), any
                # other size (auto sizing included) squeezes or stretches its pixels
                t['m_fontSize'] = t['m_fontSizeBase'] = new
                t['m_enableAutoSizing'] = 0
                o.save_typetree(t)
                counts['text'] = counts.get('text', 0) + 1
            elif 'itemsToPool' in t:
                for item in t['itemsToPool']:
                    if item['tag'] in POOL:
                        assert item['shouldExpand'], item['tag']
                        item['amountToPool'] = POOL[item['tag']]
                o.save_typetree(t)
                counts['pools'] = 1
        data_out = list(env.files.values())[0].save()
        with open(path + '.tmp', 'wb') as fh:
            fh.write(data_out)
        os.replace(path + '.tmp', path)
        print(f, counts)


if __name__ == '__main__':
    main()
