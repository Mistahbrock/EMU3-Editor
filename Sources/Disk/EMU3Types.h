// EMU3Types.h — E-MU 3/4 on-disk filesystem and bank structures
// Portions of this file are derived from emu3fs and emu3bm,
// Copyright (C) 2018 David García Goñi <dagargo@gmail.com>, licensed under the GNU GPL version 3 or later
// (https://github.com/dagargo/emu3fs, https://github.com/dagargo/emu3bm).
// The rest is Copyright (C) 2026 Rhyno Audio. This file is part of EMU3 Disk Manager, free software under the GPLv3.

#pragma once
#import <Foundation/Foundation.h>
#import <stdint.h>

// ──────────────────────────────────────────────────────────────────────────────
// Filesystem constants
// ──────────────────────────────────────────────────────────────────────────────
#define EMU3_BLOCK_SIZE             512
#define EMU3_DENTRY_SIZE            32    // 16-byte name + 16-byte data
#define EMU3_FILENAME_LEN           16
#define EMU3_BLOCKS_PER_DIR         7     // block_list[7] in dir_attrs
#define EMU3_ENTRIES_PER_BLOCK      16    // 512 / 32
#define EMU3_CLUSTER_ENTRIES_PER_BLOCK 256 // 512 / 2 (each entry is uint16)
#define EMU3_LAST_CLUSTER           0x7FFF
#define EMU3_USED_CLUSTER           0x8000
#define EMU3_FREE_CLUSTER           0x0000
#define EMU3_DIRBLOCK_NONE          -1
#define EMU3_I_ID_ROOT_DIR          1

// Superblock uint32 field indices (little-endian, 4 bytes each)
#define EMU3_SB_ROOT_DIR_BLOCK      2   // dword index = byte offset 0x08
#define EMU3_SB_DATA_AREA_BLOCK     8   // dword index = byte offset 0x20
#define EMU3_SB_FAT_START_BLOCK     10  // dword index = byte offset 0x28
#define EMU3_SB_SLOT_SIZE_KB        11  // dword index = byte offset 0x2C

// Directory entry id-byte values that indicate a directory (not a file)
#define EMU3_ID_DIR_TYPE_A          0x40
#define EMU3_ID_DIR_TYPE_B          0x80

// File type codes in dentry
#define EMU3_FILE_TYPE_DELETED      0x00
#define EMU3_FILE_TYPE_SYSTEM       0x80
#define EMU3_FILE_TYPE_STANDARD     0x81
#define EMU3_FILE_TYPE_UPDATED      0x83

// Directory type codes
#define EMU3_DIR_TYPE_A             0x40
#define EMU3_DIR_TYPE_B             0x80

// ──────────────────────────────────────────────────────────────────────────────
// Bank format constants
// ──────────────────────────────────────────────────────────────────────────────
#define EMU3_BANK_NAME_LEN          16
#define EMU3_BANK_SIZE              512
#define EMU3_NOTES                  88
#define EMU3_MEM_SIZE               0x08000000  // 128 MiB
#define SAMPLE_OFFSET               0x00400000  // 4 MiB

// Bank format strings (16 chars, space-padded)
#define EMU3_FORMAT_EMULATOR_THREE  "EMULATOR THREE "
#define EMU3_FORMAT_EMULATOR_3X     "EMULATOR 3X    "
#define EMU3_FORMAT_ESI32_V3        "EMU SI-32 v3   "

// Offsets — Emulator THREE (EIII)
#define EMU3_SAMPLE_ADDR_OFFSET_THREE   0x0204
#define EMU3_PRESET_START_THREE         0x074A
#define EMU3_PRESET_SIZE_ADDR_THREE     0x006C
#define EMU3_MAX_SAMPLES_THREE          99
#define EMU3_MAX_PRESETS_THREE          100

// Offsets — Emulator 3X / ESI-32 v3
#define EMU3_SAMPLE_ADDR_OFFSET_3X      0x1BD2
#define EMU3_PRESET_START_3X            0x2B72
#define EMU3_PRESET_SIZE_ADDR_3X        0x17CA
#define EMU3_MAX_SAMPLES_3X             999
#define EMU3_MAX_PRESETS_3X             256

// Sample option flags
#define EMU3_SAMPLE_OPT_LOOP            0x0001
#define EMU3_SAMPLE_OPT_LOOP_RELEASE    0x0008
#define EMU3_SAMPLE_OPT_MONO_L          0x0020
#define EMU3_SAMPLE_OPT_MONO_R          0x0040
#define EMU3_SAMPLE_OPT_STEREO          0x0060

