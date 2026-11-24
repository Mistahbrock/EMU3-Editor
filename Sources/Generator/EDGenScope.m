#import "EDGenScope.h"
#import "EDTheme.h"

@implementation EDGenScope
- (instancetype)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { _values = @[]; _caption = @""; } return self; }
- (void)setValues:(NSArray<NSNumber *> *)v { _values = [v copy]; self.needsDisplay = YES; }
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds; [[NSColor colorWithWhite:0.07 alpha:1] setFill]; NSRectFill(b);
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; NSFrameRect(b);
    if (!_spectrum) { NSBezierPath *z = [NSBezierPath bezierPath]; [z moveToPoint:NSMakePoint(0, NSMidY(b))]; [z lineToPoint:NSMakePoint(NSMaxX(b), NSMidY(b))]; [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; [z stroke]; }
    NSUInteger n = _values.count;
    if (n > 1) {
        if (_spectrum) {
            [[NSColor colorWithSRGBRed:1 green:0.85 blue:0.25 alpha:0.9] setFill]; double bw = b.size.width / n;
            for (NSUInteger i = 0; i < n; i++) { double v = MAX(0, MIN(1, _values[i].doubleValue)), h = v * (b.size.height - 8); NSRectFill(NSMakeRect(i * bw, b.size.height - h, MAX(1, bw - 1), h)); }
        } else {
            NSBezierPath *p = [NSBezierPath bezierPath]; p.lineWidth = 1.4;
            for (NSUInteger i = 0; i < n; i++) { NSPoint pt = NSMakePoint(b.size.width * i / (n - 1), NSMidY(b) - _values[i].doubleValue * (b.size.height / 2 - 4)); if (i) [p lineToPoint:pt]; else [p moveToPoint:pt]; }
            [[NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.55 alpha:1] setStroke]; [p stroke];
        }
    }
    [_caption drawAtPoint:NSMakePoint(6, 3) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10], NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.55]}];
}
@end

@implementation EDDrawbarView { int _lv[9]; }
static NSString *const kFootNames[9] = {@"16′", @"5⅓′", @"8′", @"4′", @"2⅔′", @"2′", @"1⅗′", @"1⅓′", @"1′"};
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(9 * 46 + 2 * 14 + 40, 230); }
- (int)levelAt:(int)i { return _lv[i]; }
- (void)setLevel:(int)v at:(int)i { _lv[i] = MAX(0, MIN(8, v)); self.needsDisplay = YES; }
- (CGFloat)colX:(int)i { return 40 + i * 46 + (i >= 2 ? 14 : 0) + (i >= 6 ? 14 : 0) + 23; }   // gaps between the groups 16′ 5⅓′ | 8′–2′ | 1⅗′–1′
static const CGFloat kTop = 34, kTravel = 150;
- (NSColor *)capColor:(int)i { return (i < 2) ? [NSColor colorWithSRGBRed:0.45 green:0.26 blue:0.10 alpha:1] : ((i == 4 || i == 6 || i == 7) ? [NSColor colorWithWhite:0.1 alpha:1] : [NSColor colorWithWhite:0.93 alpha:1]); }
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds; [[NSColor colorWithWhite:0.13 alpha:1] setFill]; NSRectFill(b);
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; NSFrameRect(b);
    NSDictionary *num = @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular], NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:0.5]};
    for (int s = 0; s <= 8; s++) {   // scale numbers on the left, one tick row across the bars
        CGFloat y = kTop + kTravel * s / 8.0; NSString *t = [NSString stringWithFormat:@"%d", s]; NSSize sz = [t sizeWithAttributes:num];
        [t drawAtPoint:NSMakePoint(24 - sz.width, y - sz.height / 2) withAttributes:num];
        [[NSColor colorWithWhite:1 alpha:0.08] setFill]; NSRectFill(NSMakeRect(30, y, b.size.width - 38, 1));
    }
    for (int i = 0; i < 9; i++) {
        CGFloat x = [self colX:i], y = kTop + kTravel * _lv[i] / 8.0;
        [[NSColor colorWithWhite:0.04 alpha:1] setFill]; NSRectFill(NSMakeRect(x - 4, kTop - 6, 8, kTravel + 12));         // slot
        [[NSColor colorWithWhite:0.55 alpha:1] setFill]; NSRectFill(NSMakeRect(x - 3, kTop - 6, 6, y - kTop + 6));         // the rod, pulled out of the slot
        NSRect cap = NSMakeRect(x - 15, y, 30, 22);
        [[self capColor:i] setFill]; NSRectFill(cap); [[NSColor colorWithWhite:0 alpha:0.5] setStroke]; NSFrameRect(cap);
        BOOL dark = (i < 2) || (i == 4 || i == 6 || i == 7);
        NSString *t = [NSString stringWithFormat:@"%d", _lv[i]]; NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:12], NSForegroundColorAttributeName: dark ? NSColor.whiteColor : NSColor.blackColor};
        NSSize sz = [t sizeWithAttributes:a]; [t drawAtPoint:NSMakePoint(x - sz.width / 2, y + 11 - sz.height / 2) withAttributes:a];
        NSDictionary *fa = @{NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: EDTheme.labelWhite};
        NSSize fs = [kFootNames[i] sizeWithAttributes:fa]; [kFootNames[i] drawAtPoint:NSMakePoint(x - fs.width / 2, b.size.height - 24) withAttributes:fa];
    }
}
- (void)setFromEvent:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; int best = 0; CGFloat bd = 1e9;
    for (int i = 0; i < 9; i++) { CGFloat d = fabs(p.x - [self colX:i]); if (d < bd) { bd = d; best = i; } }
    if (bd > 24) return;
    int v = (int)llround((p.y - 11 - kTop) / kTravel * 8.0);
    if (v != _lv[best]) { [self setLevel:v at:best]; if (_onChange) _onChange(); }
}
- (void)mouseDown:(NSEvent *)e { [self setFromEvent:e]; }
- (void)mouseDragged:(NSEvent *)e { [self setFromEvent:e]; }
@end

