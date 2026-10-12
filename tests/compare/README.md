# Shader conversion comparison (PC side)

Renders the same game states with the game's original OpenGL shaders and with the port's GLSL ES 3.00 conversion, frame by frame, and compares the pictures. Test code only: nothing here is shipped, and nothing under `port/`, `setup/` or `build/` is touched.

## The two copies

`make_copies.sh` builds both from the untouched macOS depot and Unity's Linux player installer, following `build/make_patches.sh`:

* `cmp-ref`: the whole patch pipeline except `setup/gles_shaders2019.py`. Original OpenGLCore shader programs, every other port patch applied.
* `cmp-port`: the whole pipeline, what the port ships (its MD5s are checked against `port/20minutestilldawn/tools/patchscript`).

Then, identically in both, the test helper `PortCapture` is injected and the launcher's level edits for screens up to 800 pixels wide are applied. The script lists the files that differ between the copies and stops if one is not shader carrying (`resources.assets`, `sharedassets0.assets`, `sharedassets1.assets`, `unity_builtin_extra`, `unity default resources`).

## How a run is made repeatable

Unity's `Time.captureFramerate` only fixes `Time.deltaTime`, and the game (LeanTween, DOTween, UnityEngine.UI, TextMeshPro) also runs on unscaled and real time, so `PortCapture.cs` (injected by `capture_inject.cs`, Mono.Cecil) does more:

* Fixed simulation step of 1/30 s per rendered frame (`captureFramerate = 30`), independent of how fast the machine renders.
* `Time.unscaledDeltaTime`, `Time.unscaledTime`, `Time.realtimeSinceStartup` and `new WaitForSecondsRealtime` in the game's assemblies are redirected to a clock that advances 1/30 s per frame.
* `SceneManager.LoadSceneAsync` goes through a wrapper that freezes the game clock until the scene has loaded, so the first frame of a run has the same game time (Time.time) on every machine. The title scene to battle load takes a different number of frames on every run otherwise.
* `UnityEngine.Random` is reseeded when a scene loads and every frame in the title scene. Every ParticleSystem gets a fixed random seed (new ones, such as death effects, are found by a rescan every frame). The game's code has no `System.Random`, `DateTime` or other clock seeds (checked in the IL).
* Input comes from a virtual gamepad that PortCapture feeds by scene frame number (`PORTCAP_INPUT`), so the menus are driven by frame counts, not by when a script pressed a key. No real input device is used.
* The player runs under `setarch -R` (no address space randomisation), because Mono's object hashes are address based.
* The frame counter restarts when a scene loads. At the frames in `PORTCAP_FRAMES` the back buffer is read at the end of the frame (`ReadPixels`) and written as `<scene>_<frame>.png`; a small `.txt` next to it records game time, Random sample and counts.

### Determinism

Frames from the title scene and the first part of every run are bit identical from run to run. Later frames can still differ between two runs of the same build: a rare one ulp (about 2e-7) difference in the position of an enemy body (Box2D contacts, Mono, or a thread; not found) that grows into a different fight, and the death effect particles. `compare_runs.py` handles this by comparing all runs against each other and taking the best ref/port pair per frame, next to how far the build differs from itself. See the results section below.

## Running

```
tests/compare/make_copies.sh                 # once (needs the macOS depot and the Unity installer, see below)
tests/compare/run_all.sh                     # both scenarios, 3 runs of each build, summary in out/summary.txt
tests/compare/run_capture.sh ref shoot t1    # a single run: ref|port, idle|shoot, tag
tests/compare/compare.py ref_shoot_1 port_shoot_1          # one pair of runs, strict mode: --strict
tests/compare/compare_runs.py shoot          # all runs of a scenario against each other
tests/compare/log_scan.py ref_shoot_1 port_shoot_1         # shader errors in player.log
```

