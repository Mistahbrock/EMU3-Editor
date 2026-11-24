# EOS 4.x LCD menus and functions (E6400 / E64xx, EOS 4.62)

Sources: table of contents of the EOS 4.0 Software Manual (printed page numbers in brackets), cross-checked against the screen strings in
`EOV 4,62/eos462update.img` (e.g. Defrag, Doppler/Pan, Transform Multiply, Time Compression, Pitch Change, Bit Convert, Subsume Link into Voices,
Magic load preset all appear there). The same EOS runs on E-IV, e-64, E4K, E6400, E4X, E-Synth. 4.62 adds little to the 4.0 menu tree; the manual is the map.

Legend for "In this editor?" — the user's rule: **add only where it makes sense in an editor**.
- ✔ already there  ◐ partly  ➕ makes sense to add  ○ sampler-only (acts on the hardware / needs the front panel — leave on the sampler)
Coverage marked ✔/◐ is from memory of the code; re-check before relying on it.

## 1. Master (module key: Master)
| Page | Functions | Editor |
|---|---|---|
| Overview | Memory statistics (preset K, sample MB, free) [64] | ✔ Master tab Memory box |
| Utils | AsnKy Assignable Keys [66], ChVol Channel Volume [67], Tones [67], Recal [68], Tests [69], About [70] | ◐ Assign Key…, Channel Volume… exist; Tones/Recal/Tests/About ○ |
| Bank | Erase [71], Name [72], Auto Load [72], Flash utilities [73–77] | ◐ name/erase via bank ops; Auto Bank Load ➕ (SCSI-ID/bank choice is a profile setting); Flash ○ |
| Setup ▸ Tune | Tuning offset, Transpose, Audition key [79] | ✔ |
| Setup ▸ Input/Output | Headroom, Output Boost, Output Format, ADAT dither, Default clock, Word clock in, WC phase [80–85] | ◐ first four ✔; clock items ➕ (profile only) |
| Setup ▸ Misc | Contrast, Wrap field, Screen saver, Disable Sound ROM, Zero-crossing threshold [86–88] | ◐ first three ✔; Disable ROM/ZX ➕ (profile only) |
| Setup ▸ Undo/Redo | enable [89] | ➕ profile only |
| Setup ▸ SCSI/Disk | SCSI ID, termination, Avoid Host on ID, Disk button goes to [90–92] | ✔ |
| Setup ▸ Import | Combine L/R, adjust fractional loops, Memory configuration [93–95] | ✔ / Memory config via Memory screen |
| Master Effects | MultiMode use, Effects A, Effects B, Effects Setup/Control [96–100] | ➕ effect type/parameter forms (Master FX are also in the preset) |
| Sequence Manage | see §4 | ○ (no sequence engine) |
| MIDI ▸ Mode | Basic channel, MIDI mode (omni/poly/multi), Device ID, Local control, Multimode MIDI Mix [103–107] | ✔ MIDI profile |
| MIDI ▸ Controllers | Cntrls1 (Pitch/Mod/Pressure/Pedal, Switch 1–3, Thumb), Cntrls2 (MidiA–L, Send 0–3) [108] | ✔ MIDI profile |
| MIDI ▸ Prefs | Velocity curve, Ctrl#7 sensitivity/curve, Global pedal override, Rcv/Send Program Change, Magic Load Preset [110–113] | ✔ MIDI profile |

## 2. Effects [117–129]
Two processors, A and B (B can feed A), 3-way effects control, master effects, bypass.
- A types: Reverb (decay, HF damping). B types: Chorus, Doubling, Slapback, Stereo Flanger, Delay, Stereo Delay, Panning Delay, Dual Tap, Vibrato, Distortion (feedback, LFO rate, delay time, amounts).
- Editor: ➕ Preset ▸ Effects A/B pages (preset-stored parameters, see §7). Master effects/Effects Setup ○.

## 3. Disk menu [355–386]
| Level | Functions | Editor |
|---|---|---|
| Browser | tree of drives ▸ folders ▸ banks ▸ presets/samples/sequences | ✔ Disk page |
| Disk | Mount drives, Copy System, Format, Low-level format, Backup, Load/Save bank, View, Info, Lock drive, Sleep | ◐ mount ✔, Info ✔; format/backup ○ (do on image) |
| Folder | New, Delete, Rename, Find, View, Info | ✔ New/Delete/Rename; Find ➕ |
| Bank | Delete, Name, Find, Load, Save, View, Info | ✔ (Find ➕) |
| Preset | SoundSprint, Bookmarks, Find, Load, View, Info | ◐ load/copy ✔; SoundSprint/Bookmarks ○ |
| Sample | Find, View, Load, Load .WAV/AIFF, Audition, Info | ✔ (WAV/AIFF import, audition) |
| Sequence | Find, View, Load, Info | ○ (sequences opaque) |

## 4. Sequencer [133–169]
Sequence Manage (record SysEx, load/save standard MIDI files, Name, Export), Transport, Utilities (Erase, Copy, Memory, Jukebox, Edit),
Sequence Edit (track mode, preset per track, MIDI channel modes, volume/pan/submix, initial track state, initial tempo, Cut/Copy/Erase/Note Erase/Paste/Track Delete/Track Copy, Undo),
Tools (Quantize, Transpose, Velocity, Channelize, Channel Extract), Setup (Metronome, Clock, Input, Record, Loop, Transport/MMC, Locate).
- Editor: ○ as a whole. ➕ at most: export/import of sequences inside a bank as .mid (Standard MIDI file) — only if the sequence chunk format is understood.

