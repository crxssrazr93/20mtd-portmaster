# 20 Minutes Till Dawn

Steam app 1966900 (flanne), Unity 2019.4.40f1, Mono, Facepunch.Steamworks. No Linux depot.

## Route chosen (2026-10-05)

macOS depot data on Unity's official 2019.4.40f1 Linux Mono player, then a GLES path built on unityport's shader rewriter.

* Depot 1966902 (macOS, public branch, build 12679152) carries Metal 44 and GLCore 44 shader programs; `m_GraphicsAPIs` = Metal, OpenGLCore. The Windows depot 1966901 has D3D11 only (48 programs, 5 built ins with GL).
* Linux player: `https://download.unity3d.com/download_unity/ffc62b691db5/TargetSupportInstaller/UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe` (57 MB NSIS, sha256 97fe1186bf3561a7ea1e5a8681372a3c86b0142eebde108b891b8503cda4ee1d), `Variations/linux64_withgfx_nondevelopment_mono` (LinuxPlayer, UnityPlayer.so, Data/MonoBleedingEdge, Data/Resources/unity default resources). Do not ship it: Unity's terms allow runtime distribution only as part of a licensee's project. Download on device at setup, or user supplied.
* Mac data + Linux player boots on PC: "Unknown renderer 16" (Metal skipped), OpenGL device created, full title screen (research-precedent/mac-on-linux/shot_25.png).
* Steam: the Mac build uses Facepunch.Steamworks.Posix (`libsteam_api`). `SteamIntegration.Awake` catches the failed `SteamClient.Init`; `RunCallbacks` is a no op uninitialised. Only `UnlockAchievement` throws (last call in `PlayerSurvivedState.Enter`), and the Endless leaderboard shows "retrieving data". No stub required; a minimal one is optional.

## Routes that do not work, and why

* Windows data on the Linux player: "Unknown renderer 2 / No supported renderers found". Setting GLCore is not enough: every Shader is D3D11 bytecode only (`platforms == [4]`, 43 shaders).
* Recompiling shaders with the 2019.4 editor: possible (built in shader source MIT, TMP 2.1.5/2.1.6 shader sources match, property lists match, transplant mechanics verified with UnityPy) but needs a Unity account sign in for a Personal license file, even in batchmode. The two custom shaders (Unlit/OutlineShader, Hidden/FogOfWar) cannot be decompiled by free AssetRipper. Research files in research-editor/.
* Driving UnityShaderCompiler directly: protocol is per version, no 2019 client exists.
* DXBC to GLSL via HLSLcc: started, stopped once the Mac depot route worked (not evaluated).
* Wine + box64: DXVK needs Vulkan (none on the Mali blob), wined3d D3D11 needs desktop GL 3.2+ core (gl4es is 2.1 class).
* Android (Erabit): separate purchase, likely IL2CPP, no loader.

Generalisation: for a Windows only Unity game, check the macOS depot for GLCore programs first (TASVideos Unity guide says the same).

## Port status (2026-10-05)

* Shaders: `setup/gles_shaders2019.py` (12 byte blob table as in 2021, global then local keyword lists, `m_SubPrograms`). unityport's shaders step fails on 2019.4's nested offsets. 192 programs converted in five files, including the Linux player's own `unity default resources` (InternalErrorShader, InternalClear, GUI/Text Shader fail without it). Left alone: VideoDecodeOSX (macOS only) and three GL 4.x blit programs.
* PC (forced GLES 3.2 context): menus, a run, death screen; no GLSL errors; RSS about 570 MB (same as desktop GL).
* Setup (`tools/patchscript`): Unity player from gamedata/ or downloaded (sha256 checked), unpacked with PortMaster's `7zzs.$DEVICE_ARCH`; data moved out of the .app; five xdeltas, MD5 checked. Dry run on PC and real run on the device both pass (device: under a minute including the 57 MB download).
* Launcher bug found on device: before setup no stamped file exists, so the stamp is empty and equal to a missing `.patch_stamp`; setup was skipped. Fixed with `setup_done` (stamp must be non empty).
* Device (RG35XX H): title renders (about 2 min to title on first start), run loads (about 2.5 min), 29.9 fps in a run, kills and death screen, pad detected (hints switch to controller glyphs). Memory: about 650 to 700 MB RSS, up to 324 MB of swap used at run start.
* Input: gameplay Move is left stick (and WASD) only; the D-pad is only bound in the UI map. The launcher now maps the D-pad onto the left stick half axes (`-lefty:h0.1` etc.). Not yet verified on the device (it dropped off the network during the relaunch).
* Letterbox bars: the game's Pixel Perfect Cameras (level0 x1, level1 x3; ref 800x450, 32 PPU, Upscale RT off, Crop Frame X and Y on, Stretch Fill on) crop to 16:9, leaving 15 px bars at 640x480 and a thin band at 720x720. Crop off fills the screen at the same 1:1 scale on screens up to 800 wide, but zooms out on 1280x720 (smaller sprites, more view); Crop X only pillarboxes 1280x720. So the launcher turns both crop flags off only when DISPLAY_WIDTH <= 800 (dd at fixed offsets 561596 / 288412 / 291604 / 292540, checked before writing; `setup/ppc_crop.py` is the UnityPy reference, byte identical).
* Device drop offs on 2026-10-05/06 were my own error: tools/knulli_stop.sh was called without its pattern arguments, and pgrep -f '' killed every process. Not the game. The script now refuses empty patterns.
* Audio: 57 MB decoded at load, 32 MB of it the two music loops. Since 2026-10-07 the loops stream (`setup/audio_loadtype.py`), about 10 to 30 MB less in a run.

