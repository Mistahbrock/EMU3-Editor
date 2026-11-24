// EDBank — in-memory model of an E-mu EOS bank file (IFF "FORM" E4B0) for the EMU3 Editor.
// Copyright (C) 2026 Rhyno Audio. Free software under the GNU GPL version 3 or later.
//
// Layout facts used here (all checked against sample/bank files, see docs/FORMAT-NOTES.md):
//   FORM <BE size> E4B0, then IFF chunks <4-char id><BE size><data>, each padded to an even length.
//   TOC1 lists the other chunks (32 bytes per record: type, size, position, number, 16-byte name).
//   E3S1 = sample chunk, E4P1 = preset chunk.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const EDErrorDomain;

typedef NS_OPTIONS(uint16_t, EDSampleFlags) {
    EDSampleFlagLoop         = 0x0001,
    EDSampleFlagLoopRelease  = 0x0008,
    EDSampleFlagStereo       = 0x0010,
    EDSampleFlagLeft         = 0x0020,
    EDSampleFlagRight        = 0x0040,
};

/// One E3S1 chunk. Frame indexes are positions in the stored (guard-padded) 16-bit data, 0 = first stored frame.
@interface EDSample : NSObject
@property (nonatomic, readonly) NSUInteger chunkIndex;       // index inside EDBank.chunks
@property (nonatomic) uint16_t number;                       // sample number shown on the sampler (1…999)
@property (nonatomic, copy)   NSString *name;                // max 16 characters
@property (nonatomic) uint32_t sampleRate;
@property (nonatomic) uint16_t flags;
@property (nonatomic, readonly) BOOL hasLeft;
@property (nonatomic, readonly) BOOL hasRight;
@property (nonatomic, readonly) BOOL isStereo;
@property (nonatomic, readonly) NSUInteger frameCount;       // stored frames per channel
@property (nonatomic) NSUInteger loopStart;                  // frame index
@property (nonatomic) NSUInteger loopEnd;                    // frame index (inclusive, like the sampler)
@property (nonatomic) BOOL loopEnabled;
@property (nonatomic) BOOL loopInRelease;
/// Channel data (little-endian int16 in memory as host int16). right is nil for mono.
@property (nonatomic, readonly, copy) NSData *left;
@property (nonatomic, readonly, copy, nullable) NSData *right;
@property (nonatomic, readonly) BOOL dirty;
/// YES when the sample's layout was not fully understood: it is shown but never edited, and saved back byte for byte.
@property (nonatomic) BOOL locked;

- (const int16_t *)leftFrames;
- (nullable const int16_t *)rightFrames;
/// Replaces the audio. Length may change; loop points are clamped. right may be nil (mono).
- (void)replaceLeft:(NSData *)left right:(nullable NSData *)right;
/// Exports a WAV (with a smpl chunk holding the loop when enabled).
- (BOOL)writeWAVToURL:(NSURL *)url error:(NSError **)error;
/// Replaces the audio with a WAV/AIFF/CAF file (via AudioToolbox), adding the 4-frame guard padding the sampler expects.
- (BOOL)replaceAudioFromURL:(NSURL *)url error:(NSError **)error;
@end

typedef NS_ENUM(NSInteger, EDPresetKind) { EDPresetKindE4 = 0, EDPresetKindLegacy3X };

/// One preset, kept as raw bytes; typed access to its parameters is in EDPreset+Params.h.
@interface EDPreset : NSObject
@property (nonatomic) EDPresetKind kind;
@property (nonatomic, readonly) NSUInteger chunkIndex;
@property (nonatomic) uint16_t number;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, readonly) NSMutableData *raw;          // chunk data, edited in place
@property (nonatomic, readonly) BOOL dirty;
@end

@interface EDChunk : NSObject
@property (nonatomic, copy) NSString *ident;                 // "TOC1", "E3S1", "E4P1", "EMS0", …
@property (nonatomic, strong) NSMutableData *data;           // payload without the 8-byte header
@end

@interface EDBank : NSObject
@property (nonatomic, readonly) NSString *formType;          // "E4B0" etc., or "3X" for Emulator 3X / ESI-32 banks
@property (nonatomic, readonly) NSArray<EDChunk *> *chunks;
@property (nonatomic, readonly) NSArray<EDSample *> *samples;
@property (nonatomic, readonly) NSArray<EDPreset *> *presets;
@property (nonatomic, readonly) BOOL dirty;

/// A new EOS bank file holding only this sample (TOC1 + E3S1), ready to load on the sampler. nil for samples that are not EOS E3S1 samples.
+ (nullable NSData *)singleSampleBankDataForSample:(EDSample *)sample;
/// E3S1 chunk data (starting with the 2-byte sample number) for a sample read from a 3X bank, given that sample's original 0x5C-byte header.
+ (nullable NSData *)e3s1ChunkDataForLegacySample:(EDSample *)sample header:(NSData *)header number:(uint16_t)number;
/// The bytes of a new, empty EOS bank (no samples, no presets), the starting point of File > New Bank.
+ (NSData *)emptyBankData;
+ (nullable instancetype)bankWithData:(NSData *)data error:(NSError **)error;
- (nullable NSData *)serializeWithError:(NSError **)error;
/// Call after the serialized data has been written somewhere: forgets the unsaved-changes state without reloading.
- (void)markClean;
/// Marks everything as changed (a bank restored from the unsaved-work session is still unsaved).
- (void)markAllDirty;
/// Adds an empty E4 preset (Preset Manage > New) with the lowest unused number, placed after the last preset in the file and listed in the
/// table of contents. nil for 3X banks.
- (nullable EDPreset *)addPresetNamed:(NSString *)name;
/// Removes a preset added in this session (used to undo addPresetNamed:). NO if it is not in the bank.
- (BOOL)removePreset:(EDPreset *)preset;
- (BOOL)removeSample:(EDSample *)sample;               // E4B banks; also drops its table-of-contents record
- (void)eraseAllPresetsAndSamples;
/// Removes any preset from an E4B bank (Preset Manage > Delete). Returns an opaque state for reattachPreset: (undo), or nil when not possible.
/// The samples the preset used are left alone, as on the sampler.
- (nullable NSDictionary *)detachPreset:(EDPreset *)preset;
/// A new EOS bank file holding this preset and the samples it uses (current, unsaved edits included), ready to load on the sampler.
/// `missing` receives sample numbers the preset uses that are not in this bank (ROM samples, or samples left out of the bank). nil for 3X banks.
- (nullable NSData *)bankDataForPreset:(EDPreset *)preset missingSamples:(NSArray<NSNumber *> *_Nullable *_Nullable)missing;
- (void)reattachPreset:(NSDictionary *)state;
/// Copies presets from another E4B bank into this one, with the samples they use. Copied samples take the lowest free sample numbers and the
/// copied presets' voices are re-pointed to them; samples the source does not hold (ROM samples) keep their number and are listed in `missing`.
/// Returns the new presets, or nil when either bank is not an E4B bank or no sample number is free.
- (nullable NSArray<EDPreset *> *)importPresets:(NSArray<EDPreset *> *)presets fromBank:(EDBank *)source samplesCopied:(nullable NSUInteger *)copied missingSamples:(NSArray<NSNumber *> *_Nullable *_Nullable)missing;
@end

NS_ASSUME_NONNULL_END
