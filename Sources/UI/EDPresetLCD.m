#import "EDPresetLCD.h"
#import "EDTheme.h"

// A row is @[label, group, @[param labels]]; a page is {menu, soft, title, rows, heads?}. Rows whose parameters do not exist
// for the preset (3X presets have far fewer) are left out, and pages without any row are hidden.
static NSArray *R(NSString *label, NSString *group, NSArray *labels) { return @[label, group, labels]; }
static NSArray *singles(NSString *group, NSArray *labels) { NSMutableArray *a = [NSMutableArray array]; for (NSString *l in labels) [a addObject:R(l, group, @[l])]; return a; }
static NSArray *envRows(NSString *group) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *s in @[@"Attack 1", @"Attack 2", @"Decay 1", @"Decay 2", @"Release 1", @"Release 2"])
        [a addObject:R(s, group, @[[s stringByAppendingString:@" rate"], [s stringByAppendingString:@" level"]])];
    return a;
}
static NSArray *windowRows(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *w in @[@"Key", @"Velocity", @"Realtime"]) [a addObject:R(w, @"Windows", (@[[w stringByAppendingString:@" low"], [w stringByAppendingString:@" fade low"], [w stringByAppendingString:@" fade high"], [w stringByAppendingString:@" high"]]))];
    return a;
}
static NSArray *cordRows(int from, int to) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = from; i <= to; i++) [a addObject:R([NSString stringWithFormat:@"Cord %d", i], [NSString stringWithFormat:@"Cord %d", i], @[@"Source", @"Destination", @"Amount %"])];
    return a;
}
static NSArray<NSDictionary *> *pages(void) {
    static NSArray *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *wh = @[@"Low", @"Fade lo", @"Fade hi", @"High"], *eh = @[@"Rate", @"Level"];
        p = @[
            @{@"menu": @"Global", @"soft": @"Global", @"title": @"Preset Global", @"rows": [[singles(@"Preset", @[@"Transpose", @"Volume dB", @"Pitch bend range", @"Link preset (LSB)", @"Link preset (MSB)"]) arrayByAddingObjectsFromArray:singles(@"MIDI", @[@"MIDI A", @"MIDI B", @"MIDI C", @"MIDI D"])] arrayByAddingObjectsFromArray:@[]]},
            @{@"menu": @"Global", @"soft": @"Velocity", @"title": @"Preset Velocity (3X)", @"rows": singles(@"Preset", @[@"Primary velocity low", @"Primary velocity high", @"Secondary velocity low", @"Secondary velocity high"])},
            @{@"menu": @"Global", @"soft": @"Controls", @"title": @"Realtime Controls", @"rows": singles(@"Realtime controls", (@[@"Control 1", @"Control 2", @"Control 3", @"Control 4", @"Control 5", @"Control 6", @"Control 7", @"Control 8", @"Control 9", @"Control 10", @"Control 11", @"Control 12"]))},
            @{@"menu": @"Global", @"soft": @"Effect A", @"title": @"Effect A", @"rows": singles(@"Effect A", @[@"Effect", @"Parameter 1", @"Parameter 2", @"Parameter 3", @"Main send", @"Sub 1 send", @"Sub 2 send", @"Sub 3 send"])},
            @{@"menu": @"Global", @"soft": @"Effect B", @"title": @"Effect B", @"rows": singles(@"Effect B", @[@"Effect", @"Parameter 1", @"Parameter 2", @"Parameter 3", @"Main send", @"Sub 1 send", @"Sub 2 send", @"Sub 3 send"])},

            @{@"menu": @"Voice", @"soft": @"Voice", @"title": @"Voice", @"rows": [singles(@"Voice", @[@"Group", @"Assign group", @"Delay", @"Start offset", @"Sample count", @"Sample number"]) arrayByAddingObjectsFromArray:singles(@"Tuning", @[@"Transpose", @"Coarse tune", @"Fine tune", @"Non-transpose"])]},
            @{@"menu": @"Voice", @"soft": @"Windows", @"title": @"Voice Windows", @"heads": wh, @"rows": windowRows()},
            @{@"menu": @"Voice", @"soft": @"Glide", @"title": @"Glide and Chorus", @"rows": [singles(@"Glide", @[@"Glide rate", @"Glide curve", @"Solo mode"]) arrayByAddingObjectsFromArray:singles(@"Chorus", @[@"Stereo width", @"Amount %", @"ITD"])]},
            @{@"menu": @"Voice", @"soft": @"Output", @"title": @"Voice Output", @"rows": singles(@"Output", @[@"Volume dB", @"Pan", @"Sub mix", @"Amp envelope depth"])},
            @{@"menu": @"Voice", @"soft": @"Filter", @"title": @"Filter", @"rows": singles(@"Filter", @[@"Filter type", @"Frequency", @"Resonance", @"Parameter 3", @"Parameter 4", @"Parameter 5", @"Parameter 6", @"Parameter 7", @"Parameter 8"])},
            @{@"menu": @"Voice", @"soft": @"Vol Env", @"title": @"Volume Envelope", @"heads": eh, @"rows": envRows(@"Volume envelope")},
            @{@"menu": @"Voice", @"soft": @"Filt Env", @"title": @"Filter Envelope", @"heads": eh, @"rows": envRows(@"Filter envelope")},
            @{@"menu": @"Voice", @"soft": @"Aux Env", @"title": @"Auxiliary Envelope", @"heads": eh, @"rows": envRows(@"Aux envelope")},
            @{@"menu": @"Voice", @"soft": @"LFO", @"title": @"LFOs and Lag", @"heads": @[@"Rate", @"Shape", @"Delay", @"Var %", @"Sync"], @"rows": @[R(@"LFO 1", @"LFO 1", @[@"Rate", @"Shape", @"Delay", @"Variation %", @"Key sync"]), R(@"LFO 2", @"LFO 2", @[@"Rate", @"Shape", @"Delay", @"Variation %", @"Key sync"]), R(@"Lag", @"Lag", @[@"Lag 0", @"Lag 1"])]},
            @{@"menu": @"Voice", @"soft": @"Cords 1", @"title": @"Cords 1-8", @"heads": @[@"Source", @"Dest", @"Amount %"], @"rows": cordRows(1, 8)},
            @{@"menu": @"Voice", @"soft": @"Cords 2", @"title": @"Cords 9-16", @"heads": @[@"Source", @"Dest", @"Amount %"], @"rows": cordRows(9, 16)},
            @{@"menu": @"Voice", @"soft": @"Cords 3", @"title": @"Cords 17-24", @"heads": @[@"Source", @"Dest", @"Amount %"], @"rows": cordRows(17, 24)},

            @{@"menu": @"Zone", @"soft": @"Sample", @"title": @"Zone Sample", @"rows": singles(@"Sample", @[@"Sample number", @"Root key", @"Fine tune", @"Volume dB", @"Pan"])},
            @{@"menu": @"Zone", @"soft": @"Windows", @"title": @"Zone Windows", @"heads": wh, @"rows": [windowRows() subarrayWithRange:NSMakeRange(0, 2)]},
        ];
    });
    return p;
}
static EDParam *find(NSArray<EDParam *> *ps, NSString *group, NSString *label) {
    for (EDParam *p in ps) if ([p.group isEqualToString:group] && [p.label isEqualToString:label]) return p;
    return nil;
}
static NSInteger parseNoteOrInt(NSString *s, EDParam *p) {
    NSString *t = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (p.isNote && t.length >= 2 && [[NSCharacterSet letterCharacterSet] characterIsMember:[t characterAtIndex:0]])
        for (int n = 0; n < 128; n++) if ([[EDParam noteName:n] caseInsensitiveCompare:t] == NSOrderedSame) return n;
    return t.integerValue;
}


