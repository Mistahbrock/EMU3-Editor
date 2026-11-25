// EDPreset+Params — data-driven access to preset parameters (E4P1 and Emulator 3X presets).
// E4P1 layout: 84-byte header, then per voice a 284-byte voice block followed by `sampleCount` 22-byte sample
// references (verified on 4,719 presets of a real disk). 3X layout: 142-byte header, 4 bytes per zone, 48 bytes per voice.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio. Field names follow the E4BTool field tables (AGPL-3.0, see CREDITS.md).
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EDParamType) { EDParamU8, EDParamS8, EDParamU16BE, EDParamS16BE };
typedef NS_ENUM(NSInteger, EDParamScope) { EDScopePreset, EDScopeVoice, EDScopeRef };

@interface EDParam : NSObject
@property (nonatomic, copy) NSString *group, *label;
@property (nonatomic) EDParamScope scope;
@property (nonatomic) NSUInteger offset;               // from the start of the preset / voice block / sample reference
@property (nonatomic) EDParamType type;
@property (nonatomic) NSInteger min, max;
@property (nonatomic) BOOL isNote;                     // value is a MIDI note number
@property (nonatomic) BOOL isSample;                   // value is a sample number
@property (nonatomic) BOOL readOnly;
@property (nonatomic, copy, nullable) NSDictionary<NSNumber *, NSString *> *names;   // value -> label
- (NSString *)displayForValue:(NSInteger)v;            // note names, enum names
+ (NSString *)noteName:(NSInteger)midi;
@end

@interface EDPreset (Params)
- (NSArray<EDParam *> *)paramsForScope:(EDParamScope)scope;
- (NSInteger)voiceCount;
- (NSInteger)refCountInVoice:(NSInteger)voice;         // sample references (0 for 3X presets, whose voices hold one sample)
- (NSInteger)valueOfParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r;
/// The value a new voice / zone / preset starts with (the template of "Voices > Utils > New"). NO when there is none (3X presets, sample numbers).
- (BOOL)getDefault:(NSInteger *)out ofParam:(EDParam *)p;
- (void)setValue:(NSInteger)value ofParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r;   // clamped to the param range
/// Structural edits (E4 presets only). Return NO when not possible.
- (BOOL)addRefToVoice:(NSInteger)v;
- (BOOL)removeRef:(NSInteger)r fromVoice:(NSInteger)v;
- (BOOL)duplicateVoice:(NSInteger)v;
/// Appends a new voice with one sample reference (the "Voices > Utils > New" function of the sampler's Preset Edit). The voice starts from a
/// default taken from a real preset, with full key and velocity range. NO when the preset is not an E4 preset or already has 255 voices.
- (BOOL)addVoiceWithSampleNumber:(NSInteger)sampleNumber;
/// Chunk data for an empty E4 preset (84-byte header, no voices), as created by Preset Manage > New.
+ (NSMutableData *)newE4PresetDataWithName:(NSString *)name number:(uint16_t)number;
- (BOOL)removeVoice:(NSInteger)v;
@property (nonatomic, readonly) BOOL canEditStructure;
/// YES when the raw bytes are exactly header + voices (used by the tests and before saving).
- (BOOL)validateStructure;
@end

NS_ASSUME_NONNULL_END