// ──────────────────────────────────────────────────────────────────────────────
// On-disk filesystem structures (little-endian, packed)
// ──────────────────────────────────────────────────────────────────────────────
#pragma pack(push, 1)

typedef struct {
    uint16_t start_cluster;
    uint16_t clusters;
    uint16_t blocks;
    uint16_t bytes;
    uint8_t  type;
    uint8_t  props[5];
} emu3_file_attrs_t;

typedef struct {
    int16_t  block_list[EMU3_BLOCKS_PER_DIR];
} emu3_dir_attrs_t;

typedef struct {
    uint8_t  unknown;
    uint8_t  id;
    union {
        emu3_file_attrs_t fattrs;
        emu3_dir_attrs_t  dattrs;
    };
} emu3_dentry_data_t;

typedef struct {
    char               name[EMU3_FILENAME_LEN];
    emu3_dentry_data_t data;
} emu3_dentry_t;  // 28 bytes

// ──────────────────────────────────────────────────────────────────────────────
// On-disk bank structures
// ──────────────────────────────────────────────────────────────────────────────

typedef struct {
    uint8_t attack;
    uint8_t hold;
    uint8_t decay;
    uint8_t sustain;
    uint8_t release;
} emu3_envelope_t;

typedef struct {
    char     format[EMU3_BANK_NAME_LEN];
    char     name[EMU3_BANK_NAME_LEN];
    uint32_t objects;
    uint32_t padding[3];
    uint32_t next_preset;
    uint32_t next_sample;
    uint32_t unknown_0;
    uint32_t preset_blocks;
    uint32_t sample_blocks;
    uint32_t unknown_1;
    uint32_t total_blocks;
    char     name_copy[EMU3_BANK_NAME_LEN];
    uint32_t selected_preset;
    uint32_t parameters[3];
} emu3_bank_header_t;

typedef struct {
    char     name[EMU3_BANK_NAME_LEN];
    int8_t   rt_controls[12];
    int8_t   unknown_0[16];
    int8_t   pitch_bend_range;
    int8_t   vel_range_pri_low;
    int8_t   vel_range_pri_high;
    int8_t   vel_range_sec_low;
    int8_t   vel_range_sec_high;
    int8_t   link_preset_lsb;
    int8_t   link_preset_msb;
    int8_t   unknown_1[2];
    int8_t   note_zones;
    uint8_t  note_zone_mappings[EMU3_NOTES];
} emu3_preset_header_t;

typedef struct {
    char     name[EMU3_BANK_NAME_LEN];
    uint32_t header;
    uint32_t start_l;
    uint32_t start_r;
    uint32_t end_l;
    uint32_t end_r;
    uint32_t loop_start_l;
    uint32_t loop_start_r;
    uint32_t loop_end_l;
    uint32_t loop_end_r;
    uint32_t sample_rate;
    uint16_t playback_rate;
    uint16_t options;
    uint32_t data_offset_l;
    uint32_t data_offset_r;
    uint32_t parameters[6];
    // int16_t frames[] follows
} emu3_sample_header_t;

#pragma pack(pop)

// ──────────────────────────────────────────────────────────────────────────────
// Objective-C types
// ──────────────────────────────────────────────────────────────────────────────

typedef NS_ENUM(NSInteger, EMU3FileType) {
    EMU3FileTypeUnknown = 0,
    EMU3FileTypeBank,
    EMU3FileTypeSystem,
};

typedef NS_ENUM(NSInteger, EMU3BankFormat) {
    EMU3BankFormatUnknown = 0,
    EMU3BankFormatEmulatorThree,
    EMU3BankFormatEmulator3X,
    EMU3BankFormatESI32v3,
    EMU3BankFormatEmulatorIV,   // E4B0 IFF format (EIV / E-mu IV)
};

// Human readable size with the unit that fits: B, KB, MB or GB (1 KB = 1024 bytes, like the EOS block sizes).
static inline NSString *EMU3FormatBytes(unsigned long long b) {
    if (b < 1024ULL) return [NSString stringWithFormat:@"%llu B", b];
    if (b < 1024ULL * 1024) return [NSString stringWithFormat:@"%.1f KB", b / 1024.0];
    if (b < 1024ULL * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", b / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB", b / (1024.0 * 1024.0 * 1024.0)];
}