## 5. Sample Manage [173–190]
| Function | Editor |
|---|---|
| Utils: Erase, Copy, Sample Dump (MIDI, 14/16-bit), Defragment memory | ✔ Erase/Copy; ✔ MIDI Sample Dump; Defrag ○ (RAM-only; irrelevant on a file) |
| Name Sample | ✔ |
| New Sample (threshold, input channels, source & rate, dither, ADC gain, length, arm/force/keyboard trigger, monitor) | ○ (hardware recording) |
| Automatic parameters: auto-DSP operations, auto-placement | ➕ auto-placement on import (key range / root key) |
| Place Sample | ✔ drag/assign to preset |
| Export Sample | ✔ Export WAV |
| Get Info | ✔ Edit Sample Properties |

## 6. Sample Edit [193–240]
| Group | Functions | Editor |
|---|---|---|
| Utilities | Cut, Copy, Paste section, Truncation, Taper | ✔ cut/crop; Taper ≈ Fade In/Out ✔ |
| Tools 1 | Loop (auto-correlation, loop compression, crossfade loop, zero crossing), Loop type, Digital Tuning, Sample Rate Convert, Sample Calculator | ◐ Loop/Crossfade/Crop to Loop ✔; Digital tuning, SRC ➕ |
| Tools 2 | DC Filter, Swap L/R, Stereo↔Mono, Reverse Section, Sample Integrity | ➕ all cheap pure DSP |
| Tools 3 | Gain Change, Compressor (limiter/music/noise), Parametric EQ, FIR phase-linear filter, Aphex Aural Exciter | ➕ Gain/Normalise; EQ, compressor ➕ optional; FIR/Aphex ○ |
| Tools 4 | Transform Multiplication, Doppler, Time Compression, Pitch Change, Bit Converter, Beat Munger | ➕ Pitch/Time, Bit Convert; Doppler/Munger/Transform ○ |
| Undo | multi-level | ✔ |

## 7. Preset Manage [245–250] and Preset Edit [253–354]
**Manage:** Erase, Dump (MIDI), Name, New, Copy, Export, Get Info — ✔ (rename, new, copy, delete, export; Dump ○).

**Edit — structure:** Global ▸ Edit All; Effects A (effect, decay, HF damping, FX amounts, FX B through A); Effects B (effect, feedback, LFO rate, delay time, FX amounts) — ◐ / ➕.
- **Links** (preset ▸ link): Main controls (type, volume, pan, transpose, fine tune); Utilities New/Copy/Delete/Subsume Link; Key window; Velocity window; MIDI filters — ✔ link list/ranges; ➕ MIDI filters, Subsume.
- **Voices:** Main controls; New/Copy/Delete/Split/Solo voice; Sample zones (New, Get Multisample, Delete, Combine, Expand); Key window, Velocity window, Realtime window — ✔ voice/zone/range editing; ➕ Split, Combine/Expand, Realtime window.
- **Dynamic Processing Level:** Utilities (Voice Select with function keys + Isolate, Copy/Delete voices, Automatic voice selection, Set, Solo); Voice tuning/modifiers/setup (Key transpose, coarse/fine tuning, non-transpose mode, chorus amount, delay, start offset, glide rate & curve, solo modes, latch mode, assign group); Amplifier (amp parameters, amp envelope); Filter (parameters, filter types incl. Z-Plane, filter envelope); LFO / Auxiliary envelope (lag processors, aux envelope); Cords; Sample retrigger — ✔ most (LCD pages, envelopes, LFO, cords); ◐ lag/retrigger/glide to check.
- Concepts shown on screen: modulation sources/cords/destinations/processors, envelope generators, LFOs, random sources, clock modulation, groups, bookmarks.
- Display units still raw bytes: LFO Hz, envelope times, filter Hz, glide, tuning (see EOSED-NOTES.md) — the best "make sense in an editor" win.

## 8. Not menus but front-panel functions
Lock button, Arpeggiator (modes, tempo), Keyboard modes (Split, Layer etc.), SoundSprints, Bookmarks, Audition, assignable keys, function keys F1–F8 (soft keys), Exit/Enter, Escape = Exit.
- Editor: Esc/Enter now follow Exit/Enter. Arpeggiator/keyboard modes are preset/sequence parameters → ➕ if the preset chunk exposes them.

## Suggested next steps (editor-relevant, not hardware-touching)
1. Real units in the LCD pages (LFO Hz table, envelope rate table, glide, tuning).
2. Preset Effects A/B page (type + parameters from the preset chunk).
3. Cheap sample tools: Gain/Normalise, Reverse Section, Swap L/R, Stereo↔Mono, DC filter, Sample Rate Convert.
4. Voice utilities: Split voice, Combine/Expand zones, Subsume Link.
5. Profile-only Setup items (clocks, Undo, Disable ROM, ZX threshold) and Auto Bank Load.
