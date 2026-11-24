# Notes from eosed (lentferj/eosed)

Source: https://github.com/lentferj/eosed — a Python terminal editor for E4 / E4XT / E6400 over MIDI SysEx (GPL-2.0-or-later).
These are **facts and pointers** worth checking against our own hardware (E6400, EOS 4.62), not code to copy. Where the author measured on an
E4XT Ultra running EOS 4.70, the numbers may differ on 4.62.

## What it has that we do not

1. **Display conversions.** The sampler shows envelope rates, LFO rates, filter frequencies and so on in real units. We show raw bytes.
   - `docs/data/e4xt_lfo_rate_table.json` — LFO rate byte 0..127 → Hz, read from the panel: 0 = 0.08 Hz, 64 = 4.12 Hz, 127 = 18.01 Hz (full table in the file).
     Would let the LFO page and our LFO preview show Hz. Cross-checked by audio at several bytes.
   - `docs/data/eos462_env_rate_table_candidate.json` — a 128-entry u16 table found by shape inside the **EOS 4.62** image: 65535 → 4, log-linear,
     steeper below byte 20 and above byte 100. Likely the envelope rate law (not proven). It is the right shape for the "Scaled" time axis of the
     envelope graphs (ours is linear in the rate byte).
   - `docs/data/e4xt_filter_cutoff_law_lp2.json` — filter corner Hz per byte, LP2 only (other filter types sit lower). Cutoff is done in hardware, so it can only be measured.
   - README "Display-conversion curves": glide rate (two 128-entry tables), master tuning offset (65 entries), chorus initial ITD (33 entries), morph gain ±24 dB.
2. **Memory queries.** Preset RAM total/free (KB) and sample RAM total/free (10 KB units) — we already read these (that is what the Memory box uses).
3. **Front panel over SysEx** (`F0 18 7F <dev> 7A …`): session open, the full key map, the data wheel and the 240×64 LCD as a bitstream (7 bits per byte).
   A full screen costs ~2.2 kB / ~0.7 s of MIDI, a delta request ~0.09 kB; poll the cheap one. The device never pushes. Reverse engineered, E-mu documented it in 1996 ("Peptalk").
   A live mirror of the sampler's LCD in our editor would be possible. Gated behind "armed" writes because the menus include erase utilities.
4. **Program Change selects a preset for real** (Bank MSB 0, LSB = block of 128, then PC) — edits sent over SysEx do not appear on the front panel until the preset is touched there.

## Facts that agree or disagree with what we do

