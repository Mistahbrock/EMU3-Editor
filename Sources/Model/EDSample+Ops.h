// EDSample+Ops — destructive sample operations (normalize, reverse, fades, DC, crop, loop crossfade).
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDSample (Ops)
- (void)normalizeToPeak:(double)peak;                 // peak 0…1
- (void)applyGainDB:(double)db;
- (void)reverse;                                      // loop points are mirrored
- (void)fadeInFrames:(NSUInteger)n;
- (void)fadeOutFrames:(NSUInteger)n;
- (void)removeDC;
- (void)cropToFrom:(NSUInteger)from to:(NSUInteger)to; // inclusive frame range; keeps/clamps the loop
- (void)cropToLoop;
/// Blends the audio just before loopEnd with the audio just before loopStart so the loop joins smoothly.
- (void)crossfadeLoopFrames:(NSUInteger)n;
- (void)swapChannels;                                  // stereo only: left <-> right
- (void)convertToMono;                                 // stereo: (L+R)/2
- (void)convertToStereo;                               // mono: right = copy of left
/// Resamples to `rate` Hz (length and loop points follow; pitch stays the same when played at the new rate).
- (void)convertToSampleRate:(uint32_t)rate;
/// Digital tuning: shifts the pitch by `cents` by resampling (the length changes, the sample rate stays).
- (void)tuneByCents:(double)cents;
/// Reduces the resolution to `bits` (1…15), optionally with triangular dither. The data stays 16-bit.
- (void)reduceToBits:(int)bits dither:(BOOL)dither;
- (double)peak;
@end
NS_ASSUME_NONNULL_END