// Small graph of a six-stage envelope: a line through seven points with square drag handles. Horizontal position of a handle is
// its stage's rate (further right = slower), vertical position is its level.
@interface EDEnvGraph : NSView
@property (nonatomic) BOOL scaled;     // zoom the stages to fill the frame (Scaled) instead of a fixed time axis (Fixed)
@property (nonatomic) BOOL unipolar;   // envelope graphs: handles stop at the zero line
@property (nonatomic, strong) NSArray<EDParam *> *params;   // 12: rate, level per stage
@property (nonatomic, copy) NSInteger (^get)(EDParam *);
@property (nonatomic, copy) void (^set)(EDParam *, NSInteger);
@end
@implementation EDEnvGraph { NSInteger _drag, _sel; CGFloat _dragScale; }   // _sel: clicked handle stays bold until you click elsewhere
static inline CGFloat minWidth(NSInteger stage) { return stage ? 8 : 0; }
static const CGFloat kSeg = 62, kMin = 8, kPad = 14;   // every stage after the first keeps a minimum width so the handles stay apart; Attack 1 may sit on the left edge (rate 0)
- (BOOL)isFlipped { return YES; }
- (CGFloat)zeroY { CGFloat h = self.bounds.size.height - 2 * kPad; return kPad + h / 2; }   // same layout for all envelopes; volume just cannot go below zero
- (CGFloat)pxPerLevel { CGFloat h = self.bounds.size.height - 2 * kPad; return h / 2 / 127.0; }
// EOS rates: 0 is instant, 127 is slowest. In the time-scaled display a stage also takes longer the further its level has to travel.
- (CGFloat)levelFactor:(NSInteger)i level:(NSInteger)lvl {
    if (!_scaled) return 1;
    NSInteger prev = i ? _get(_params[i * 2 - 1]) : 0;
    return 0.25 + 0.75 * MIN(127, labs(lvl - prev)) / 127.0;
}
- (CGFloat)rawWidth:(NSInteger)i { return minWidth(i) + kSeg * _get(_params[i * 2]) / 127.0 * [self levelFactor:i level:_get(_params[i * 2 + 1])]; }
- (CGFloat)timeScale {
    if (!_scaled) return 1;
    CGFloat t = 0; for (int i = 0; i < 6; i++) t += [self rawWidth:i];
    return t > 0.01 ? (self.bounds.size.width - 2 * kPad) / t : 1;
}
- (NSArray<NSValue *> *)points {
    NSMutableArray *a = [NSMutableArray array]; CGFloat x = kPad, sc = [self timeScale];
    [a addObject:[NSValue valueWithPoint:NSMakePoint(x, [self zeroY])]];
    for (int i = 0; i < 6; i++) {
        NSInteger lvl = _get(_params[i * 2 + 1]);
        x += [self rawWidth:i] * sc;
        [a addObject:[NSValue valueWithPoint:NSMakePoint(x, [self zeroY] - MAX(_unipolar ? 0 : -127, lvl) * [self pxPerLevel])]];
    }
    return a;
}
- (void)drawRect:(NSRect)r {
    if (_params.count != 12) return;
    NSColor *ink = EDTheme.lcdInk;
    [[ink colorWithAlphaComponent:0.20] setFill]; NSRectFillUsingOperation(NSInsetRect(self.bounds, 1, 1), NSCompositingOperationSourceOver);   // darker plot, like the window graph
    NSBezierPath *frame = [NSBezierPath bezierPathWithRect:NSInsetRect(self.bounds, 1, 1)]; frame.lineWidth = 2; [ink setStroke]; [frame stroke];
    [[ink colorWithAlphaComponent:0.35] setStroke];
    NSBezierPath *zero = [NSBezierPath bezierPath]; [zero moveToPoint:NSMakePoint(kPad, [self zeroY])]; [zero lineToPoint:NSMakePoint(self.bounds.size.width - kPad, [self zeroY])];
    zero.lineWidth = 1; CGFloat dash[2] = {3, 3}; [zero setLineDash:dash count:2 phase:0]; [zero stroke];
    NSArray<NSValue *> *pts = [self points];
    NSBezierPath *ticks = [NSBezierPath bezierPath]; ticks.lineWidth = 1; [ticks setLineDash:dash count:2 phase:0];   // stage boundaries
    for (NSInteger i = 1; i < 7; i++) { NSPoint pt = pts[i].pointValue; [ticks moveToPoint:NSMakePoint(pt.x, kPad)]; [ticks lineToPoint:NSMakePoint(pt.x, self.bounds.size.height - kPad)]; }
    [[ink colorWithAlphaComponent:0.35] setStroke]; [ticks stroke];
    NSBezierPath *line = [NSBezierPath bezierPath]; line.lineWidth = 2; line.lineJoinStyle = NSLineJoinStyleRound;
    for (NSInteger i = 0; i < 7; i++) { NSPoint pt = pts[i].pointValue; i ? [line lineToPoint:pt] : [line moveToPoint:pt]; }
    [ink setStroke]; [line stroke];
    for (NSInteger i = 1; i < 7; i++) {
        NSPoint pt = pts[i].pointValue; NSRect b = NSMakeRect(pt.x - 4, pt.y - 4, 8, 8);
        BOOL on = i == _sel; (on ? ink : EDTheme.lcdBackground).setFill; NSRectFill(b); [ink setStroke]; NSBezierPath *bp = [NSBezierPath bezierPathWithRect:b]; bp.lineWidth = on ? 3 : 1.5; [bp stroke];
    }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint m = [self convertPoint:e.locationInWindow fromView:nil]; _drag = 0; CGFloat best = 12;
    NSArray<NSValue *> *pts = [self points];
    for (NSInteger i = 1; i < 7; i++) { NSPoint p = pts[i].pointValue; CGFloat d = hypot(p.x - m.x, p.y - m.y); if (d < best) { best = d; _drag = i; } }
    if (_drag) {   // handles of instant stages sit on top of each other: take the last one, and each further click on the spot moves on to the one beneath
        NSPoint at = pts[_drag].pointValue; NSMutableArray<NSNumber *> *pile = [NSMutableArray array];
        for (NSInteger i = 6; i >= 1; i--) { NSPoint p = pts[i].pointValue; if (hypot(p.x - at.x, p.y - at.y) < 2) [pile addObject:@(i)]; }
        NSUInteger k = [pile indexOfObject:@(_sel)];
        _drag = pile.count > 1 && k != NSNotFound ? pile[(k + 1) % pile.count].integerValue : pile.firstObject.integerValue;
    }
    _sel = _drag; self.needsDisplay = YES;
    _dragScale = [self timeScale]; if (_drag) [self mouseDragged:e];
}
- (void)mouseDragged:(NSEvent *)e {
    if (!_drag) return;
    NSPoint m = [self convertPoint:e.locationInWindow fromView:nil];
    NSArray<NSValue *> *pts = [self points]; CGFloat prevX = pts[_drag - 1].pointValue.x;
    NSInteger lvl = (NSInteger)llround(([self zeroY] - m.y) / [self pxPerLevel]);
    lvl = MAX(_unipolar ? 0 : -127, MIN(127, lvl));
    NSInteger rate = (NSInteger)llround(((m.x - prevX) / _dragScale - minWidth(_drag - 1)) / kSeg * 127 / [self levelFactor:_drag - 1 level:lvl]);
    EDParam *rp = _params[(_drag - 1) * 2], *lp = _params[(_drag - 1) * 2 + 1];
    rate = MAX(rp.min, MIN(rp.max, rate)); lvl = MAX(_unipolar ? 0 : lp.min, MIN(lp.max, lvl));
    if (rate != _get(rp)) _set(rp, rate);
    if (lvl != _get(lp)) _set(lp, lvl);
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)e { _drag = 0; self.needsDisplay = YES; }
@end