`make_copies.sh [workspace]` expects `macos/20MinutesTillDawn.app` and `unity/UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe` in the workspace (default `~/Games/steam-ports/20mtd`) and writes `cmp-ref` and `cmp-port` there. It needs mono with `mcs` and Mono.Cecil 0.11, `7z`, and Python with UnityPy (it makes `tests/compare/.venv` from `setup/requirements.txt` when `PYTHON` is not set). `install_capture.sh` rebuilds just the helper after editing `PortCapture.cs`.

`run_capture.sh` follows `tests/localtest.sh`: an offscreen Xvfb (never the desktop display), 640x480, bwrap with no input devices, `cmp-ref` on desktop GL (`NOGLES`) and `cmp-port` on a forced GLES 3.2 context (`tests/pc/gles_force.so`, as crusty_glx gives on the device). Audio goes to a null ALSA device (`alsa_null.conf`) because FMOD crashes while listing this PC's ALSA plugins. Each run ends when PortCapture logs `PortCapture: done`, the player is killed with SIGKILL and the Xvfb with it.

Scenarios: `idle` (nothing pressed during the run: the player stands still and dies after about 20 s) and `shoot` (right trigger pressed again every 60 frames, left stick walking a square, 90 frames a side). Both press A through the menus at title frames 900, 1020, 1140, 1260 and 1380 (Play, character, weapon, mode, map). Environment: `FRAMES` (default `TitleScreen:120,300,600;Battle:30,60,...,1500`), `SEED`, `DISP`, `TRACE=1` (per frame game time and Random state in `frames/trace.txt`, with `DUMP=a-b` adding the 2D bodies), `NAV_START` and `NAV_GAP`.

## Reading the output

`compare.py` per frame pair: PSNR, maximum absolute channel difference, share of pixels with any channel differing (`%>0`), by more than 2 and by more than 16, mean difference, and in `out/<name>/`: `<frame>_heat.png` (difference times 8 in red over a dark copy of the picture; any differing pixel shows at least 40 of 255) and `<frame>_side.png` (A, B, heat map).

`log_scan.py` counts shader compile and link failures, "not supported", "fallback" and error shader lines in `player.log` and `game.out` per shader name.

## Results

See `out/summary.txt` after a run (the numbers of the last run are summarised in the commit message and in the report that came with this harness).

## On the device

Do the same with the same data, nothing else changes: the pictures only mean something when the game states are the same.

1. Use the port as installed and set up on the device (so its `MinutesTillDawn_Data` is the port's patched data). From `cmp-port` copy `MinutesTillDawn_Data/Managed/PortCapture.dll`, `Assembly-CSharp.dll`, `DOTween.dll`, `UnityEngine.UI.dll` and `Unity.TextMeshPro.dll` into the device's `MinutesTillDawn_Data/Managed/` (keep the originals; the port's launcher checks `Assembly-CSharp.dll` through its setup MD5s, so run this on a test copy of the port folder or restore the originals afterwards and delete the setup stamp if it complains).
2. In a copy of the launcher, export before the game starts: `PORTCAP_DIR=$GAMEDIR/portcap`, `PORTCAP_FRAMES` and `PORTCAP_INPUT` exactly as `runs/<tag>/env.txt` of the PC run (written by `run_capture.sh`), `PORTCAP_SEED=1234`. Westonpack's `westonwrap.sh` takes `VAR=value` arguments for the game, as the launcher does for box64 (see the existing launcher lines).
3. Use the same resolution as the PC run (`-screen-width 640 -screen-height 480`) and the port's normal GL path (glespass, crusty_glx). The speed of the device does not matter: the simulation advances 1/30 s per rendered frame whatever the real frame rate (expect a long run; the 30 fps cap is irrelevant).
4. Wait for `PortCapture: done` in `player.log`, copy `portcap/*.png` to `tests/compare/runs/dev_<scenario>_1/frames/` on the PC and compare with the PC desktop GL reference: `tests/compare/compare.py ref_<scenario>_1 dev_<scenario>_1`. Expect the same pictures within GPU rounding (the Mali rasteriser is not llvmpipe, so single level differences in gradients are normal); flat colour differences, missing or wrong coloured sprites, or a different blend are shader bugs. Run the device twice first and compare the two runs with `--strict` to see how repeatable the device is.
