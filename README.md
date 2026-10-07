# 20 Minutes Till Dawn for PortMaster

A [PortMaster](https://portmaster.games/) port of [20 Minutes Till Dawn](https://store.steampowered.com/app/1966900/20_Minutes_Till_Dawn/) (flanne, 2023), a survival roguelite, for Linux handhelds with ARM64 CPUs.

The game has Windows and macOS builds only. The Windows build carries Direct3D 11 shaders only, but the macOS build also carries OpenGL ones, so the port takes the macOS game data, converts its shaders to OpenGL ES 3 and runs it on Unity's own Linux player for the same engine version (2019.4.40f1) through box64. No game files and no Unity files are included: you supply the game from your Steam copy, and the device downloads Unity's player from Unity the first time it starts.

| | |
|--|--|
| Status | Runs on an Anbernic RG35XX H (Knulli and muOS, Mali G31, 1 GB): menus, runs, level ups and death screen with the controller and sound, 30 fps in a run. |
| Tester reports (first release) | R36H (dArkOS): starts after about 3 minutes, the controls do nothing in game. RG40XX-H (muOS): setup fails. Both are open; the launcher logs much more since (pad details, setup log), so logs from the current release are needed. |
| Target | aarch64 PortMaster devices with an OpenGL ES 3 GPU, 1 GB RAM or more |
| Runtimes | Westonpack (`weston_pkg_0.2`, crusty_glx), bundled box64 and glespass |
| Supported game version | Steam depot 1966902 (macOS), manifest 1890137909460856104 |

## For players

1. Buy the game on Steam.
2. Open the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244) and download the macOS build:
   ```
   download_depot 1966900 1966902
   ```
3. Copy `20MinutesTillDawn.app` into `ports/20minutestilldawn/gamedata/` on your device.
4. Start **20 Minutes Till Dawn** from the Ports menu with the device online. The first start shows PortMaster's patcher screen while it downloads Unity's Linux player (57 MB) and adapts the game files.

Controls and notes are in [port/README.md](port/README.md), the file that ships with the port.

## What the port changes

All changes are made on the device to your own copy, from xdelta patches checked by MD5 before and after (`port/20minutestilldawn/tools/patchscript`):

* Shaders: GLCore GLSL rewritten to GLSL ES 3.00 in five files (`setup/gles_shaders2019.py`).
* Load time: pooled effects expire without `Invoke`/`CancelInvoke` (`setup/ttl_patch.cs`), and the run's object pools start smaller (they grow on demand).
* Small screens: the UI canvas is laid out for 640 units wide, the small pixel font is redrawn for 12 px and used at that size (`setup/font_rescale.py`), and a few panels are resized to fit (`setup/ui_levels.py`). On screens up to 800 wide the launcher turns off the game's 16:9 crop so the view fills the screen.
* Input: the launcher renumbers pad buttons for the Unity player's built in SDL and maps the D-pad to movement. The mapping is passed to the game as a Westonpack argument, because Westonpack reloads PortMaster's settings and on muOS that replaced it (only the sticks and L2 worked).

## Building

* `build/build.sh` builds box64 and glespass for aarch64 in Docker.
* `build/make_patches.sh <folder with 20MinutesTillDawn.app> <Unity Linux player installer>` regenerates the patches and MD5s (Python packages in `setup/requirements.txt`, mono with Mono.Cecil, 7z, Docker).
* `build/package.sh` makes `20minutestilldawn.zip`.
* `tests/localtest.sh` runs the port on an x86_64 PC under Xwayland with a virtual pad; `docs/NOTES.md` has the route, the failed routes and the findings.

## License

The port's own files are MIT (see `LICENSE`). The game, Unity's player, box64, libgcc_s and glespass keep their own licenses (`port/20minutestilldawn/licenses/`).