// Key × velocity picture of a window page. Keys run left to right, velocity bottom to top. The outer rectangle is the whole window
// (low…high), the darker inner one is where the zone plays at full level (fade lo…fade hi); between them it fades in and out.
// Eight handles sit in two rulers: squares (low, high) and diamonds (fade lo, fade hi), along the bottom for keys, at the left for velocity.
@interface EDWindowGraph : NSView
@property (nonatomic, strong) NSArray<EDParam *> *params;   // 8: key low, fade lo, fade hi, high, then the same for velocity
@property (nonatomic, copy) NSInteger (^get)(EDParam *);
@property (nonatomic, copy) void (^set)(EDParam *, NSInteger);
@end
@implementation EDWindowGraph { NSInteger _drag, _sel; }   // handle + 1; _sel stays after the click until you click elsewhere
static const CGFloat kWL = 50, kWB = 50, kWT = 10, kWR = 14;
- (BOOL)isFlipped { return YES; }
- (NSRect)plot { return NSMakeRect(kWL, kWT, self.bounds.size.width - kWL - kWR, self.bounds.size.height - kWT - kWB); }
- (CGFloat)xOf:(NSInteger)k { NSRect P = [self plot]; return P.origin.x + k / 127.0 * P.size.width; }
- (CGFloat)yOf:(NSInteger)v { NSRect P = [self plot]; return NSMaxY(P) - v / 127.0 * P.size.height; }
- (NSPoint)handle:(NSInteger)h {   // 0…3 key low, fade lo, fade hi, high; 4…7 velocity
    NSRect P = [self plot]; NSInteger i = h % 4, v = _get(_params[h]); BOOL outer = i == 0 || i == 3;
    return h < 4 ? NSMakePoint([self xOf:v], NSMaxY(P) + (outer ? 14 : 34)) : NSMakePoint(P.origin.x - (outer ? 14 : 34), [self yOf:v]);
}
- (NSInteger)value:(NSInteger)h {
    NSRect P = [self plot]; NSPoint m = [self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    CGFloat t = h < 4 ? (m.x - P.origin.x) / P.size.width : (NSMaxY(P) - m.y) / P.size.height;
    return MAX(0, MIN(127, (NSInteger)llround(t * 127)));
}
- (void)drawRect:(NSRect)r {
    if (_params.count != 8) return;
    NSColor *ink = EDTheme.lcdInk; NSRect P = [self plot];
    NSInteger k[4], v[4]; for (int i = 0; i < 4; i++) { k[i] = _get(_params[i]); v[i] = _get(_params[4 + i]); }
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:10], NSForegroundColorAttributeName: [ink colorWithAlphaComponent:0.75]};
    CGFloat dash[2] = {3, 3};
    [[ink colorWithAlphaComponent:0.25] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath]; grid.lineWidth = 1; [grid setLineDash:dash count:2 phase:0];
    for (int o = 0; o <= 10; o++) { CGFloat x = [self xOf:MIN(127, o * 12)]; [grid moveToPoint:NSMakePoint(x, P.origin.y)]; [grid lineToPoint:NSMakePoint(x, NSMaxY(P))]; }
    for (int q = 0; q <= 4; q++) { CGFloat y = [self yOf:MIN(127, q * 32)]; [grid moveToPoint:NSMakePoint(P.origin.x, y)]; [grid lineToPoint:NSMakePoint(NSMaxX(P), y)]; }
    [grid stroke];
    for (int o = 0; o <= 10; o += 2) { NSString *t = [EDParam noteName:o * 12]; [t drawAtPoint:NSMakePoint([self xOf:o * 12] - 8, NSMaxY(P) + 3) withAttributes:at]; }   // tiny labels sit above the squares' row
    for (int q = 0; q <= 4; q++) { NSString *t = [NSString stringWithFormat:@"%d", MIN(127, q * 32)]; NSSize sz = [t sizeWithAttributes:at]; [t drawAtPoint:NSMakePoint(P.origin.x - sz.width - 3, [self yOf:MIN(127, q * 32)] - sz.height / 2 - (q == 0 ? 4 : 0)) withAttributes:at]; }
    NSRect outer = NSMakeRect([self xOf:k[0]], [self yOf:v[3]], [self xOf:k[3]] - [self xOf:k[0]], [self yOf:v[0]] - [self yOf:v[3]]);
    NSRect inner = NSMakeRect([self xOf:k[1]], [self yOf:v[2]], [self xOf:k[2]] - [self xOf:k[1]], [self yOf:v[1]] - [self yOf:v[2]]);
    [[ink colorWithAlphaComponent:0.20] setFill]; NSRectFillUsingOperation(outer, NSCompositingOperationSourceOver);
    [[ink colorWithAlphaComponent:0.45] setFill]; NSRectFillUsingOperation(inner, NSCompositingOperationSourceOver);
    [ink setStroke]; NSBezierPath *ob = [NSBezierPath bezierPathWithRect:outer]; ob.lineWidth = 2; [ob stroke];
    NSBezierPath *ib = [NSBezierPath bezierPathWithRect:inner]; ib.lineWidth = 1; [ib stroke];
    NSBezierPath *fr = [NSBezierPath bezierPathWithRect:P]; fr.lineWidth = 1.5; [ink setStroke]; [fr stroke];
    for (NSInteger h = 0; h < 8; h++) {   // guide lines from every handle into the plot, then the handles
        NSPoint pt = [self handle:h]; NSBezierPath *g = [NSBezierPath bezierPath]; g.lineWidth = 1; [g setLineDash:dash count:2 phase:0];
        if (h < 4) { [g moveToPoint:NSMakePoint(pt.x, P.origin.y)]; [g lineToPoint:NSMakePoint(pt.x, pt.y)]; } else { [g moveToPoint:NSMakePoint(NSMaxX(P), pt.y)]; [g lineToPoint:NSMakePoint(pt.x, pt.y)]; }
        [[ink colorWithAlphaComponent:0.45] setStroke]; [g stroke];
    }
    for (NSInteger h = 0; h < 8; h++) {
        NSPoint pt = [self handle:h]; NSInteger i = h % 4; BOOL sq = i == 0 || i == 3;
        NSBezierPath *b = sq ? [NSBezierPath bezierPathWithRect:NSMakeRect(pt.x - 5, pt.y - 5, 10, 10)] : [NSBezierPath bezierPath];
        if (!sq) { [b moveToPoint:NSMakePoint(pt.x, pt.y - 6)]; [b lineToPoint:NSMakePoint(pt.x + 6, pt.y)]; [b lineToPoint:NSMakePoint(pt.x, pt.y + 6)]; [b lineToPoint:NSMakePoint(pt.x - 6, pt.y)]; [b closePath]; }
        BOOL on = h == _sel - 1; (on ? ink : EDTheme.lcdBackground).setFill; [b fill]; [ink setStroke]; b.lineWidth = on ? 3 : 1.5; [b stroke];
    }
    if (_sel) {   // value of the selected handle
        NSInteger h = _sel - 1; NSPoint pt = [self handle:h]; NSInteger val = _get(_params[h]);
        NSString *t = h < 4 ? [EDParam noteName:val] : [NSString stringWithFormat:@"%ld", (long)val];
        NSMutableDictionary *bold = [@{NSFontAttributeName: [EDTheme lcdFont:12], NSForegroundColorAttributeName: ink} mutableCopy];
        NSSize sz = [t sizeWithAttributes:bold]; NSPoint o = h < 4 ? NSMakePoint(pt.x - sz.width / 2, pt.y - 24 - (h % 4 == 0 || h % 4 == 3 ? 0 : 0)) : NSMakePoint(pt.x + 10, pt.y - sz.height / 2);
        if (h < 4) o.y = P.origin.y + 2;
        [t drawAtPoint:o withAttributes:bold];
    }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint m = [self convertPoint:e.locationInWindow fromView:nil]; _drag = 0; CGFloat best = 14;
    for (NSInteger h = 0; h < 8; h++) { NSPoint p = [self handle:h]; CGFloat d = hypot(p.x - m.x, p.y - m.y); if (d < best) { best = d; _drag = h + 1; } }
    _sel = _drag; if (_drag) [self mouseDragged:e]; self.needsDisplay = YES;   // a click on empty space deselects
}
- (void)mouseDragged:(NSEvent *)e {
    if (!_drag) return;
    NSInteger h = _drag - 1, g = h / 4 * 4, i = h % 4, val = [self value:h], a[4];
    for (int j = 0; j < 4; j++) a[j] = _get(_params[g + j]);
    a[i] = val;   // keep low ≤ fade lo ≤ fade hi ≤ high: the outer edges push the fades, the fades stop at their neighbours
    if (i == 0) { a[1] = MAX(a[1], val); a[2] = MAX(a[2], a[1]); a[3] = MAX(a[3], a[2]); }
    else if (i == 1) a[1] = MAX(a[0], MIN(a[2], val));
    else if (i == 2) a[2] = MAX(a[1], MIN(a[3], val));
    else { a[2] = MIN(a[2], val); a[1] = MIN(a[1], a[2]); a[0] = MIN(a[0], a[1]); }
    NSInteger old[4]; for (int j = 0; j < 4; j++) old[j] = _get(_params[g + j]);
    for (int j = 0; j < 4; j++) if (a[j] != old[j]) _set(_params[g + j], a[j]);
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent *)e { _drag = 0; self.needsDisplay = YES; }
@end

