#import "EDMemoryView.h"
#import "EDTheme.h"

@implementation EDMemoryView
- (NSSize)intrinsicContentSize { return NSMakeSize(420, 190); }
- (void)setResidentUsedK:(double)v { _residentUsedK = v; self.needsDisplay = YES; }
- (void)setPresetUsedK:(double)v { _presetUsedK = v; self.needsDisplay = YES; }
- (void)setSampleUsedMB:(double)v { _sampleUsedMB = v; self.needsDisplay = YES; }
- (void)setSampleTotalMB:(double)v { _sampleTotalMB = v; self.needsDisplay = YES; }

static void text(NSString *s, NSPoint p, CGFloat size, NSColor *c, BOOL right) {
    NSDictionary *a = @{NSFontAttributeName: [EDTheme lcdFont:size], NSForegroundColorAttributeName: c};
    NSSize sz = [s sizeWithAttributes:a]; [s drawAtPoint:NSMakePoint(right ? p.x - sz.width : p.x, p.y) withAttributes:a];
}
static NSString *kb(double k) { return k >= 1024 ? [NSString stringWithFormat:@"%.1fmb", k / 1024] : [NSString stringWithFormat:@"%.0fk", k]; }

- (void)drawRect:(NSRect)dirty {
    NSRect r = NSInsetRect(self.bounds, EDTheme.lcdFrameWidth / 2, EDTheme.lcdFrameWidth / 2);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6];
    [EDTheme.lcdBackground setFill]; [frame fill]; [NSColor.blackColor setStroke]; frame.lineWidth = EDTheme.lcdFrameWidth; [frame stroke];
    NSColor *ink = EDTheme.lcdInk; CGFloat top = NSMaxY(r), h = r.size.height;
    text(@"Memory", NSMakePoint(NSMinX(r) + 14, top - 36), 22, ink, NO);
    text(@"Total", NSMakePoint(NSMinX(r) + 190, top - 30), 12, ink, YES); text(@"Used", NSMakePoint(NSMinX(r) + 262, top - 30), 12, ink, YES);
    [[ink colorWithAlphaComponent:0.6] setFill]; NSRectFill(NSMakeRect(NSMinX(r) + 14, top - 42, r.size.width - 28, 1));
    double totals[3] = {_residentTotalK, _presetTotalK, _sampleTotalMB * 1024}, used[3] = {_residentUsedK, _presetUsedK, _sampleUsedMB * 1024};
    NSString *names[3] = {@"Resident", @"Preset", @"Sample"};
    for (int i = 0; i < 3; i++) {
        CGFloat y = top - 66 - i * (h - 80) / 3.0; double pct = totals[i] > 0 ? used[i] / totals[i] * 100 : 0; BOOL over = pct > 100;
        NSColor *c = over ? EDTheme.accent : ink;
        text(names[i], NSMakePoint(NSMinX(r) + 18, y), 14, c, NO);
        text(i == 2 ? [NSString stringWithFormat:@"%.0fmb", _sampleTotalMB] : kb(totals[i]), NSMakePoint(NSMinX(r) + 190, y), 14, c, YES);
        text(i == 2 ? [NSString stringWithFormat:@"%.1fmb", _sampleUsedMB] : kb(used[i]), NSMakePoint(NSMinX(r) + 262, y), 14, c, YES);
        text([NSString stringWithFormat:@"%.0f%%", pct], NSMakePoint(NSMinX(r) + 318, y), 14, c, YES);
        NSRect bar = NSMakeRect(NSMinX(r) + 326, y + 1, r.size.width - 326 - 18, 14);
        [c setStroke]; NSBezierPath *bp = [NSBezierPath bezierPathWithRect:bar]; bp.lineWidth = 1.5; [bp stroke];
        [c setFill]; NSRectFill(NSMakeRect(bar.origin.x + 1.5, bar.origin.y + 1.5, MAX(0, MIN(1, pct / 100)) * (bar.size.width - 3), bar.size.height - 3));
    }
}
@end
