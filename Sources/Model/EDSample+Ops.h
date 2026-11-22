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
- (double)peak;
@end
NS_ASSUME_NONNULL_END