// Waveform preview of one LFO shape, drawn like the sampler's small LFO graph (one cycle, zero line, frame).
// LFO rate byte 0…127 → Hz, panel-read on an E4XT (lentferj/eosed, e4xt_lfo_rate_table.json); the E6400 should match but is unchecked.
static const float kLFOHz[128] = {
    0.08, 0.11, 0.15, 0.17, 0.21, 0.25, 0.28, 0.32, 0.36, 0.38, 0.42, 0.48, 0.50, 0.53, 0.56, 0.65,
    0.69, 0.72, 0.76, 0.80, 0.84, 0.92, 0.95, 0.99, 1.03, 1.11, 1.13, 1.22, 1.26, 1.30, 1.37, 1.41,
    1.49, 1.56, 1.60, 1.68, 1.72, 1.79, 1.87, 1.95, 1.98, 2.06, 2.14, 2.21, 2.29, 2.37, 2.44, 2.52,
    2.59, 2.67, 2.75, 2.82, 2.98, 3.05, 3.13, 3.20, 3.28, 3.43, 3.51, 3.59, 3.74, 3.81, 3.89, 4.04,
    4.12, 4.26, 4.34, 4.50, 4.58, 4.73, 4.88, 4.96, 5.11, 5.26, 5.34, 5.49, 5.65, 5.80, 5.95, 6.10,
    6.26, 6.41, 6.56, 6.71, 6.87, 7.02, 7.17, 7.32, 7.63, 7.78, 7.93, 8.09, 8.39, 8.53, 8.69, 8.85,
    9.16, 9.31, 9.61, 9.77, 10.07, 10.22, 10.53, 10.68, 10.99, 11.14, 11.44, 11.75, 12.05, 12.21, 12.51, 12.82,
    13.12, 13.43, 13.73, 14.04, 14.34, 14.65, 14.95, 15.26, 15.56, 15.87, 16.17, 16.78, 17.09, 17.39, 17.70, 18.01,
};

@interface EDLFOGraph : NSView
@property (nonatomic) NSInteger shape; @property (nonatomic, copy) NSString *caption;
@end
@implementation EDLFOGraph
- (BOOL)isFlipped { return YES; }
static double lfoAt(NSInteger shape, double t) {   // t 0…1 over one cycle, result -1…1
    switch (shape) {
        case 0: return t < 0.25 ? t * 4 : (t < 0.75 ? 2 - t * 4 : t * 4 - 4);
        case 1: return sin(t * 2 * M_PI);
        case 2: return 1 - 2 * t;   // manual: smoothly decreases, then jumps back up
        case 3: return t < 0.5 ? 1 : -1;
        case 14: return 0.8 * sin(t * 2 * M_PI) + 0.25 * sin(t * 61.0) * cos(t * 17.0);
        default: { int k = (int)(t * 8); return fmod(sin(k * 12.9898) * 43758.5453, 2.0) - 1 > 1 ? 1 : (fmod(fabs(sin(k * 12.9898) * 43758.5453), 2.0) - 1); }
    }
}
- (void)drawRect:(NSRect)r {
    NSColor *ink = EDTheme.lcdInk; NSRect f = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *fr = [NSBezierPath bezierPathWithRect:f]; fr.lineWidth = 2; [ink setStroke]; [fr stroke];
    CGFloat pad = 10, top = 22, h = f.size.height - top - pad, w = f.size.width - 2 * pad, mid = top + h / 2;
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:11], NSForegroundColorAttributeName: ink};
    [_caption drawAtPoint:NSMakePoint(8, 4) withAttributes:at];
    NSBezierPath *z = [NSBezierPath bezierPath]; [z moveToPoint:NSMakePoint(pad, mid)]; [z lineToPoint:NSMakePoint(pad + w, mid)];
    CGFloat d[2] = {3, 3}; [z setLineDash:d count:2 phase:0]; [[ink colorWithAlphaComponent:0.35] setStroke]; [z stroke];
    NSBezierPath *p = [NSBezierPath bezierPath]; p.lineWidth = 2; p.lineJoinStyle = NSLineJoinStyleRound;
    BOOL steps = _shape != 0 && _shape != 1 && _shape != 2 && _shape != 3 && _shape != 14;
    for (int i = 0; i <= 160; i++) {
        double t = MIN(i / 160.0, 0.9999), y = lfoAt(_shape, t);
        NSPoint pt = NSMakePoint(pad + w * i / 160.0, mid - y * h / 2 * 0.9);
        i ? [p lineToPoint:pt] : [p moveToPoint:pt]; (void)steps;
    }
    [ink setStroke]; [p stroke];
}
@end

