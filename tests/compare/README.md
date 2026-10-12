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

## Results (2026-10-13)

PC, desktop GL reference (`cmp-ref`) against the port's GLES programs (`cmp-port`), 2 scenarios, 2 to 3 runs of each build, 22 frames per run: every frame is identical or differs by at most 1 level of 255 (rounding), except frames where the game itself diverges between two runs of the same build (death particles), which stay inside that spread. 0 unexplained differences. The shader log scan finds no compile, link or fallback errors (its one hit per run is the GL extension list, which contains `GL_KHR_no_error`, in the reference runs too).

RG35XX H (Knulli, Mali-G31, the port's real path: box64, glespass, Westonpack, crusty_glx) against the PC reference, idle and shoot:

* Title screen frames: identical.
* Battle frames: 68 to 96% of pixels differ by 1 or 2 levels (mean 0.5), the Mali rasteriser and blending rounding differently from Mesa. No banding: the vision light gradient, fog and particles stay within 2 levels everywhere.
* At most 0.2% of pixels differ by more than 2, and every such spot is a 1 pixel tall UI element (the hint text row, the reload bar, the results separator) drawn on the neighbouring pixel row: geometry at a half pixel position that the two GPUs round to opposite rows. Not a shader difference.
* The device run follows the same game states for the whole run (shoot scenario included), so the frames compare one to one.

Conclusion: the converted shaders render the game as the original shaders do, on PC and on the Mali GPU, with the port's precision (highp floats, ints and samplers).

## On the device

`device/20MTD Compare.sh` is a test launcher (never shipped) that runs the port's own game path with PortCapture. Steps used for the results above:

1. On the device, make `ports/20mtdcmp` from the installed port (`gamedata`, `box64`, `glespass`, `tools`), then copy `PortCapture.dll`, `Assembly-CSharp.dll`, `DOTween.dll`, `UnityEngine.UI.dll` and `Unity.TextMeshPro.dll` from `cmp-port/MinutesTillDawn_Data/Managed/` into its `gamedata/MinutesTillDawn_Data/Managed/`. Check first that the shader carrying assets and level files are byte identical to `cmp-port` (md5sum).
2. Copy the launcher to `ports/`, reload the game list (`curl localhost:1234/reloadgames`), write `ports/20mtdcmp/run.cfg` (`SCEN=idle` or `shoot`, `TAG=dev_<scen>_1`) and launch it (`curl -d "<path>" localhost:1234/launch`).
3. Turn address space randomisation off for the runs (`echo 0 > /proc/sys/kernel/randomize_va_space`, as `setarch -R` on the PC) and back on afterwards (`echo 2`).
4. PortCapture disables every real input device inside the game (`PORTCAP_ONLYPAD`, default on), so stick drift on the handheld cannot change the run. Do not hide `/dev/input` instead: Westonpack's seatd aborts without input devices.
5. When `PortCapture: done` is in `portcap/<tag>/player.log`, stop the game (`curl localhost:1234/emukill`), copy `portcap/<tag>/frames` to `runs/<tag>/frames` here and run `./compare.py ref_<scen>_1 dev_<scen>_1`.
6. Remove `ports/20mtdcmp` and the launcher from the device afterwards.