## Performance in fights (2026-10-07, RG35XX H)

Benchmark: a run is started from the title, then R2 is held for 30 s (fps from `GLESPASS_FPSFILE`, frame cap off). Calm play runs at about 50 fps uncapped; fights at 32 to 40, so the 30 fps cap (`GLESPASS_FPSCAP`) holds most of the time. Run to run spread is large because the fights differ: plain runs scored 40.5 and 43.4 fps average with 29 and 9 frames over 50 ms, so only differences well beyond that count.

Within that spread (no measurable change):
* Unity quality level 0 instead of the default Ultra (the game is 2D with shadows off at every level; the levels differ in particle raycast budget and pixel lights).
* Audio at 22050 Hz with 16 real voices; Fixed Timestep 1/30 instead of 0.02 (both via globalgamemanagers).
* box64 `BOX64_DYNAREC_CALLRET=1` and `BOX64_DYNAREC_BIGBLOCK=0` alone (the combined profile with SAFEFLAGS=0, BIGBLOCK=2, FORWARD=1024, CALLRET=1, DIRTY=1 was clearly worse, 23.5 fps).
* `SoundEffectSO.Play` without its exception: it adds each sound to a dictionary in a try and counts copies in the catch, so every overlapping sound throws. Replacing that with TryGetValue changed nothing measurable.
* A title screen warmup that JIT compiles all 5668 game methods (8.7 s spread over the title): the run itself is no faster and the freeze when firing starts stays.

Only audio disabled entirely stood out (46.2 fps, 9 frames over 50 ms), which is not an option.

The freeze when firing starts (one frame of 400 to 770 ms, in every run) is first use cost: about 100 ms of it is shader compiles (glespass appends `shaders N in X ms` to the FPS log line), the rest is new code running for the first time (box64 translating the freshly JIT compiled methods) and first draws of the effects. The JIT warmup shows the JIT is not the part that costs. Fights are bound by the emulated CPU work of the game's scripts.

## To do

* Verify D-pad movement with the remap, and START (pause) behaviour (on PC the frame froze without a visible menu in both GLES and desktop GL runs, so not a port regression; check on the device).
* Long run memory check (20 minutes of hordes). Startup: not the JIT (a full JIT warmup takes 8.7 s); the run load is one frame of about 39 s.
* README, port.json, gameinfo.xml, screenshot, licenses (game scope), repo staging.

## Controller on muOS

On muOS only the sticks and L2 worked. Westonpack's `westonwrap.sh` sources PortMaster's `control.txt` again before it starts the game, and muOS's `control.txt` exports the original `SDL_GAMECONTROLLERCONFIG`, so the mapping the launcher had renumbered for the Unity player's SDL was replaced (Knulli's `control.txt` does not export it, which is why it worked there). The launcher now passes the mapping as a `VAR=value` argument to `westonwrap.sh`, which applies it to the game itself. `westonwrap.sh` evals its arguments, so the mapping is passed as one line with the spaces in the pad's name replaced (SDL matches the GUID, not the name). Tested on an RG35XX H with muOS: menus, Options, a run with movement, R2 to fire, Start to pause, and the exit hotkey.

PortMaster also expects the line `# PORTMASTER: <zip>, <script>` at the top of the launcher. Without it, harbourmaster inserts the line the first time it downloads a runtime, which broke a launcher that was running at the time.

