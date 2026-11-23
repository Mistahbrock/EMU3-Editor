// EDBankConverter — turns an Emulator 3X / ESI-32 bank into an EOS (E4B) bank for the E64 / E6400 family.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
//
// Samples are converted exactly: the 3X sample header is the E3S1 header with the number in front, so the name, rate, loop,
// flags and the undecoded header bytes travel along. Presets are rebuilt: each 3X zone voice (primary and secondary) becomes
// an E4 voice with its sample, the key window taken from the key map and the velocity window from the preset header.
// What 3X voices hold beyond that (tuning, envelopes, filter) is not decoded yet, so E4 voices start from the default voice.
#import "EDBank.h"
NS_ASSUME_NONNULL_BEGIN
@interface EDBankConverter : NSObject
/// A complete E4B file for a 3X bank, or nil with an error. `warnings` lists what could not be carried over.
+ (nullable NSData *)e4bDataFromLegacyBank:(EDBank *)bank warnings:(NSArray<NSString *> *_Nullable *_Nullable)warnings error:(NSError **)error;
/// Same for just these presets of the bank, with only the samples they use (a bank holding one preset and its samples).
+ (nullable NSData *)e4bDataFromLegacyBank:(EDBank *)bank presets:(nullable NSArray<EDPreset *> *)only warnings:(NSArray<NSString *> *_Nullable *_Nullable)warnings error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
