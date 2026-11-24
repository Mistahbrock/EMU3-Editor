// Small drawing views shared by the generator panels: a waveform / spectrum scope and the Hammond-style drawbars.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
/// One cycle of a waveform (values -1…1) or a harmonic spectrum (values 0…1), drawn on a dark scope.
@interface EDGenScope : NSView
@property (nonatomic) BOOL spectrum;                       // NO = waveform line, YES = harmonic bars
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@property (nonatomic, copy) NSString *caption;
@end

/// Nine drawbars, 0…8, with Hammond colours (brown, white, black). Drag a bar up or down.
@interface EDDrawbarView : NSView
@property (nonatomic, copy, nullable) void (^onChange)(void);
- (int)levelAt:(int)i;
- (void)setLevel:(int)v at:(int)i;
@end
/// A retro slider: a thin green line with a small tick for the handle, no chrome. Same target/action use as NSSlider.
@interface EDLineSlider : NSControl
@property (nonatomic) double minValue, maxValue, doubleValue;
+ (instancetype)sliderWithValue:(double)v minValue:(double)lo maxValue:(double)hi target:(id)t action:(SEL)a;
+ (NSColor *)lineGreen;
@end

/// A dark screen with a thin green frame; the generator draws its picture and sliders inside it.
@interface EDGenScreen : NSView
@end
NS_ASSUME_NONNULL_END
