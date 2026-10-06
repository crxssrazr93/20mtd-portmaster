## Installation

Buy the game on [Steam](https://store.steampowered.com/app/1966900/20_Minutes_Till_Dawn/) and download the macOS build with the [Steam console](https://steamcommunity.com/sharedfiles/filedetails/?id=873543244) (the game has no Linux build, and the macOS one carries the OpenGL shaders the port converts):

`download_depot 1966900 1966902`

Copy `20MinutesTillDawn.app` into `ports/20minutestilldawn/gamedata/`. The first start downloads Unity's Linux player for the game's engine version (57 MB, needs internet) and patches your copy for the device (a few minutes, again after a game update). Without internet, download `UnitySetup-Linux-Mono-Support-for-Editor-2019.4.40f1.exe` from Unity on a computer and put it in `gamedata/` too.

## Controls

The game reads the pad itself. Buttons are named as the game's prompts show them. On Knulli they act as labelled on the device. Other firmwares use SDL's layout by position, where A is the bottom button (labelled B on Anbernic devices).

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

## Thanks

flanne, ptitSeb (box64), binarycounter (Westonpack), Knifethrower (Unity porting tools, glespass), ChevyRay (Express font), the PortMaster team.
