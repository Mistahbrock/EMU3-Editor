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
@implementation EDEnvGraph { NSInteger _drag; CGFloat _dragScale; }
static const CGFloat kSeg = 62, kMin = 8, kPad = 14;
- (BOOL)isFlipped { return YES; }
- (CGFloat)zeroY { CGFloat h = self.bounds.size.height - 2 * kPad; return kPad + h / 2; }   // same layout for all envelopes; volume just cannot go below zero
- (CGFloat)pxPerLevel { CGFloat h = self.bounds.size.height - 2 * kPad; return h / 2 / 127.0; }
// EOS rates: 0 is instant, 127 is slowest. In the time-scaled display a stage also takes longer the further its level has to travel.
- (CGFloat)levelFactor:(NSInteger)i level:(NSInteger)lvl {
    if (!_scaled) return 1;
    NSInteger prev = i ? _get(_params[i * 2 - 1]) : 0;
    return 0.25 + 0.75 * MIN(127, labs(lvl - prev)) / 127.0;
}
- (CGFloat)rawWidth:(NSInteger)i { return kMin + kSeg * _get(_params[i * 2]) / 127.0 * [self levelFactor:i level:_get(_params[i * 2 + 1])]; }
- (CGFloat)timeScale {
    if (!_scaled) return 1;
    CGFloat t = 0; for (int i = 0; i < 6; i++) t += [self rawWidth:i];
    return (self.bounds.size.width - 2 * kPad) / t;
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
        [EDTheme.lcdBackground setFill]; NSRectFill(b); [ink setStroke]; NSBezierPath *bp = [NSBezierPath bezierPathWithRect:b]; bp.lineWidth = i == _drag ? 3 : 1.5; [bp stroke];
    }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint m = [self convertPoint:e.locationInWindow fromView:nil]; _drag = 0; CGFloat best = 12;
    NSArray<NSValue *> *pts = [self points];
    for (NSInteger i = 1; i < 7; i++) { NSPoint p = pts[i].pointValue; CGFloat d = hypot(p.x - m.x, p.y - m.y); if (d < best) { best = d; _drag = i; } }
    _dragScale = [self timeScale]; if (_drag) [self mouseDragged:e];
}
- (void)mouseDragged:(NSEvent *)e {
    if (!_drag) return;
    NSPoint m = [self convertPoint:e.locationInWindow fromView:nil];
    NSArray<NSValue *> *pts = [self points]; CGFloat prevX = pts[_drag - 1].pointValue.x;
    NSInteger lvl = (NSInteger)llround(([self zeroY] - m.y) / [self pxPerLevel]);
    lvl = MAX(_unipolar ? 0 : -127, MIN(127, lvl));
    NSInteger rate = (NSInteger)llround(((m.x - prevX) / _dragScale - kMin) / kSeg * 127 / [self levelFactor:_drag - 1 level:lvl]);
    EDParam *rp = _params[(_drag - 1) * 2], *lp = _params[(_drag - 1) * 2 + 1];
    rate = MAX(rp.min, MIN(rp.max, rate)); lvl = MAX(_unipolar ? 0 : lp.min, MIN(lp.max, lvl));
    if (rate != _get(rp)) _set(rp, rate);
    if (lvl != _get(lp)) _set(lp, lvl);
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

@interface EDPresetLCDField : NSTextField
@property (nonatomic) NSInteger paramTag;
@end
@implementation EDPresetLCDField
@end

@implementation EDPresetLCD {
    EDPreset *_preset; NSInteger _voice, _ref;
    NSString *_menu; NSInteger _page, _lastV, _lastR;
    NSMutableArray<NSDictionary *> *_active;     // pages of the current menu that have rows for this preset
    NSMutableArray<EDParam *> *_fieldParams;
    NSMutableArray<NSButton *> *_menuBtns; NSStackView *_menuRow;
    NSView *_screen; NSTextField *_title, *_context, *_empty; NSButton *_prevV, *_nextV;
    NSStackView *_grid, *_keys; EDEnvGraph *_graph; NSButton *_scaleBtn; EDLFOGraph *_lfoGraph[2];
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
        [_graph.widthAnchor constraintEqualToConstant:460], [_graph.heightAnchor constraintEqualToConstant:250],
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
    _graph.hidden = YES; _scaleBtn.hidden = YES; _lfoGraph[0].hidden = _lfoGraph[1].hidden = YES;
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
