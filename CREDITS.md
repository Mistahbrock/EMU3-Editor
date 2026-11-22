# EMU3 Editor: License and Credits

Copyright (C) 2026 Rhyno Audio

EMU3 Editor is free software: you can redistribute and modify it under the terms of the GNU General Public License,
version 3, as published by the Free Software Foundation. It is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
The full license text is in the file `LICENSE`. The source code is published at
<https://github.com/Mistahbrock/EMU3-Editor>.

## Based on the work of

| Project | Author | Used for | License |
| --- | --- | --- | --- |
| [EMU3 Disk Manager](https://github.com/Mistahbrock/EMU3-Disk-Manager) | Rhyno Audio | The EOS disk layer in `Sources/Disk` (copied from it) | GPL 3 |
| [emu3fs](https://github.com/dagargo/emu3fs) | David García Goñi | The E-mu EOS disk layout (structures and field names), through the Disk Manager | GPL 3 or later |
| [emu3bm](https://github.com/dagargo/emu3bm) | David García Goñi | The E-mu bank file format (offsets and structures) | GPL 3 or later |
| [E4_Open_Interface](https://github.com/JohnnyGadget/E4_Open_Interface) | JohnnyGadget | Reference for the Emulator 4 preset (E4P1) parameter table; consulted, no code copied | see its repository |

Format details that were not in those sources were found by examining real banks and disks, and are noted in
[docs/STATUS.md](docs/STATUS.md). The menu pages and value ranges in the Master tab follow the E-mu EOS 4.0 manual and the
EOS 4.62 operating system's own menu text, as notes in [docs/EOS-MANUAL-NOTES.md](docs/EOS-MANUAL-NOTES.md). The manual itself is not included.

## Names and artwork

E-mu, Emulator, EOS and the E-MU logo are trademarks of their owners. The logo in `Graphics/` is a redrawn
reproduction used only to say which equipment the program works with. This program is an independent project and is not
affiliated with or endorsed by E-mu or Creative Technology.

## Built with

Claude (Anthropic) assisted in writing the code.
