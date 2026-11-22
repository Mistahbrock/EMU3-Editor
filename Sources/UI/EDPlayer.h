// EDPlayer — audition engine for a sample, with sustain-loop playback. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>
#import "EDBank.h"

@interface EDPlayer : NSObject
@property (nonatomic, readonly) BOOL playing;
/// Current frame in the sample's stored data, or -1 when stopped (polled by the UI).
@property (nonatomic, readonly) NSInteger currentFrame;
@property (nonatomic, copy) void (^onStop)(void);
- (void)playSample:(EDSample *)sample ratio:(double)ratio;   // ratio 1 = original pitch; 2 = an octave up (clamped to 1/16 … 8)
- (void)playSample:(EDSample *)sample;      // loops when the sample's loop flag is set
- (void)stop;
@end
