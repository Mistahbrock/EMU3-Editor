// EDSamplerRemote — read-only queries to an E4-family sampler over MIDI SysEx (EOS remote-editing protocol, draft #30):
// Identity Request, Sample / Preset Memory Request, Configuration Request. Nothing is written to the sampler.
// Finds the sampler by asking every MIDI port pair; the pair that answers is remembered (RemoteOut / RemoteIn).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface EDSamplerStatus : NSObject
@property (nonatomic, copy) NSString *model, *version, *outPort, *inPort;   // "E6400", "4.62"
@property (nonatomic) NSInteger deviceID, ramMB, sampleTotalMB, presetTotalK, presetFreeK, options;
@property (nonatomic) double sampleFreeK;                                    // kB
@property (nonatomic, readonly) BOOL hasFXCard, hasMIDICard, has128Voices;
@end
@interface EDSamplerRemote : NSObject
/// Runs on a background queue; `done` is called on the main queue with nil when no sampler answered.
+ (void)queryWithCompletion:(void (^)(EDSamplerStatus *_Nullable status))done;
/// The Multimode Map (73h → 72h): one entry per MIDI channel, @[preset, volume 0-127, pan -64...63, submix]. nil when the sampler does not answer.
+ (void)readMultimodeWithCompletion:(void (^)(NSArray<NSArray<NSNumber *> *> *_Nullable channels))done;
/// Sets one channel's multimode volume (channel 1-based, volume 0-127): MULTIMODE_CHANNEL + MULTIMODE_VOLUME in one Parameter Edit.
/// Quick successive calls for the same channel are merged; the last value always gets sent.
+ (void)setVolume:(NSInteger)volume forChannel:(NSInteger)channel;
/// Sets one channel's multimode pan (-64 left ... +63 right).
+ (void)setPan:(NSInteger)pan forChannel:(NSInteger)channel;
/// Sets one channel's multimode preset (-1 = none, 0...999).
+ (void)setPreset:(NSInteger)preset forChannel:(NSInteger)channel;
/// The sampler's name for a preset number (Preset Name Request, 06h → 05h); nil when it does not answer.
+ (void)presetNameForNumber:(NSInteger)number completion:(void (^)(NSString *_Nullable name))done;
@end
NS_ASSUME_NONNULL_END
