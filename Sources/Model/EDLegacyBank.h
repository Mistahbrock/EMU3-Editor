// EDLegacyBank — Emulator 3X / ESI-32 v3 bank files ("EMULATOR 3X", "EMU SI-32 v3").
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
//
// Layout (verified on 90 banks of a sampler-formatted disk, see docs/STATUS.md):
//   0x000  header (0x4C bytes): format, name, object count, next_preset, next_sample, block counts …
//   0x17CA preset address table, 256 x u32, relative to 0x2B72; preset i spans addr[i] … addr[i+1] (equal = end)
//   0x1BD2 sample address table, 999 x u32, absolute sampler addresses starting at 0x400000
//   0x2B72 preset data; sample objects follow at file offset 0x4C + next_preset
//   file size = 0x4C + next_preset + next_sample
//   sample object: 0x5C-byte header (name, rate, loop/start/end words, flags at 0x3A) + 16-bit PCM
#import "EDBank.h"
NS_ASSUME_NONNULL_BEGIN
@interface EDLegacyBank : EDBank
+ (nullable instancetype)legacyBankWithData:(NSData *)data error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
