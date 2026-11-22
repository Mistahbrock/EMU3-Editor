# SMDI over SCSI (BlueSCSI initiator)

Fast sample transfer to and from an E-mu EOS sampler (tested: E6400, EOS 4.62, SCSI ID 6) through a BlueSCSI board
(Desktop 50-pin 2023.10a, RP2350) running the passthrough firmware. Measured: receive ≈ 63 KB/s, send ≈ 50 KB/s
(MIDI SDS is a few KB/s).

## Hardware
- BlueSCSI in **initiator** mode: both initiator jumpers (ATN and ACK) set to Initiator; USB to the Mac.
- `TERM_BCKF` ("Back/Feed") jumper capped, so the board supplies termination power. Helpful, not proven to be required.
- Sampler: SCSI ID 6 (any 0–6), Master ▸ Setup ▸ SCSI/Disk ▸ **Avoid Host on ID = 7**.
- The board has no disk in this mode. Quit EMU3 Disk Manager's sampler link first: its helper `emu3linkd`
  (launchd job `com.emu3.automount`) holds the same serial port and swallows replies.

## Firmware
`~/Developer/USB-SCSI/firmware/BlueSCSI-v2-smdi` (BlueSCSI v2 fork, GPL). Build output `build/Pico_2/BlueSCSI_Pico_2_smdi.uf2`; copy of the tested build:
`builds/BlueSCSI_Pico2_smdi19.uf2`. ini needs `InitiatorMode=1` and `InitiatorUSBPassthrough=1`.
Flashing without the BOOTSEL button: `tools/scsi_pass.py bootsel`, then copy the UF2 to the RP2350 drive.

The EOS sampler glitches its SCSI phase lines between bytes, so the stock initiator aborts after the first command byte.
The passthrough has a "loose" mode (request flag 8) that ignores the phase lines and only follows REQ/ACK; phases are
told apart only when a data read ends (C/D or MSG stable for 100 µs).

Host protocol on the board's second USB serial port (little endian):
`'S' 'X' 1 op tag target cdbLen flags outLen[4] inLen[4] timeoutMs[4] cdb data` →
`'X' 'S' 1 op tag result status senseLen dataLen[4] ownId maxData[2] sense data`. Ops: 1 SCSI command, 2 info, 3 bus reset, 4 reboot to BOOTSEL, 5 passive bus recorder.
Flags: 1 REQUEST SENSE on check condition, 2 no IDENTIFY, 4 trace phases in the CDC0 log, 8 loose phase handling.

## SMDI
Messages ride in SCSI SEND (0x0A) / RECEIVE (0x08): `"SMDI"` + ID (BE32) + length (BE24) + body.
Layouts follow OpenSMDI (LGPL, github.com/rdmark/OpenSMDI) and were verified on the sampler.
- Master Identify 0x00010000 → Slave Identify 0x00010001
- Header request 0x01200000 [num24] → Sample Header 0x01210000 or Reject 0x00020000 [code BE32]: 0x00200002 no sample, 0x00200000 out of range
- Upload: Sample Header → Transfer Ack 0x01220001 (packet length, 512) → Begin Transfer 0x01220000 [num24, len24] →
  Data Packet 0x01100000 [pn24, big-endian 16-bit words], each answered by Send Next 0x01030000, the last by End Of Procedure 0x01040000
- Download: header request → Begin Transfer → Send Next [pn24] → Data Packet
- Delete 0x01240000, Abort 0x01050000, WAIT 0x01020000 means ask again.
- **Loop end must be length−1 for a sample without loop** (0 makes the sampler's panel freeze for a while).
- A sample sent over SMDI is placed across the whole keyboard of the current preset (EOS manual p. 392); the sampler's panel stalls while it receives.

## Editor
File ▸ SMDI Transfer (SCSI)… (⌘T): port, sampler ID, sample list (1–999), send selected sample, receive into the selected sample, delete.
Code: `Sources/MIDI/EDSMDI.{h,m}` (board link + client, transport-agnostic via `EDSMDIExec`), `Sources/UI/EDSMDIPanel.{h,m}`.
Tests: `Tests/SMDITest.m` (fake sampler). A RaSCSI/SCSI2Pi route only needs another `EDSMDIExec`.

## Switching firmware without BOOTSEL (scsi_pass.py use)

`python3 scsi_pass.py use smdi` (or `use smdi19`, or a .uf2 path) asks the running SMDI firmware to reboot into BOOTSEL (passthrough op 4), copies the UF2 to the RP2350 drive and waits until the board answers again. It needs the SMDI passthrough firmware to be running already; from a dead or non-SMDI board, hold BOOTSEL while plugging in.

The SMDI firmware has no disk-serving mode: in target mode it crashes when the sampler selects ID 2 (unresolved). The disk-serving `usbblk` builds are `.bin` files, installed via BlueSCSI's SD-card updater (copy the .bin to the card root, power-cycle) — they cannot be flashed by this script. Restore image: firmware/restore/BlueSCSI_Pico2_2026-03-01_d4a38955.bin.
Note: `use smdi` picks the newest non-cardless build (smdi23); `smdi19` is the plain tested one.

## Sample numbers

The SMDI sample number equals the number on the sampler's display (S001 = 1, S020 = 20); the sampler honours the number the editor asks for. Sample 0 (S000, the clipboard) is refused by the sampler itself — verified with a header request and with an upload that bypassed the editor's range check. The panel says so next to the Sample # field and in its error message. Not tried: MIDI SDS to S000.
