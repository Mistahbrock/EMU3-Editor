# EMU3 Disk Manager: License and Credits

Copyright (C) 2026 Rhyno Audio

EMU3 Disk Manager, its helpers (`emu3linkd`, `emu3nfs`), the installer scripts and the modified BlueSCSI firmware
are free software: you can redistribute and modify them under the terms of the GNU General Public License,
version 3, as published by the Free Software Foundation. They are distributed in the hope that they will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
The full license text is in the file `LICENSE`.

The complete source code of every program in the installer is published at
<https://github.com/Mistahbrock/EMU3-Disk-Manager> and must be given to anyone who receives the installer
(GPL version 3, section 6).

## Based on the work of

| Project | Author | Used for | License |
| --- | --- | --- | --- |
| [emu3fs](https://github.com/dagargo/emu3fs) | David García Goñi | The E-mu EOS disk layout (structures and field names) | GPL 3 or later |
| [emu3bm](https://github.com/dagargo/emu3bm) | David García Goñi | The E-mu bank file format (offsets and structures) | GPL 3 or later |
| [BlueSCSI v2](https://github.com/BlueSCSI/BlueSCSI-v2) | Eric Helgeson, Androda and contributors | The SCSI board firmware; the installer carries a modified build with the USB disk link | GPL 3 |
| [DiskJockey](https://diskjockey.onegeekarmy.eu/) | One Geek Army | A tool to create .hda disk images (linked from the About box, not included) | n/a |

## Inside the firmware build

The firmware file in the installer (`BlueSCSI-firmware.uf2`) is built from BlueSCSI v2 and contains these
components. Their licenses are in their own sources; the list follows BlueSCSI's own README and the library files.

| Component | Author | License |
| --- | --- | --- |
| [ZuluSCSI firmware](https://github.com/ZuluSCSI/ZuluSCSI-firmware) (BlueSCSI v2 is a fork) | Rabbit Hole Computing and contributors | GPL 3 |
| SCSI2SD V6 | Michael McMaster | GPL 3 |
| [BlueSCSI v1](https://github.com/erichelgeson/BlueSCSI) and [ArdSCSIno-stm32](https://github.com/ztto/ArdSCSino-stm32) | Eric Helgeson; ztto | as in BlueSCSI's README |
| [SdFat](https://github.com/BlueSCSI/SdFat) | Bill Greiman | MIT |
| CUEParser | Rabbit Hole Computing | MIT |
| minIni | CompuPhase | Apache 2.0 |
| BlueI2S | BlueSCSI project | LGPL 2.1 or later |
| Raspberry Pi Pico SDK and TinyUSB | Raspberry Pi Ltd; Ha Thach and contributors | BSD 3-Clause; MIT |

## Names

E-mu, Emulator and EOS are trademarks of their owners. BlueSCSI is a trademark of its owner. This program is an
independent project and is not affiliated with or endorsed by E-mu, Creative Technology or the BlueSCSI project.
The firmware in the installer is an **unofficial, modified build** and is not supported by the BlueSCSI project. The
names are used only to say which equipment the program works with.

## Built with

Claude (Anthropic) assisted in writing the code.