- Envelope stage order is **Atk1, Atk2, Dcy1, Dcy2, Rls1, Rls2**, held at stage 4's target (that level is the sustain). This is the order our LCD pages and graphs use. ✔
- Amp envelope levels are 0..100 %, filter and aux are −100..100 % (bipolar). We already clamp the volume graph at 0. ✔
  (We show the stored byte, −127..127; the sampler shows percent — worth a check against the sampler's screen.)
- LFO shapes: triangle, sine, sawtooth, square, `0,1,0,-1`, `C,E,G,C`, `C,D,F,G`, 8-step pentatonic.
- Filter envelope level range in the spec's own table was wrong (spec says 0..100); confirmed bipolar on the device.

## Lessons worth keeping

- **"Number of X" commands are not plain counts** (voices, zones): never trust a count from a command that merely looks like its sibling; walk the real data instead.
  Relevant if we add live voice/zone reads over SysEx.
- Two independent cross-checks were still not enough for a general formula; each parameter needs its own live check.
- Preset **restore** over SysEx is specified but unverified on hardware; their editor deliberately has a "write mode" gate and requires typing the preset number back before overwriting.
- The remote spec: "Remote Preset Editing via MIDI SysEx", Draft #30, EOS 4.00 (E-mu, 17 Feb 1999) — the primary source for the parameter ids (GLOBAL 0–21, LINK 23–35, VOICE 37–182, MASTER 183–222, selectors 223–227).

## Possible next steps for the editor

1. Show real units: LFO Hz (table above), envelope times (rate table), filter Hz, glide, tuning, chorus ITD.
2. Use the envelope rate table for the graph's Scaled mode and for a "time to stage" readout.
3. Optional: LCD mirror of the sampler over the panel protocol (read-only first).
4. Check the −127..127 vs −100..100 % display of levels against the sampler screens.

---

# Notes from eosflash (nkrypth/eosflash)

Source: https://github.com/nkrypth/eosflash — a CLI (Linux / Windows binaries only, no source, no licence stated) to inspect, convert and write EOS firmware.
Only the README and changelog were read; the binaries were not run.

- **OS file formats it knows:** raw floppy image (`.img`), OS binary (`.eos`, compressed), legacy DOS executable (`.exe`), EOSLoader "DownLoad Image" (`.dli`, Ultra only —
  the only distribution form of the 4.59beta7 and 4.60a Ultra builds), and full or partial ROM dumps (IC halves low/high, 1 MB flash chip halves).
- **Two hardware families:** Classic (EIV / E4 first and second generation, Motorola 68020) and Ultra (Coldfire MCF5206E). Their OS images are **not interchangeable** — never flash an Ultra OS onto a Classic.
  The E6400 with EOS 4.62 here is the Classic family.
- **ROM layout facts from the changelog:** a 4 MB FlashROM has a different RAM map and chip layout from the older ROMs and needs a 128 KB bootloader (a 64 KB one will not boot);
  when building a 4 MB ROM the OS is copied at offset 0x20000; a 2 MB OS can be decompressed to a 4 MB-compatible stream (and back).
- **Floppy OS updates:** use freshly formatted disks; bad sectors are the usual cause of failed writes. Flash Prep is a separate disk set.
- **Pointer:** emu.tools (https://emu.tools) updates E4 samplers over MIDI, without floppies.
- **Relevance here:** none for the editor's own features today. It only matters if we ever want to verify an OS image (such as the "EOV 4,62" folder) or explain
  which firmware fits which machine. Per the standing rule, nothing here is to be used to flash the sampler without being asked.

---

# Notes from samplerdisc (bmxcode/samplerdisc, MIT)

Source: https://github.com/bmxcode/samplerdisc — pure-Python converter of vintage sampler CD-ROM images (AKAI, E-mu EMU3, Roland S-7xx, Kurzweil, ISO 9660) to WAV.
Read: README, `docs/formats/emu3.md` (the E-mu part, 89 kB) and the E-mu ADRs. Verified by the author against 10+ real E-mu discs (EIII/ESI/E-IV libraries) and cross-checked with lentferj/mpc2emu.

## Already agrees with what we do
- Block 0 of the `EMU3` filesystem ends with a checksum: 16-bit sum of the first 255 little-endian words, stored at 0x1FE. (We implement this in `EMU3Filesystem.m`.)
- `FORM/E4B0`: the declared FORM size is a few bytes short (4–12), so chunks are walked to the end of the data and the size is not trusted. (We already do this.)
- `E4P1` name field is 16 bytes at chunk-body +2 (same offset as a sample record's name).
- Everything on the disc is addressed in 512-byte blocks; the FAT starts at block 2.

## Facts we could use or double-check
- **Header geometry is not fixed.** 0x08 = folder table block, 0x0C = blocks reserved, 0x10 = first folder's bank directory (0x08 + 0x0C == 0x10). Across discs the value at 0x10 takes several values (9, 12, 13, 15, 10). The FAT runs from block 2 up to 0x08, which is 4, 5 or 7 blocks. Read, never assume.
- **Directory records, 32 bytes:** name 16 bytes padded with spaces *or NULs* (requiring spaces dropped banks silently), start u16 @18, length u16 @20, flags u16 @26.
  Flags: 0xFFFF folder, 0x0080/0x0081 bank — but some discs use 0x0013 / 0x0018 on folder entries, so the flags word is *not* a safe "is folder" test. A directory ends at a zeroed entry or a non-bank flags word.
  `start`/`len` contiguity is not a validity test (it fails on most banks of some discs). Each folder's directory is bounded by the next folder's start block.
- **`start` is a FAT cluster index** and the allocation unit is per-disc (256 KiB or 1 MiB seen), so measure it; do not derive it.
- **A fragmented FORM bank must be read along its FAT chain**; a contiguous read stops at the first break and silently lists fewer samples (12 of 20 in their worst case).
- **Sample record layout** (EIII/ESI/E-IV `E3S1`): fields at +22, +26, +30 … +50 (not +24/+28/+32); rate at +58; 92-byte header; a record may declare its single channel on the right.
  +34 is the *right* channel end, not the record length. Payload is **signed 16-bit little-endian** (a sector-aligned probe makes it look big-endian — a trap).
- **Stereo is stored as two blocks (left then right), not interleaved**; the record's paired length fields are the channel count, and `end_L + 2 == start_R` confirms it.
- **Loops:** a loop end past the payload should be refused, not clamped. A "whole-file loop" is written inset by a few bytes at both ends, not at frame 0 — treat it as "no loop".
- **There is no root key in the sample record** — the root key lives in the preset's zones. The E-IV sample directory is big-endian, the only big-endian part.
- `Credits` banks: sample-free FORM banks whose `E4P1` name fields are readable text lines (who sampled, how to contact the publisher).

## Possible features
1. **Open EMU3 sample CDs directly** (ISO / BIN images of E-mu library discs): same directory format as our disk images, plus the CD origin probe and cluster-size measurement.
2. Show "Credits" text of a bank on the Disk page's Info.
3. Check our loop import: refuse loop ends past the data, ignore whole-extent loops with a small inset.

## Process wisdom (worth copying as habits)
- Every constant is verified against real media; a table in a document is a note, not a test — pin counts and **SHA-256 of payloads per disc** in the test suite.
- "A probe must confirm a file": detect formats by signature and checksum, not by extension or a single magic.
- A previous revision of their own doc concluded "everything is mono" from a measurement that only refuted interleaving; keep the wrong turns written down.