/// Double-click on a value box: the first click starts editing and the field editor then owns the second one, so both the box and its editor report it.
@interface EDLCDFieldEditor : NSTextView
@end
@interface EDLCDFieldCell : NSTextFieldCell
@end
@interface EDPresetLCDField : NSTextField
@property (nonatomic) NSInteger paramTag;
@property (nonatomic, copy) void (^wheel)(NSInteger steps);
@property (nonatomic, copy) void (^reset)(void);
@end
@implementation EDLCDFieldEditor
- (void)mouseDown:(NSEvent *)e { id d = self.delegate; if (e.clickCount == 2 && [d isKindOfClass:NSControl.class] && [d respondsToSelector:@selector(reset)] && [(EDPresetLCDField *)d reset]) { ((void (^)(void))[(EDPresetLCDField *)d reset])(); return; } [super mouseDown:e]; }
@end
@implementation EDLCDFieldCell
- (NSTextView *)fieldEditorForView:(NSView *)v {
    static EDLCDFieldEditor *ed; if (!ed) { ed = [[EDLCDFieldEditor alloc] initWithFrame:NSZeroRect]; ed.fieldEditor = YES; }
    return ed;
}
@end
@implementation EDPresetLCDField { CGFloat _acc; }
+ (Class)cellClass { return EDLCDFieldCell.class; }
- (void)mouseDown:(NSEvent *)e { if (e.clickCount == 2 && self.reset && self.isEditable) { self.reset(); return; } [super mouseDown:e]; }
/// Mouse wheel over a value: one click = one step (Shift = 10); trackpads accumulate small deltas.
- (void)scrollWheel:(NSEvent *)e {
    CGFloat dy = e.isDirectionInvertedFromDevice ? -e.scrollingDeltaY : e.scrollingDeltaY;   // wheel up = larger, whatever the natural-scrolling setting
    if (!self.wheel || !self.isEnabled || !self.isEditable || dy == 0) { [super scrollWheel:e]; return; }
    if (e.phase == NSEventPhaseBegan || e.phase == NSEventPhaseMayBegin) _acc = 0;
    _acc += e.hasPreciseScrollingDeltas ? dy : (dy > 0 ? 1 : -1);
    CGFloat step = e.hasPreciseScrollingDeltas ? 10 : 1; NSInteger n = 0;
    while (fabs(_acc) >= step) { NSInteger dir = _acc > 0 ? 1 : -1; _acc -= dir * step; n += dir; }
    if (n) self.wheel(n * ((e.modifierFlags & NSEventModifierFlagShift) ? 10 : 1));
}
@end

@implementation EDPresetLCD {
    EDPreset *_preset; NSInteger _voice, _ref;
    NSString *_menu; NSInteger _page, _lastV, _lastR;
    NSMutableArray<NSDictionary *> *_active;     // pages of the current menu that have rows for this preset
    NSMutableArray<EDParam *> *_fieldParams;
    NSMutableArray<NSButton *> *_menuBtns; NSStackView *_menuRow;
    NSView *_screen; NSTextField *_title, *_context, *_empty; NSButton *_prevV, *_nextV;
    NSStackView *_grid, *_keys; EDEnvGraph *_graph; EDWindowGraph *_winGraph; NSButton *_scaleBtn; EDLFOGraph *_lfoGraph[2];
}