@implementation EDLineSlider
@synthesize doubleValue = _doubleValue;
+ (NSColor *)lineGreen { return [NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.55 alpha:1]; }
+ (instancetype)sliderWithValue:(double)v minValue:(double)lo maxValue:(double)hi target:(id)t action:(SEL)a {
    EDLineSlider *s = [EDLineSlider new]; s.minValue = lo; s.maxValue = hi; s.doubleValue = v; s.target = t; s.action = a; return s;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 16); }
- (void)setDoubleValue:(double)v { _doubleValue = MAX(_minValue, MIN(_maxValue, v)); self.needsDisplay = YES; }
- (void)drawRect:(NSRect)r {
    NSRect b = self.bounds; double t = _maxValue > _minValue ? (_doubleValue - _minValue) / (_maxValue - _minValue) : 0, x = 4 + t * (b.size.width - 8), y = floor(b.size.height / 2) + 0.5;
    NSColor *g = EDLineSlider.lineGreen;
    [[g colorWithAlphaComponent:0.35] setFill]; NSRectFill(NSMakeRect(4, y - 0.5, b.size.width - 8, 1));
    [g setFill]; NSRectFill(NSMakeRect(4, y - 0.5, x - 4, 1));                       // the part up to the handle is brighter
    NSRectFill(NSMakeRect(x - 1, 2, 2, b.size.height - 4));                          // handle: a thin vertical tick
}
- (void)track:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; double t = MAX(0, MIN(1, (p.x - 4) / MAX(1, self.bounds.size.width - 8)));
    self.doubleValue = _minValue + t * (_maxValue - _minValue); [self sendAction:self.action to:self.target];
}
- (void)mouseDown:(NSEvent *)e { [self track:e]; }
- (void)mouseDragged:(NSEvent *)e { [self track:e]; }
@end

@implementation EDGenScreen
- (instancetype)initWithFrame:(NSRect)f { if ((self = [super initWithFrame:f])) { self.wantsLayer = YES; self.layer.backgroundColor = [NSColor colorWithWhite:0.05 alpha:1].CGColor; self.layer.borderWidth = 1; self.layer.borderColor = [[EDLineSlider.lineGreen colorWithAlphaComponent:0.55] CGColor]; } return self; }
@end
