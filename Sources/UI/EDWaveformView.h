// EDWaveformView — zoomable waveform with draggable loop markers. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDBank.h"

NS_ASSUME_NONNULL_BEGIN

@interface EDWaveformView : NSView
@property (nonatomic, strong, nullable) EDSample *sample;
@property (nonatomic) NSUInteger visibleStart;     // first visible frame
@property (nonatomic) double framesPerPixel;       // zoom
@property (nonatomic) NSInteger playhead;          // -1 = hidden
/// Called while a loop marker is dragged (isLoopStart) and when the drag ends.
@property (nonatomic, copy, nullable) void (^loopChanged)(BOOL final);
- (void)zoomToFit;
- (void)zoomBy:(double)factor;                     // >1 zooms in
- (void)zoomToLoop;
@end

NS_ASSUME_NONNULL_END