- (instancetype)initWithFrame:(NSRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    _menu = @"Global"; _voice = -1; _ref = -1; _fieldParams = [NSMutableArray array];
    _menuBtns = [NSMutableArray array]; NSStackView *menuRow = [NSStackView new]; menuRow.spacing = 6;
    for (NSInteger i = 0; i < 3; i++) { NSButton *b = [EDTheme lcdButton:@[@"Global", @"Voice", @"Zone"][i] target:self action:@selector(menuPicked:)]; b.tag = i; [b.widthAnchor constraintEqualToConstant:78].active = YES; [_menuBtns addObject:b]; [menuRow addArrangedSubview:b]; }
    menuRow.translatesAutoresizingMaskIntoConstraints = NO; _menuRow = menuRow;
    _screen = [NSView new]; _screen.wantsLayer = YES; _screen.layer.backgroundColor = EDTheme.lcdBackground.CGColor;
    _screen.layer.cornerRadius = 0; _screen.layer.borderColor = NSColor.blackColor.CGColor; _screen.layer.borderWidth = EDTheme.lcdFrameWidth;
    _screen.translatesAutoresizingMaskIntoConstraints = NO;
    _title = [NSTextField labelWithString:@""]; _title.font = [EDTheme lcdFont:22]; _title.textColor = EDTheme.lcdInk;
    _context = [NSTextField labelWithString:@""]; _context.font = [EDTheme lcdFont:14]; _context.textColor = EDTheme.lcdInk;
    _prevV = [EDTheme lcdButton:@"◀" target:self action:@selector(prevItem:)]; _nextV = [EDTheme lcdButton:@"▶" target:self action:@selector(nextItem:)];
    for (NSButton *b in @[_prevV, _nextV]) { [b setButtonType:NSButtonTypeMomentaryPushIn]; [b.widthAnchor constraintEqualToConstant:40].active = YES; }
    _empty = [NSTextField ed_wrappingLabelWithString:@""]; _empty.font = [EDTheme lcdFont:15]; _empty.textColor = EDTheme.lcdInk; _empty.alignment = NSTextAlignmentCenter;
    _grid = [NSStackView new]; _grid.orientation = NSUserInterfaceLayoutOrientationHorizontal; _grid.alignment = NSLayoutAttributeTop; _grid.spacing = 40;
    _keys = [NSStackView new]; _keys.orientation = NSUserInterfaceLayoutOrientationVertical; _keys.spacing = 6; _keys.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *v in @[_title, _context, _prevV, _nextV, _empty, _grid, _menuRow, _keys]) { v.translatesAutoresizingMaskIntoConstraints = NO; [_screen addSubview:v]; }
    _graph = [EDEnvGraph new]; _graph.translatesAutoresizingMaskIntoConstraints = NO; _graph.hidden = YES; [_screen addSubview:_graph];
    _winGraph = [EDWindowGraph new]; _winGraph.translatesAutoresizingMaskIntoConstraints = NO; _winGraph.hidden = YES; [_screen addSubview:_winGraph];
    _scaleBtn = [EDTheme lcdButton:@"Fixed" target:self action:@selector(toggleScale:)]; _scaleBtn.translatesAutoresizingMaskIntoConstraints = NO; _scaleBtn.hidden = YES;
    [_scaleBtn.widthAnchor constraintEqualToConstant:104].active = YES; [_screen addSubview:_scaleBtn];
    _graph.scaled = [NSUserDefaults.standardUserDefaults boolForKey:@"EnvScaled"]; _scaleBtn.title = _graph.scaled ? @"Scaled" : @"Fixed";
    for (int i = 0; i < 2; i++) {
        _lfoGraph[i] = [EDLFOGraph new]; _lfoGraph[i].translatesAutoresizingMaskIntoConstraints = NO; _lfoGraph[i].hidden = YES; _lfoGraph[i].caption = [NSString stringWithFormat:@"LFO %d", i + 1]; [_screen addSubview:_lfoGraph[i]];
        [NSLayoutConstraint activateConstraints:@[[_lfoGraph[i].topAnchor constraintEqualToAnchor:_menuRow.bottomAnchor constant:40], [_lfoGraph[i].leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:560 + i * 200],
            [_lfoGraph[i].widthAnchor constraintEqualToConstant:180], [_lfoGraph[i].heightAnchor constraintEqualToConstant:110]]];
    }
    __weak EDPresetLCD *ws = self;
    _graph.get = ^NSInteger(EDParam *p) { EDPresetLCD *me = ws; return me.getValue ? me.getValue(p, [me vIndex], [me rIndex]) : 0; };
    _graph.set = ^(EDParam *p, NSInteger v) { EDPresetLCD *me = ws; if (me.setValue) me.setValue(p, [me vIndex], [me rIndex], v); };
    _winGraph.get = _graph.get; _winGraph.set = _graph.set;
    [EDTheme addGlareTo:_screen];
    [self addSubview:_screen];
    [NSLayoutConstraint activateConstraints:@[
        [_screen.topAnchor constraintEqualToAnchor:self.topAnchor], [_screen.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [_screen.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_screen.heightAnchor constraintGreaterThanOrEqualToConstant:380],
        [_menuRow.topAnchor constraintEqualToAnchor:_screen.topAnchor constant:12], [_menuRow.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:14],
        [_title.centerYAnchor constraintEqualToAnchor:_menuRow.centerYAnchor], [_title.centerXAnchor constraintEqualToAnchor:_screen.centerXAnchor],
        [_nextV.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor constant:-14], [_nextV.centerYAnchor constraintEqualToAnchor:_menuRow.centerYAnchor],
        [_prevV.trailingAnchor constraintEqualToAnchor:_nextV.leadingAnchor constant:-6], [_prevV.centerYAnchor constraintEqualToAnchor:_menuRow.centerYAnchor],
        [_context.trailingAnchor constraintEqualToAnchor:_prevV.leadingAnchor constant:-12], [_context.centerYAnchor constraintEqualToAnchor:_menuRow.centerYAnchor],
        [_graph.topAnchor constraintEqualToAnchor:_menuRow.bottomAnchor constant:40], [_graph.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:330],
        [_scaleBtn.topAnchor constraintEqualToAnchor:_graph.bottomAnchor constant:8], [_scaleBtn.trailingAnchor constraintEqualToAnchor:_graph.trailingAnchor],
        [_graph.trailingAnchor constraintEqualToAnchor:_context.leadingAnchor], [_graph.widthAnchor constraintGreaterThanOrEqualToConstant:300], [_graph.heightAnchor constraintEqualToConstant:250],
        [_winGraph.topAnchor constraintEqualToAnchor:_grid.bottomAnchor constant:24], [_winGraph.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:24], [_winGraph.trailingAnchor constraintEqualToAnchor:_screen.trailingAnchor constant:-24], [_winGraph.bottomAnchor constraintEqualToAnchor:_keys.topAnchor constant:-16],
        [_grid.topAnchor constraintEqualToAnchor:_menuRow.bottomAnchor constant:22], [_grid.leadingAnchor constraintEqualToAnchor:_screen.leadingAnchor constant:24],
        [_empty.centerXAnchor constraintEqualToAnchor:_screen.centerXAnchor], [_empty.centerYAnchor constraintEqualToAnchor:_screen.centerYAnchor constant:-20], [_empty.widthAnchor constraintEqualToConstant:420],
        [_keys.centerXAnchor constraintEqualToAnchor:_screen.centerXAnchor], [_keys.bottomAnchor constraintEqualToAnchor:_screen.bottomAnchor constant:-12],
        [_screen.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
    return self;
}

// MARK: selection

- (void)showPreset:(EDPreset *)p voice:(NSInteger)v ref:(NSInteger)r {
    BOOL selectionChanged = p != _preset || v != _lastV || r != _lastR;
    _preset = p; _voice = v; _ref = r; _lastV = v; _lastR = r;
    if (selectionChanged) {   // follow the structure list when the selection moves; keep a manually chosen menu otherwise
        NSString *want = r >= 0 ? @"Zone" : (v >= 0 ? @"Voice" : @"Global");
        if (![want isEqualToString:_menu]) { _menu = want; _page = 0; }
    }
    [self rebuild];
}
- (void)menuPicked:(NSButton *)s { _menu = @[@"Global", @"Voice", @"Zone"][s.tag]; _page = 0; [self rebuild]; }
- (NSInteger)vIndex { return MAX(_voice, 0); }
- (NSInteger)rIndex { return MAX(_ref, 0); }
- (EDParamScope)scopeForMenu { return [_menu isEqual:@"Global"] ? EDScopePreset : ([_menu isEqual:@"Voice"] ? EDScopeVoice : EDScopeRef); }

// MARK: build

- (NSArray *)resolvedRows:(NSDictionary *)pg {   // @[@[label, @[EDParam]]]
    NSArray<EDParam *> *ps = [_preset paramsForScope:[self scopeForMenu]];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *r in pg[@"rows"]) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSString *l in r[2]) { EDParam *p = find(ps, r[1], l); if (p) [cells addObject:p]; }
        if (cells.count == [r[2] count]) [out addObject:@[r[0], cells]];
    }
    return out;
}
- (void)rebuild {
    for (NSButton *b in _menuBtns) b.state = [@[@"Global", @"Voice", @"Zone"][b.tag] isEqual:_menu] ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSView *v in _grid.arrangedSubviews.copy) { [_grid removeArrangedSubview:v]; [v removeFromSuperview]; }
    for (NSView *v in _keys.arrangedSubviews.copy) { [_keys removeArrangedSubview:v]; [v removeFromSuperview]; }
    [_fieldParams removeAllObjects];
    _active = [NSMutableArray array];
    NSInteger nv = _preset.voiceCount, nz = (_preset && _voice >= 0) ? [_preset refCountInVoice:_voice] : 0;
    BOOL noData = !_preset || ([_menu isEqual:@"Voice"] && nv == 0) || ([_menu isEqual:@"Zone"] && (nz == 0));
    if (_preset && !noData) for (NSDictionary *pg in pages()) if ([pg[@"menu"] isEqual:_menu] && [self resolvedRows:pg].count) [_active addObject:pg];
    _prevV.hidden = _nextV.hidden = ![_menu isEqual:@"Global"] ? NO : YES;
    if ([_menu isEqual:@"Voice"]) _context.stringValue = [NSString stringWithFormat:@"Voice %ld of %ld", (long)[self vIndex] + 1, (long)nv];
    else if ([_menu isEqual:@"Zone"]) _context.stringValue = nz ? [NSString stringWithFormat:@"Voice %ld  Zone %ld of %ld", (long)[self vIndex] + 1, (long)[self rIndex] + 1, (long)nz] : @"";
    else _context.stringValue = _preset ? [NSString stringWithFormat:@"%@", _preset.name] : @"";
    _graph.hidden = YES; _winGraph.hidden = YES; _scaleBtn.hidden = YES; _lfoGraph[0].hidden = _lfoGraph[1].hidden = YES;
    if (!_active.count) {
        _title.stringValue = _menu; _empty.hidden = NO; _grid.hidden = YES;
        _empty.stringValue = !_preset ? @"No preset selected." : ([_menu isEqual:@"Zone"] ? @"Select a voice's sample zone in the structure list." : (_preset.kind == EDPresetKindLegacy3X ? @"Emulator 3X preset: only some parameters are decoded. See the List view." : @"Nothing to show."));
        return;
    }
    _empty.hidden = YES; _grid.hidden = NO;
    if (_page >= (NSInteger)_active.count) _page = 0;
    for (NSInteger i = 0; i < (NSInteger)_active.count; i++) {
        if (i % 6 == 0) { NSStackView *row = [NSStackView new]; row.spacing = 8; [_keys addArrangedSubview:row]; }
        NSButton *b = [EDTheme lcdButton:_active[i][@"soft"] target:self action:@selector(softKey:)];
        b.tag = i; b.state = i == _page ? NSControlStateValueOn : NSControlStateValueOff;
        [b.widthAnchor constraintEqualToConstant:104].active = YES; [(NSStackView *)_keys.arrangedSubviews.lastObject addArrangedSubview:b];
    }
    NSDictionary *pg = _active[_page]; _title.stringValue = pg[@"title"];
    NSArray *rows = [self resolvedRows:pg]; NSArray *heads = pg[@"heads"];
    if (rows.count == 6 && [pg[@"title"] hasSuffix:@"Envelope"]) {
        NSMutableArray *ep = [NSMutableArray array];
        for (NSArray *r in rows) [ep addObjectsFromArray:r[1]];
        _graph.params = ep; _graph.unipolar = YES; _graph.hidden = NO; _scaleBtn.hidden = NO; _graph.needsDisplay = YES;
    }
    if ([pg[@"title"] hasSuffix:@"Windows"] && rows.count >= 2) {   // key and velocity windows get a picture
        NSMutableArray *wp = [NSMutableArray array];
        for (NSInteger i = 0; i < 2; i++) [wp addObjectsFromArray:rows[i][1]];
        _winGraph.params = wp; _winGraph.hidden = NO; _winGraph.needsDisplay = YES;
    }
    if ([pg[@"title"] isEqual:@"LFOs and Lag"])
        for (int i = 0; i < 2 && i < (int)rows.count; i++) {
            NSArray<EDParam *> *c = rows[i][1];
            _lfoGraph[i].shape = c.count > 1 && self.getValue ? self.getValue(c[1], [self vIndex], [self rIndex]) : 0;
            if (self.getValue) { NSInteger rb = MAX(0, MIN(127, self.getValue(c[0], [self vIndex], [self rIndex]))); _lfoGraph[i].caption = [NSString stringWithFormat:@"LFO %d  %.2f Hz", i + 1, kLFOHz[rb]]; } _lfoGraph[i].hidden = NO; _lfoGraph[i].needsDisplay = YES;
        }
    NSInteger perCol = heads ? 8 : 7, ncol = ((NSInteger)rows.count + perCol - 1) / perCol;
    for (NSInteger c = 0; c < ncol; c++) {
        NSStackView *col = [NSStackView new]; col.orientation = NSUserInterfaceLayoutOrientationVertical; col.alignment = NSLayoutAttributeLeading; col.spacing = heads ? 5 : 10;
        if (heads) {
            NSStackView *h = [NSStackView new]; h.spacing = 6;
            NSTextField *sp = [NSTextField labelWithString:@""]; [sp.widthAnchor constraintEqualToConstant:90].active = YES; [h addArrangedSubview:sp];
            for (NSString *t in heads) { NSTextField *l = [NSTextField labelWithString:t]; l.font = [EDTheme lcdFont:11]; l.textColor = EDTheme.lcdInk; l.alignment = NSTextAlignmentCenter; [l.widthAnchor constraintEqualToConstant:heads.count > 3 && [heads[0] isEqual:@"Rate"] ? 64 : 76].active = YES; [h addArrangedSubview:l]; }
            [col addArrangedSubview:h];
        }
        for (NSInteger r = c * perCol; r < MIN((NSInteger)rows.count, (c + 1) * perCol); r++) [col addArrangedSubview:[self rowView:rows[r] wide:!heads]];
        [_grid addArrangedSubview:col];
    }
}
- (NSView *)rowView:(NSArray *)row wide:(BOOL)wide {
    NSTextField *lab = [NSTextField labelWithString:row[0]]; lab.font = [EDTheme lcdFont:wide ? 16 : 14]; lab.textColor = EDTheme.lcdInk;
    [lab.widthAnchor constraintEqualToConstant:wide ? 210 : 90].active = YES;
    NSStackView *st = [NSStackView stackViewWithViews:@[lab]]; st.spacing = 6; st.alignment = NSLayoutAttributeCenterY;
    NSArray<EDParam *> *cells = row[1];
    for (EDParam *p in cells) [st addArrangedSubview:[self control:p wide:wide && cells.count == 1 ? YES : NO]];
    if (cells.count == 1) {
        EDParam *p = cells[0]; NSInteger v = self.getValue ? self.getValue(p, [self vIndex], [self rIndex]) : 0;
        NSString *info = p.isSample ? (self.sampleName ? self.sampleName(v) : @"") : (p.isNote ? [EDParam noteName:v] : (p.names ? @"" : [NSString stringWithFormat:@"%ld … %ld", (long)p.min, (long)p.max]));
        NSTextField *i = [NSTextField labelWithString:info]; i.font = [EDTheme lcdFont:11]; i.textColor = [EDTheme.lcdInk colorWithAlphaComponent:0.75]; [st addArrangedSubview:i];
    }
    return st;
}
- (NSView *)control:(EDParam *)p wide:(BOOL)wide {
    NSInteger v = self.getValue ? self.getValue(p, [self vIndex], [self rIndex]) : 0;
    CGFloat w = p.names ? (wide ? 190 : 120) : (wide ? 90 : 70);
    if (p.names) {
        NSPopUpButton *pop = [[EDWheelPopUp alloc] initWithFrame:NSZeroRect pullsDown:NO]; pop.bordered = NO; pop.font = [EDTheme lcdFont:wide ? 16 : 13];
        pop.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        NSDictionary *attr = @{NSFontAttributeName: [EDTheme lcdFont:wide ? 16 : 13], NSForegroundColorAttributeName: EDTheme.lcdInk};
        NSMutableArray<NSNumber *> *keys = [[p.names.allKeys sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
        if (![keys containsObject:@(v)]) { [keys addObject:@(v)]; [keys sortUsingSelector:@selector(compare:)]; }
        for (NSNumber *k in keys) {
            NSString *t = p.names[k] ?: [NSString stringWithFormat:@"%@", k];
            NSMenuItem *mi = [pop.menu addItemWithTitle:t action:nil keyEquivalent:@""]; mi.tag = k.integerValue; mi.attributedTitle = [[NSAttributedString alloc] initWithString:t attributes:attr];
            if (k.integerValue == v) [pop selectItem:mi];
        }
        [EDTheme styleLCDPopup:pop]; pop.target = self; pop.action = @selector(popPicked:); pop.tag = (NSInteger)_fieldParams.count; [_fieldParams addObject:p];
        pop.enabled = !p.readOnly; [pop.widthAnchor constraintGreaterThanOrEqualToConstant:w].active = YES;
        return pop;
    }
    EDPresetLCDField *f = [EDPresetLCDField textFieldWithString:p.isNote && !p.isSample ? [EDParam noteName:v] : [NSString stringWithFormat:@"%ld", (long)v]];
    f.font = [EDTheme lcdFont:wide ? 16 : 13]; f.textColor = EDTheme.lcdInk; f.bordered = NO; f.drawsBackground = NO; f.focusRingType = NSFocusRingTypeNone;
    f.editable = !p.readOnly; f.alignment = NSTextAlignmentCenter; f.wantsLayer = YES; f.layer.borderWidth = p.readOnly ? 0 : 1.5; f.layer.borderColor = EDTheme.lcdInk.CGColor; f.layer.cornerRadius = 0;
    f.target = self; f.action = @selector(fieldCommitted:); f.paramTag = (NSInteger)_fieldParams.count; [_fieldParams addObject:p];
    __weak EDPresetLCD *wl = self; __weak EDPresetLCDField *wf = f;
    f.wheel = ^(NSInteger n) { EDPresetLCD *me = wl; EDPresetLCDField *fl = wf; if (!me || !fl) return; [me wheelStep:n field:fl]; };
    if (!p.readOnly) {   // right-click: reset, or one of the values that matter for this box
        NSMenu *m = [NSMenu new]; NSInteger dv = 0; BOOL hasDef = [_preset getDefault:&dv ofParam:p];
        NSString *(^show)(NSInteger) = ^NSString *(NSInteger k) { return p.isNote && !p.isSample ? [EDParam noteName:k] : [NSString stringWithFormat:@"%ld", (long)k]; };
        void (^add)(NSString *, SEL, NSInteger, NSNumber *, BOOL) = ^(NSString *t, SEL a, NSInteger tag, NSNumber *val, BOOL on) {
            NSMenuItem *it = [m addItemWithTitle:[(on ? @"✓ " : @"   ") stringByAppendingString:t] action:a keyEquivalent:@""]; it.target = self; it.tag = tag; it.representedObject = val; };
        if (hasDef) add(@"Reset to Default", @selector(menuReset:), f.paramTag, nil, NO);
        NSMutableArray<NSNumber *> *vals = [NSMutableArray array];
        if (p.max - p.min <= 16) for (NSInteger k = p.min; k <= p.max; k++) [vals addObject:@(k)];
        else { NSMutableSet *seen = [NSMutableSet set]; for (NSNumber *k in @[@(p.min), @(0), @(hasDef ? dv : p.min), @(p.max)]) if (k.integerValue >= p.min && k.integerValue <= p.max && ![seen containsObject:k]) { [seen addObject:k]; [vals addObject:k]; } [vals sortUsingSelector:@selector(compare:)]; }
        if (vals.count) { if (m.numberOfItems) [m addItem:NSMenuItem.separatorItem];
            for (NSNumber *k in vals) { NSInteger kv = k.integerValue; NSString *tag = kv == p.min && p.max - p.min > 16 ? @" (min)" : kv == p.max && p.max - p.min > 16 ? @" (max)" : (hasDef && kv == dv && p.max - p.min > 16) ? @" (default)" : @"";
                add([show(kv) stringByAppendingString:tag], @selector(menuPickValue:), f.paramTag, k, kv == v); } }
        f.menu = m; [EDTheme useLCDContextMenuOn:f]; }
    f.reset = ^{ EDPresetLCD *me = wl; EDPresetLCDField *fl = wf; if (me && fl) [me resetField:fl]; };
    [f.widthAnchor constraintEqualToConstant:w].active = YES;
    return f;
}

// MARK: actions

- (void)toggleScale:(NSButton *)b {
    _graph.scaled = !_graph.scaled; b.title = _graph.scaled ? @"Scaled" : @"Fixed"; _graph.needsDisplay = YES;
    [NSUserDefaults.standardUserDefaults setBool:_graph.scaled forKey:@"EnvScaled"];
}
- (void)softKey:(NSButton *)b { _page = b.tag; [self rebuild]; }
- (void)popPicked:(NSPopUpButton *)b {
    EDParam *p = _fieldParams[b.tag]; if (self.setValue) self.setValue(p, [self vIndex], [self rIndex], b.selectedItem.tag);
}
- (void)menuReset:(NSMenuItem *)mi { [self resetParamAt:mi.tag]; }
- (void)menuPickValue:(NSMenuItem *)mi {
    if (mi.tag >= (NSInteger)_fieldParams.count) return;
    [self.window makeFirstResponder:nil];
    if (self.setValue) self.setValue(_fieldParams[mi.tag], [self vIndex], [self rIndex], [mi.representedObject integerValue]);
    [self rebuild];
}
- (void)resetField:(EDPresetLCDField *)f { [self resetParamAt:f.paramTag]; }
- (void)resetParamAt:(NSInteger)tag {
    if (tag >= (NSInteger)_fieldParams.count || !_preset) return;
    EDParam *p = _fieldParams[tag]; NSInteger dv = 0;
    BOOL okd = [_preset getDefault:&dv ofParam:p];
    if (!okd) { NSBeep(); return; }
    [self.window makeFirstResponder:nil];   // end the editing the first click started, or it commits the old text over the default
    if (self.setValue) self.setValue(p, [self vIndex], [self rIndex], dv);
    [self rebuild];
}
- (void)wheelStep:(NSInteger)n field:(EDPresetLCDField *)f {
    if (f.paramTag >= (NSInteger)_fieldParams.count) return;
    EDParam *p = _fieldParams[f.paramTag]; if (p.readOnly || !self.getValue) return;
    NSInteger old = self.getValue(p, [self vIndex], [self rIndex]);
    if (self.setValue) self.setValue(p, [self vIndex], [self rIndex], old + n);
    [self rebuild];   // shows the clamped value
}
- (void)fieldCommitted:(EDPresetLCDField *)f {
    EDParam *p = _fieldParams[f.paramTag];
    NSInteger nv = parseNoteOrInt(f.stringValue, p);
    NSInteger old = self.getValue ? self.getValue(p, [self vIndex], [self rIndex]) : nv;
    if (nv != old && self.setValue) self.setValue(p, [self vIndex], [self rIndex], nv);
    [self rebuild];   // shows the clamped value
}
- (void)prevItem:(id)s { [self stepItem:-1]; }
- (void)nextItem:(id)s { [self stepItem:1]; }
- (void)stepItem:(NSInteger)d {
    if (!self.navigate || !_preset) return;
    if ([_menu isEqual:@"Voice"]) { NSInteger n = _preset.voiceCount, v = MAX(0, MIN(n - 1, [self vIndex] + d)); self.navigate(v, -1); }
    else if ([_menu isEqual:@"Zone"]) { NSInteger n = [_preset refCountInVoice:[self vIndex]], r = MAX(0, MIN(n - 1, [self rIndex] + d)); self.navigate([self vIndex], r); }
}
@end
