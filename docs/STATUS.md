# EMU3 Editor — status

Native Objective-C / AppKit app. Build: `xcodegen generate && xcodebuild -project EMU3Editor.xcodeproj -scheme EMU3Editor build`.
Model tests: `Tests/run-tests.sh` (synthetic E4B bank; not real-sampler data).

## Done (stage 1)
- Disk layer copied from EMU3 Disk Manager (`Sources/Disk`), plus `replaceContentsOfFile:withData:` (in-place overwrite: keeps bank id and first cluster).
- E4B model (`Sources/Model/EDBank`): IFF parse, E3S1 sample header + 16-bit PCM, E4P1 presets (name/number only), TOC1 fix-up on save, byte-identical round trip.
- Sample/loop editor: waveform, draggable loop markers (⌥ snaps to zero crossing), zoom, audition with sustain loop, normalize/reverse/fades/DC/crop/crossfade, WAV export (smpl loop), audio import, undo.
- Save writes a backup of the loaded bank to `~/Library/Application Support/EMU3 Editor/Backups` first.

## Verified on real data (HD20_14GB image, read through the Disk Manager NFS mount, 21 Nov 2026)
- All 200 E4B banks on the disk parse and re-serialize byte-identical. Edited saves (rename, loop move, shrink) re-parse with a consistent TOC1 (`Tests/InspectBank.m`, `Tests/EditReal.m`).
- Real-bank quirks handled: FORM size is declared 4 bytes short; TOC1 size field = chunk size − 2, positions big-endian; some banks carry trailing bytes after the last chunk (kept verbatim); some have no TOC1.
- **Emulator 3X / ESI-32 v3 banks** (`Sources/Model/EDLegacyBank`): all 90 on the disk parse; 12,523 samples and 3,354 presets read, 0 samples locked. Unedited save is byte-identical; a same-size edit (rename, loop, gain) and a resize (crop) re-parse correctly and leave every other sample untouched (`Tests/InspectLegacy.m`).
- 3X layout facts (probed, not taken on trust): file = 0x4C + next_preset + next_sample; preset table 0x17CA (relative to 0x2B72), sample table 0x1BD2 (absolute from 0x400000); sample object = 0x5C header + int16 PCM; stereo = L then R; right-only mono samples exist (the L words mirror the R words); the 4-byte field at 0x10 is an opaque ID (not a CRC/sum) and is preserved; sample_blocks = ceil(next_sample/512), total_blocks = preset_blocks + sample_blocks.
- Samples whose layout does not match the known rules are shown but locked and written back byte for byte (none on this disk).

## Still unverified
- Loading an edited bank on the sampler itself (both formats). The resize path for 3X banks shifts the sample table, the data-offset words at 0x3C/0x40 and the block counts; it is internally consistent but only hardware can confirm the sampler accepts it.
- Whether the sampler checks the sample ID field at 0x10 (it is left unchanged on edits).
- The 4 unknown bytes at 0x12 of the sample header are preserved, not recomputed.
- Not yet tried on the sampler: save a bank with a changed loop and load it on the hardware.

## Not built yet
- Preset editor (zones, sample references, voice/filter/envelope/LFO/cords), bank-level parameters, E4P1 field map (see E4_Open_Interface for the SysEx parameter table).
- Original Emulator III ("EMULATOR THREE") banks — different offsets; none on the test disk.
- 3X preset zone/voice data is kept as raw bytes (only the name is editable).
- MIDI Sample Dump (SDS) transfer, live sampler link integration.
- Add / remove / reorder samples in a bank.

## Preset editor (added)
- Presets tab: preset list, structure outline (preset ▸ voice ▸ sample refs), grouped parameter table, name/number fields.
- E4 (EOS): full parameter tables (header, voice, sample ref); add/remove sample ref, duplicate/remove voice. Verified structurally on 4,719 presets.
- Emulator 3X / ESI-32: header, realtime controls, zone table and key map editable; voice blocks only decode the sample number (other bytes raw).
- Checked: `build/presettest` over 290 real banks, 8,073 presets, 0 structure failures. Visually checked on one E4B and one 3X bank.
- Not yet verified on hardware. Field names for E4P1 follow E4BTool (AGPL), see CREDITS.md.

## MIDI Sample Dump (SDS) transfer (added)
- File ▸ MIDI Sample Dump… (⌘D): pick MIDI out/in ports, device ID, then Send selected sample, Request sample from sampler (by number), or Wait for dump from sampler.
- Sends the selected sample's left channel (stereo samples go mono), 16-bit, with loop points; the 4 guard frames per side are stripped and re-added on receive. A received sample replaces the audio of the selected sample (undoable); it does not add a new sample to the bank.
- Handshake: ACK/NAK/WAIT/CANCEL, retries on bad checksums, open-loop fallback when the sampler does not answer within 2 s.
- Tested (Tests/SDSTest.m, run by Tests/run-tests.sh): codec round trip at several sizes, checksum rejection, in-memory sender↔receiver transfers (clean, one corrupted packet, no handshake, packet counter wrap).
- NOT tested against a real sampler. Whether the EMU3/ESI-32 accepts SDS, and its device ID and sample numbering, still need checking on hardware.

## Send Sample to Sampler Disk (SCSI route, added)
- File ▸ Send Sample to Sampler Disk… (⇧⌘D): writes the selected sample as a one-sample EOS bank (TOC1 + E3S1) into the volume EMU3 Disk Manager serves to the BlueSCSI board (starts in "Default Folder"). Rescan SCSI on the sampler, then load the bank.
- EOS (E4B) samples only; 3X / ESI-32 samples are refused.
- Tested: builds a bank that re-parses to identical audio, loop and rate for every sample of 3 real E4B banks (Tests/ModelSelfTest.m also covers it). Not yet loaded on a real sampler; the TOC size and FORM size conventions copy those of real banks.

## SMDI over SCSI (in preparation)
- Sampler is the slave; the BlueSCSI Desktop 50-pin (2023.10a, supports initiator mode) will be the initiator at ID 7, sampler at ID 6.
- Firmware passthrough built in ~/Developer/USB-SCSI/firmware/BlueSCSI-v2-smdi (see USB-SCSI-Bridge-Plan.md); not flashed yet. SMDI protocol code in the editor is not written: the message layouts are still unknown.
- Do not derive code from ~/Developer/zoeos-master (proprietary EULA).

## SMDI over SCSI (2026-11-22)
Working end to end with the BlueSCSI initiator firmware: send, receive, list and delete samples (see docs/SMDI.md). Panel: File ▸ SMDI Transfer (SCSI)… (⌘T). Not yet done: stereo/8-bit/24-bit samples, sending whole banks, RaSCSI/SCSI2Pi executor, sample placement control.
