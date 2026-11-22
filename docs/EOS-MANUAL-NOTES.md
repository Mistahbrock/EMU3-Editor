# Notes from the EOS 4.0 Software Manual (e-mu-eos-4-manual-476441.pdf)

Manual page numbers are the printed ones.

## MIDI Sample Dump (p. 175–176)
- Started on the sampler: Sample Manage ▸ Utils (F1) ▸ Dump… (F3) ▸ Direction Transmit/Receive, Word Size 14 or 16, Side (stereo), sample ▸ OK. The sampler does not answer dump *requests* from outside.
- 14-bit words transfer about 30% faster. Two cables (closed loop) are faster than one because there is no idle time between packets.
- Sample numbers are kept through a transfer (#36 overwrites #36). When receiving, the selected sample is overwritten. Loop data is kept, preset parameters are not.

## SMDI over SCSI (p. 392)
- The sampler is strictly a slave: it cannot start a transfer; the computer's editor must. Tested with Adaptec 1542C on PC, and Recycle / Transfer Station / Alchemy on Mac.
- Alchemy needs sample number + 1. Sample 000 (clipboard) can't be transferred.
- A sample received over SMDI is placed across the whole keyboard and overwrites the current preset's placement: create an empty preset first.
- SMDI file carries: name and number (1–999), mono/stereo, length plus one loop, rate, pitch, bit depth, key placement (E-mu extension).
- Master ▸ Setup ▸ SCSI/Disk: SCSI ID of the sampler, termination, "Avoid Host on ID" (set it to the host's ID).
- The Disk Manager's BlueSCSI board uses ID 7 by default, so a second device acting as initiator (RaSCSI/SCSI2Pi) needs another ID.
- The manual does not give the SMDI command set; ESMDI (open source) is the reference for that.

## Checked against the EOS 4.62 update image (EOV 4,62/eos462update.img)
The image is a raw 1.44 MB floppy ("EOS v4.62" header, 68000 code); screen texts are plain strings, so `strings` shows the menus.
- Master ▸ Utils: AsnKy (Assignable Keys), ChVol (Channel Volume), Tones (Test Tones: sine, triangle, square, sawtooth), Recal, Tests (diagnostics), About.
- Master ▸ Bank: Erase, Name, Auto Load, Flash (resident). Master ▸ Setup: Tune, Output, Misc, SCSI, Import, Memory (config). Effects setup, Sequence Mixer.
- Master ▸ MIDI: Mode (Basic Channel, MIDI mode omni/poly/multi, Device ID, Local Control), Cntrls1 (Pitch/Mod/Pressure/Pedal, Switch 1–3, Thumb), Cntrls2 (MidiA–L, Send0–3),
  Prefs1 (Velocity Curve, Ctrl#7 Sensitivity, Ctrl#7 Curve: linear/logarithmic/squared, Global pedal override), Prefs2 (Rcv/Send Program Change, Magic load preset).
- Controller sources: off, ptwheel, chnpres, cc<n>. Only "linear" is spelled out among the velocity curves; the others are drawn as graphs.

## Master ▸ Setup pages in the editor (Master tab ▸ Setup)
Page titles and field names come from the EOS 4.62 image; value ranges from the EOS 4.0 manual (pp. 79–92). The sampler keeps all of these in flash, so the editor only stores a reference profile (SamplerMIDIProfile).
- Tuning: Tuning Offset (±100 cents, shown as ±64/64ths of a semitone), Transposition ±12, Audition Key.
- Output: Headroom 0–15 dB (default 3), Output Boost +0/+12 dB, Output Format analog / S/PDIF / AES pro, ADAT Output Dither on/off.
- Miscellaneous: Contrast −8..+7, Wrap Field Selection, Screen Saver Never/10–60 min.
- SCSI / Disk: SCSI ID, SCSI termination, Avoid Host on ID, Disk Button goes to Sprint/Last.
- Import Options: Combine L/R into stereo, Adjust Akai/Ensoniq fractional loops.
- Not added: Bank (Erase/Name/Auto/Flash), Recal, Tests and About act on the sampler itself; Memory Config is covered by the Memory screen on the Overview.
