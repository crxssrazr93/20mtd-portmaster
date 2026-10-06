## Installation

Buy the game on [Steam](https://store.steampowered.com/app/1966900/20_Minutes_Till_Dawn/) and download the macOS build with the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244) (the game has no Linux build, and the macOS one carries the OpenGL shaders the port converts):

`download_depot 1966900 1966902`

Copy `20MinutesTillDawn.app` into `ports/20minutestilldawn/gamedata/`. The first start downloads Unity's Linux player for the game's engine version (57 MB, needs internet) and patches your copy for the device (a few minutes, again after a game update). Without internet, download [UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe](https://download.unity3d.com/download_unity/ffc62b691db5/TargetSupportInstaller/UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe) on a computer and put it in `gamedata/` too. If the first start fails, the reason is in `ports/20minutestilldawn/setup_log.txt`.

## Controls

The game reads the pad itself. Buttons are named as the game's prompts show them. They work by position, as SDL lays them out: A is the bottom button (labelled B on Anbernic devices). On Knulli you can swap them per game: long press X on the game in the ports list and change its A/B layout setting.

| Button | Action |
| :----- | :----- |
| Left stick / D-pad | Move |
| Right stick | Aim |
| R1 / R2 | Shoot (hold) |
| L1 / L2 | Skill |
| X | Reload |
| Y | Toggle auto aim |
| A | Confirm |
| Start | Pause |
| Select + Start | Exit |

## Notes

Runs through box64 and Westonpack on Unity's own Linux player. Small screens get larger menu text and a full screen view (no 16:9 bars). Steam features (achievements, the Endless leaderboard) are not available.

Source and build instructions: https://github.com/crxssrazr93/20mtd-portmaster

## Reporting problems

Please send `ports/20minutestilldawn/log.txt`, `ports/20minutestilldawn/setup_log.txt` and `player.log` (Unity's own log). `log.txt` is rewritten on every start and the run before it is kept as `log.prev.txt` (the setup log likewise), so send both if the game was started again after the problem. Lines starting with `PORT:` list the device, firmware, screen, memory and swap, the state of the setup, and at the end how long the game ran and whether the system ran out of memory.

## Thanks

flanne, ptitSeb (box64), binarycounter (Westonpack), Knifethrower (Unity porting tools, glespass), ChevyRay (Express font), the PortMaster team.
