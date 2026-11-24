// Fractal tone generator: one cycle taken along a path through a fractal, made exactly periodic so it loops with no seam.
// Ported from the Fractal tool of Sample Surgeon (Mandelbrot / Julia / Weierstrass / Takagi, and the Avalon-style circle tree).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import "EDGenerator.h"
#import "EDTheme.h"
#import "EDGenScope.h"

typedef NS_ENUM(NSInteger, EDFractalKind) { EDFKMandelbrot, EDFKJulia, EDFKWeierstrass, EDFKTakagi, EDFKCircles };
static const int kCycleN = 2048;


// The fractal itself, with the path through it drawn as a ring: drag = move the ring, drag the ring = radius, ⇧-drag = move the fractal, wheel = zoom, ⇧-wheel = radius.
@interface EDFractalImageView : NSView
@property (nonatomic) BOOL julia;
@property (nonatomic) double cRe, cIm, zRe, zIm, radius, viewRe, viewIm, zoom;
@property (nonatomic, copy) void (^onChange)(void);
@end
@implementation EDFractalImageView {
    CGImageRef _img; NSString *_key; int _mode; double _p0[2], _v0[2]; NSPoint _start; uint64_t _gen;
}
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(360, 270); }
- (void)dealloc { if (_img) CGImageRelease(_img); }
- (double)span { return (_julia ? 3.0 : 3.2) / MAX(1, _zoom); }
- (NSPoint)toPoint:(double)re im:(double)im { double W = self.bounds.size.width, H = self.bounds.size.height; return NSMakePoint((re - _viewRe) / self.span * W + W / 2, -(im - _viewIm) / self.span * W + H / 2); }
- (void)toComplex:(NSPoint)p re:(double *)re im:(double *)im { double W = self.bounds.size.width, H = self.bounds.size.height; *re = _viewRe + (p.x / W - 0.5) * self.span; *im = _viewIm - (p.y / W - 0.5 * H / W) * self.span; }
- (void)refreshImage {
    NSString *k = [NSString stringWithFormat:@"%d|%.6f|%.6f|%.4f|%.4f|%.4f", _julia, _viewRe, _viewIm, _zoom, _julia ? _cRe : 0, _julia ? _cIm : 0];
    if ([k isEqualToString:_key]) { self.needsDisplay = YES; return; }
    _key = k; uint64_t gen = ++_gen; int W = 360, H = 270; BOOL julia = _julia; double vr = _viewRe, vi = _viewIm, z = _zoom, cr0 = _cRe, ci0 = _cIm, span = self.span;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int maxIt = 70 + (int)(25 * log2(MAX(1, z))); uint8_t *px = malloc((size_t)W * H * 4);
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
            double re = vr + ((double)x / W - 0.5) * span, im = vi - ((double)y / W - 0.5 * H / W) * span, zr, zi, cr, ci;
            if (!julia) { zr = 0; zi = 0; cr = re; ci = im; } else { zr = re; zi = im; cr = cr0; ci = ci0; }
            int n = 0; while (n < maxIt && zr * zr + zi * zi <= 256) { double nr = zr * zr - zi * zi + cr; zi = 2 * zr * zi + ci; zr = nr; n++; }
            uint8_t *o = px + ((size_t)y * W + x) * 4; o[3] = 255;
            if (n >= maxIt) { o[0] = 8; o[1] = 8; o[2] = 16; }
            else { double sm = n + 1 - log2(MAX(1e-9, log(zr * zr + zi * zi) / 2)), t = sm / 24;
                o[0] = (uint8_t)MAX(0, MIN(255, 128 + 127 * sin(6.28 * t))); o[1] = (uint8_t)MAX(0, MIN(255, 100 + 100 * sin(6.28 * t + 2.1))); o[2] = (uint8_t)MAX(0, MIN(255, 150 + 105 * sin(6.28 * t + 4.2))); }
        }
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB(); CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, (size_t)W * 4, cs, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
        CGImageRef im = CGBitmapContextCreateImage(ctx); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(px);
        dispatch_async(dispatch_get_main_queue(), ^{ if (gen == self->_gen) { if (self->_img) CGImageRelease(self->_img); self->_img = im; self.needsDisplay = YES; } else CGImageRelease(im); });
    });
}
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds; NSRectClip(b); [[NSColor blackColor] setFill]; NSRectFill(b);
    if (_img) { CGContextRef c = NSGraphicsContext.currentContext.CGContext; CGContextSaveGState(c); CGContextTranslateCTM(c, 0, b.size.height); CGContextScaleCTM(c, 1, -1); CGContextDrawImage(c, b, _img); CGContextRestoreGState(c); }
    NSPoint c = _julia ? [self toPoint:_zRe im:_zIm] : [self toPoint:_cRe im:_cIm]; double r = _radius / self.span * b.size.width;
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r, c.y - r, 2 * r, 2 * r)];
    [[NSColor colorWithWhite:0 alpha:0.7] setStroke]; ring.lineWidth = 4; [ring stroke]; [NSColor.whiteColor setStroke]; ring.lineWidth = 1.8; [ring stroke];
    [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(c.x - 2.5, c.y - 2.5, 5, 5));
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; NSFrameRect(b);
}
- (void)mouseDown:(NSEvent *)e {
    _start = [self convertPoint:e.locationInWindow fromView:nil]; NSPoint c = _julia ? [self toPoint:_zRe im:_zIm] : [self toPoint:_cRe im:_cIm];
    double ring = _radius / self.span * self.bounds.size.width, d = hypot(_start.x - c.x, _start.y - c.y);
    _mode = (e.modifierFlags & NSEventModifierFlagShift) ? 2 : ((fabs(d - ring) < 9 && ring > 6) ? 1 : 0);
    _v0[0] = _viewRe; _v0[1] = _viewIm; _p0[0] = _julia ? _zRe : _cRe; _p0[1] = _julia ? _zIm : _cIm; [self mouseDragged:e];
}
- (void)mouseDragged:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil], c = _julia ? [self toPoint:_zRe im:_zIm] : [self toPoint:_cRe im:_cIm]; double W = self.bounds.size.width, re, im; [self toComplex:p re:&re im:&im];
    if (_mode == 2) {
        double dRe = -(p.x - _start.x) / W * self.span, dIm = (p.y - _start.y) / W * self.span; _viewRe = _v0[0] + dRe; _viewIm = _v0[1] + dIm;
        if (_julia) { _zRe = _p0[0] + dRe; _zIm = _p0[1] + dIm; } else { _cRe = _p0[0] + dRe; _cIm = _p0[1] + dIm; }
    } else if (_mode == 1) _radius = MAX(0.002, MIN(1.0, hypot(p.x - c.x, p.y - c.y) / W * self.span));
    else if (_julia) { _zRe = re; _zIm = im; } else { _cRe = re; _cIm = im; }
    [self refreshImage]; if (_onChange) _onChange();
}
- (void)scrollWheel:(NSEvent *)e {
    double d = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.05 : 0.5);
    if (e.modifierFlags & NSEventModifierFlagShift) _radius = MAX(0.002, MIN(1.0, _radius * pow(1.07, d))); else _zoom = MAX(1, MIN(32, _zoom * pow(1.12, d)));
    [self refreshImage]; if (_onChange) _onChange();
}
@end

// Avalon-style circle tree: a mother circle with up to three daughters, each with a distance ratio and an angle from its mother's base vector, grown for a number of
// generations. Every circle is a sound event: size = volume, horizontal = onset time, vertical = pitch. The matrix is 1.6 : 1 like Avalon's (320 × 200).
static const double kAspect = 1.6;
typedef struct { double x, y, r; } EDCirc;
typedef struct { int n, gens, count, cap; double dd[3], da[3]; EDCirc *out; } EDGrow;
static void growRec(EDGrow *G, EDCirc c, double ang, int g) {
    if (G->count >= G->cap) return; G->out[G->count++] = c;
    if (g >= G->gens || c.r <= 0.004) return;
    for (int k = 0; k < G->n; k++) { double a = ang + G->da[k], d = G->dd[k] * c.r; growRec(G, (EDCirc){c.x + d * cos(a), c.y + d * sin(a), d}, a, g + 1); }
}
static int growCircles(NSDictionary *p, EDCirc *out, int cap) {
    EDGrow G = {MAX(1, MIN(3, (int)llround([p[@"daughters"] doubleValue]))), MAX(1, MIN(8, (int)llround([p[@"gens"] doubleValue]))), 0, cap, {0}, {0}, out};
    for (int k = 0; k < 3; k++) { G.dd[k] = [p[[NSString stringWithFormat:@"dd%d", k]] doubleValue]; G.da[k] = [p[[NSString stringWithFormat:@"da%d", k]] doubleValue]; }
    growRec(&G, (EDCirc){[p[@"mX"] doubleValue], [p[@"mY"] doubleValue], [p[@"mR"] doubleValue]}, [p[@"mAng"] doubleValue], 1);
    return G.count;
}
/// Preset from Avalon coordinates (320 × 200 matrix): mother (x, y, r), base-vector angle in degrees, daughters (x, y, r).
static NSDictionary *avalonDict(int depth, double mx, double my, double mr, double angle, NSArray<NSArray<NSNumber *> *> *ds) {
    NSMutableDictionary *d = [@{@"mX": @(mx / 200), @"mY": @(my / 200), @"mR": @(mr / 200), @"mAng": @(angle * M_PI / 180), @"daughters": @(ds.count), @"gens": @(depth)} mutableCopy];
    for (NSUInteger k = 0; k < ds.count; k++) {
        double dx = ds[k][0].doubleValue - mx, dy = ds[k][1].doubleValue - my, a = atan2(dy, dx) - angle * M_PI / 180;
        while (a > M_PI) a -= 2 * M_PI; while (a < -M_PI) a += 2 * M_PI;
        d[[NSString stringWithFormat:@"dd%lu", (unsigned long)k]] = @(hypot(dx, dy) / mr); d[[NSString stringWithFormat:@"da%lu", (unsigned long)k]] = @(a);
    }
    return d;
}

@interface EDCircleTreeView : NSView
@property (nonatomic, strong) NSMutableDictionary *state;      // the generator's parameters (mX, mY, mR, mAng, daughters, gens, dd0…2, da0…2)
@property (nonatomic) BOOL drawMode;                           // filled black circles on white, like a print
@property (nonatomic, copy) void (^onChange)(void);
@end
@implementation EDCircleTreeView { int _drag; }
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(360, 225); }
- (double)v:(NSString *)k { return [_state[k] doubleValue]; }
- (NSPoint)P:(double)x y:(double)y { double H = self.bounds.size.height; return NSMakePoint(x * H, y * H); }
- (NSPoint)tip { return [self P:[self v:@"mX"] + [self v:@"mR"] * cos([self v:@"mAng"]) y:[self v:@"mY"] + [self v:@"mR"] * sin([self v:@"mAng"])]; }
- (NSPoint)daughter:(int)k {
    double a = [self v:@"mAng"] + [self v:[NSString stringWithFormat:@"da%d", k]], d = [self v:[NSString stringWithFormat:@"dd%d", k]] * [self v:@"mR"];
    return [self P:[self v:@"mX"] + d * cos(a) y:[self v:@"mY"] + d * sin(a)];
}
- (void)drawRect:(NSRect)dirty {
    NSRect b = self.bounds; double H = b.size.height; NSRectClip(b);   // circles that stick out of the matrix stay inside the frame
    [(_drawMode ? NSColor.whiteColor : [NSColor colorWithWhite:0.08 alpha:1]) setFill]; NSRectFill(b);
    EDCirc *cs = malloc(sizeof(EDCirc) * 4000); int n = growCircles(_state, cs, 4000);
    for (int i = 0; i < n; i++) {
        NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect((cs[i].x - cs[i].r) * H, (cs[i].y - cs[i].r) * H, 2 * cs[i].r * H, 2 * cs[i].r * H)];
        if (_drawMode) { [[NSColor colorWithWhite:0 alpha:0.85] setFill]; [o fill]; } else { o.lineWidth = 0.8; [[NSColor colorWithSRGBRed:0.35 green:0.85 blue:0.55 alpha:0.55] setStroke]; [o stroke]; }
    }
    free(cs);
    if (!_drawMode) {
        NSPoint mc = [self P:[self v:@"mX"] y:[self v:@"mY"]], tip = [self tip];
        NSBezierPath *l = [NSBezierPath bezierPath]; [l moveToPoint:mc]; [l lineToPoint:tip]; l.lineWidth = 1.5; [NSColor.whiteColor setStroke]; [l stroke];
        NSMutableArray *pts = [NSMutableArray arrayWithObjects:[NSValue valueWithPoint:mc], [NSValue valueWithPoint:tip], nil];
        for (int k = 0; k < MAX(1, MIN(3, (int)llround([self v:@"daughters"]))); k++) [pts addObject:[NSValue valueWithPoint:[self daughter:k]]];
        for (NSUInteger i = 0; i < pts.count; i++) { NSPoint pt = [pts[i] pointValue]; [(i == 0 ? NSColor.whiteColor : i == 1 ? NSColor.orangeColor : NSColor.yellowColor) setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(pt.x - 5, pt.y - 5, 10, 10)] fill]; }
    }
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:9], NSForegroundColorAttributeName: NSColor.grayColor};
    [@"high" drawAtPoint:NSMakePoint(6, 3) withAttributes:a]; [@"low" drawAtPoint:NSMakePoint(6, b.size.height - 14) withAttributes:a]; [@"time →" drawAtPoint:NSMakePoint(b.size.width - 40, b.size.height - 14) withAttributes:a];
    [[NSColor colorWithWhite:1 alpha:0.12] setStroke]; NSFrameRect(b);
}
- (void)set:(NSString *)k to:(double)v { _state[k] = @(v); }
- (void)mouseDown:(NSEvent *)e {
    if (_drawMode) return;
    NSPoint s = [self convertPoint:e.locationInWindow fromView:nil];
    if (e.modifierFlags & NSEventModifierFlagShift) { [self set:@"mAng" to:cos([self v:@"mAng"]) < 0 ? M_PI : 0]; _drag = -2; self.needsDisplay = YES; if (_onChange) _onChange(); return; }
    NSMutableArray *pts = [NSMutableArray arrayWithObjects:[NSValue valueWithPoint:[self P:[self v:@"mX"] y:[self v:@"mY"]]], [NSValue valueWithPoint:[self tip]], nil];
    for (int k = 0; k < MAX(1, MIN(3, (int)llround([self v:@"daughters"]))); k++) [pts addObject:[NSValue valueWithPoint:[self daughter:k]]];
    int best = -2; double bd = 22;
    for (NSUInteger i = 0; i < pts.count; i++) { NSPoint pt = [pts[i] pointValue]; double d = hypot(s.x - pt.x, s.y - pt.y); if (d < bd) { bd = d; best = (int)i; } }
    _drag = best;
}
- (void)mouseDragged:(NSEvent *)e {
    if (_drag < 0) return;
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; double H = self.bounds.size.height, nx = p.x / H, ny = p.y / H, mx = [self v:@"mX"], my = [self v:@"mY"], mr = [self v:@"mR"], ma = [self v:@"mAng"];
    if (_drag == 0) { [self set:@"mX" to:MAX(0, MIN(kAspect, nx))]; [self set:@"mY" to:MAX(0, MIN(1, ny))]; }
    else if (_drag == 1) { double dx = nx - mx, dy = ny - my; [self set:@"mR" to:MAX(0.03, MIN(0.5, hypot(dx, dy)))]; [self set:@"mAng" to:atan2(dy, dx)]; }
    else {
        int k = _drag - 2; double dx = nx - mx, dy = ny - my, a = atan2(dy, dx) - ma;
        while (a > M_PI) a -= 2 * M_PI; while (a < -M_PI) a += 2 * M_PI;
        [self set:[NSString stringWithFormat:@"dd%d", k] to:MAX(0.1, MIN(1.2, hypot(dx, dy) / mr))]; [self set:[NSString stringWithFormat:@"da%d", k] to:a];
    }
    self.needsDisplay = YES; if (_onChange) _onChange();
}
- (void)mouseUp:(NSEvent *)e { _drag = -1; }
- (void)scrollWheel:(NSEvent *)e {
    double d = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.05 : 0.5);
    [self set:@"mR" to:MAX(0.03, MIN(0.5, [self v:@"mR"] * pow((e.modifierFlags & NSEventModifierFlagShift) ? 1.01 : 1.05, d)))]; self.needsDisplay = YES; if (_onChange) _onChange();
}
@end

@interface EDFractalGenerator : NSObject <EDGeneratorPlugin>
@end

@implementation EDFractalGenerator {
    __weak id<EDGeneratorHost> _host;
    NSView *_view;
    NSMutableDictionary<NSString *, NSNumber *> *_p;
    NSInteger _kind;
    NSMutableDictionary<NSString *, EDLineSlider *> *_sliders;
    NSMutableDictionary<NSString *, NSTextField *> *_vals;
    NSMutableDictionary<NSString *, NSArray<NSView *> *> *_rowViews;
    NSStackView *_grid;
    EDFractalImageView *_image; EDGenScope *_waveScope, *_specScope; NSStackView *_imageBox, *_circleBox, *_scopeRow, *_nrRow; EDCircleTreeView *_circles;
}
+ (NSString *)generatorIdentifier { return @"com.rhynoaudio.fractal"; }
+ (NSString *)generatorName { return @"Fractal"; }
+ (NSString *)generatorSummary { return @"Mandelbrot, Julia, Weierstrass, Takagi and Avalon circles"; }

static NSString *noteName(NSInteger n) { static NSString *nm[] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"}; return [NSString stringWithFormat:@"%@%ld", nm[((n % 12) + 12) % 12], (long)(n / 12 - 1)]; }

// key, title, min, max, which kinds show it (bitmask: 1 Mandelbrot, 2 Julia, 4 Weierstrass, 8 Takagi), format
static NSArray *paramTable(void) {
    return @[@[@"radius", @"Path radius", @0.002, @1.0, @3, @"%.3f"], @[@"iter", @"Iterations", @1, @30, @3, @"%.0f"],
             @[@"cRe", @"c real", @-2, @1.5, @3, @"%.3f"], @[@"cIm", @"c imaginary", @-1.5, @1.5, @3, @"%.3f"],
             @[@"zRe", @"z real (Julia path)", @-1.5, @1.5, @2, @"%.3f"], @[@"zIm", @"z imaginary (Julia path)", @-1.5, @1.5, @2, @"%.3f"],
             @[@"rough", @"Roughness", @0.2, @0.95, @12, @"%.2f"], @[@"scale", @"Scale", @2, @5, @4, @"%.0f"], @[@"depth", @"Depth", @1, @12, @12, @"%.0f"],
             @[@"morph", @"Detail (morph)", @0, @1, @15, @"%.2f"], @[@"tilt", @"Spectral tilt", @0, @2, @15, @"%.2f"],
             @[@"seconds", @"Length (s)", @0.5, @10, @31, @"%.1f"], @[@"attack", @"Attack (ms)", @0, @300, @15, @"%.0f"], @[@"level", @"Level", @0.1, @1, @31, @"%.2f"],
             @[@"daughters", @"Daughters", @1, @3, @16, @"%.0f"], @[@"gens", @"Generations", @1, @8, @16, @"%.0f"], @[@"tlen", @"T-length (ms)", @10, @600, @16, @"%.0f"],
             @[@"atkS", @"Attack (samples)", @1, @1000, @16, @"%.0f"], @[@"fLo", @"Low pitch (Hz)", @30, @1000, @16, @"%.0f"], @[@"fHi", @"High pitch (Hz)", @500, @12000, @16, @"%.0f"]];
}
static NSArray *presetList(void) {   // name, kind, then key/value pairs
    return @[@[@"Seahorse valley", @0, @{@"cRe": @-0.745, @"cIm": @0.113, @"radius": @0.03, @"iter": @12}],
             @[@"Cardioid edge", @0, @{@"cRe": @0.25, @"cIm": @0, @"radius": @0.2, @"iter": @8}],
             @[@"Antenna tip", @0, @{@"cRe": @-1.9, @"cIm": @0, @"radius": @0.07, @"iter": @10}],
             @[@"Mini-brot", @0, @{@"cRe": @-1.75, @"cIm": @0, @"radius": @0.035, @"iter": @11}],
             @[@"Julia rabbit", @1, @{@"cRe": @-0.123, @"cIm": @0.745, @"zRe": @0, @"zIm": @0, @"radius": @0.6, @"iter": @6}],
             @[@"Julia dendrite", @1, @{@"cRe": @0, @"cIm": @1, @"zRe": @0, @"zIm": @0, @"radius": @0.5, @"iter": @7}],
             @[@"Weierstrass rough", @2, @{@"rough": @0.7, @"scale": @2, @"depth": @9}],
             @[@"Weierstrass bell", @2, @{@"rough": @0.45, @"scale": @3, @"depth": @6}],
             @[@"Takagi", @3, @{@"rough": @0.55, @"depth": @10}],
             @[@"Avalon chaos.con · FRACTAL1", @4, avalonDict(5, 73, 158, 65, -147, @[@[@127, @195, @65], @[@51, @124, @40], @[@83, @108, @50]])],
             @[@"Avalon chaos.con · FRACTAL2", @4, avalonDict(5, 30, 200, 80, 180, @[@[@50, @200, @20], @[@71, @139, @73], @[@75, @155, @63]])],
             @[@"Fern", @4, @{@"mX": @0.2, @"mY": @0.5, @"mR": @0.22, @"mAng": @0, @"daughters": @3, @"gens": @5, @"dd0": @0.6, @"dd1": @0.45, @"dd2": @0.5, @"da0": @0.5, @"da1": @-0.7, @"da2": @0.05}],
             @[@"Spiral", @4, @{@"mX": @0.15, @"mY": @0.8, @"mR": @0.2, @"mAng": @-0.6, @"daughters": @1, @"gens": @8, @"dd0": @0.82, @"da0": @0.55}],
             @[@"Cloud", @4, @{@"mX": @0.5, @"mY": @0.5, @"mR": @0.3, @"mAng": @1, @"daughters": @3, @"gens": @6, @"dd0": @0.55, @"dd1": @0.55, @"dd2": @0.55, @"da0": @2.1, @"da1": @4.2, @"da2": @0.3}],
             @[@"Rising swarm", @4, @{@"mX": @0.1, @"mY": @0.85, @"mR": @0.18, @"mAng": @-0.9, @"daughters": @2, @"gens": @7, @"dd0": @0.7, @"dd1": @0.4, @"da0": @0.3, @"da1": @-0.5}]];
}
- (void)defaults {
    _kind = EDFKMandelbrot;
    _p = [@{@"radius": @0.03, @"iter": @12, @"cRe": @-0.745, @"cIm": @0.113, @"zRe": @0, @"zIm": @0, @"rough": @0.62, @"scale": @2, @"depth": @9,
            @"morph": @1, @"tilt": @0, @"seconds": @2, @"attack": @4, @"level": @0.9, @"note": @48, @"rate": @48000, @"output": @0, @"viewRe": @-0.745, @"viewIm": @0.113, @"zoom": @6,
            @"mX": @0.2, @"mY": @0.5, @"mR": @0.22, @"mAng": @0, @"daughters": @3, @"gens": @5, @"dd0": @0.6, @"dd1": @0.45, @"dd2": @0.5, @"da0": @0.5, @"da1": @-0.7, @"da2": @0.05,
            @"tlen": @120, @"atkS": @300, @"fLo": @80, @"fHi": @4000} mutableCopy];
    _circles.state = _p;
}

- (instancetype)initWithHost:(id<EDGeneratorHost>)host {
    if (!(self = [super init])) return nil;
    _host = host; _sliders = [NSMutableDictionary dictionary]; _vals = [NSMutableDictionary dictionary]; _rowViews = [NSMutableDictionary dictionary];
    [self defaults]; [self buildView];
    return self;
}
- (NSView *)view { return _view; }
- (double)v:(NSString *)k { return _p[k].doubleValue; }
- (void)green:(NSTextField *)t { t.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; t.textColor = EDLineSlider.lineGreen; }
- (NSTextField *)label:(NSString *)t { NSTextField *l = [NSTextField labelWithString:t]; l.font = [NSFont systemFontOfSize:12]; l.textColor = EDTheme.labelWhite; return l; }

- (void)buildView {
    NSPopUpButton *kind = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [kind addItemsWithTitles:@[@"Mandelbrot path", @"Julia path", @"Weierstrass", @"Takagi (blancmange)", @"Avalon circles"]]; kind.target = self; kind.action = @selector(kindPicked:);
    NSPopUpButton *pre = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [pre addItemWithTitle:@"Presets…"]; for (NSArray *a in presetList()) [pre addItemWithTitle:a[0]];
    pre.target = self; pre.action = @selector(presetPicked:);
    NSButton *reset = [NSButton buttonWithTitle:@"Reset" target:self action:@selector(resetAll:)];
    NSStackView *top = [NSStackView stackViewWithViews:@[[self label:@"Fractal"], kind, pre, reset]]; top.spacing = 10;
    NSPopUpButton *out = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [out addItemsWithTitles:@[@"Real", @"Imaginary", @"Magnitude"]]; out.target = self; out.action = @selector(outputPicked:);
    NSPopUpButton *note = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger n = 24; n <= 96; n++) { [note addItemWithTitle:[NSString stringWithFormat:@"%@  (%ld)", noteName(n), (long)n]]; note.lastItem.tag = n; }
    [note selectItemWithTag:48]; note.target = self; note.action = @selector(notePicked:);
    NSPopUpButton *rate = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSNumber *r in @[@32000, @44100, @48000]) { [rate addItemWithTitle:[NSString stringWithFormat:@"%@ Hz", r]]; rate.lastItem.tag = r.integerValue; }
    [rate selectItemWithTag:48000]; rate.target = self; rate.action = @selector(ratePicked:);
    NSStackView *nr = [NSStackView stackViewWithViews:@[[self label:@"Output"], out, [self label:@"Note"], note, [self label:@"Sample rate"], rate]]; nr.spacing = 10; _nrRow = nr;
    _grid = [NSStackView new]; _grid.orientation = NSUserInterfaceLayoutOrientationVertical; _grid.alignment = NSLayoutAttributeLeading; _grid.spacing = 6;
    for (NSArray *r in paramTable()) {
        NSString *k = r[0];
        EDLineSlider *s = [EDLineSlider sliderWithValue:[self v:k] minValue:[r[2] doubleValue] maxValue:[r[3] doubleValue] target:self action:@selector(paramMoved:)]; s.identifier = k;
        [s.widthAnchor constraintEqualToConstant:180].active = YES; _sliders[k] = s;
        NSTextField *v = [self label:@""]; v.alignment = NSTextAlignmentRight; [v.widthAnchor constraintEqualToConstant:60].active = YES; _vals[k] = v; [self green:v];
        NSTextField *t = [self label:r[1]]; [self green:t]; [t.widthAnchor constraintEqualToConstant:128].active = YES;
        NSStackView *row = [NSStackView stackViewWithViews:@[t, s, v]]; row.spacing = 10; [_grid addArrangedSubview:row]; _rowViews[k] = @[row];
    }
    NSTextField *hint = [self label:@"The cycle is a path through the fractal, band-limited so every pitch is alias-free and exactly periodic."];
    hint.textColor = [EDTheme.labelWhite colorWithAlphaComponent:0.6];
    _image = [EDFractalImageView new]; [_image.widthAnchor constraintEqualToConstant:360].active = YES; [_image.heightAnchor constraintEqualToConstant:270].active = YES;
    __weak typeof(self) ws = self; _image.onChange = ^{ [ws imageMoved]; };
    NSTextField *ih = [self label:@"Drag = move the ring · drag the ring = radius · ⇧-drag = move the fractal · wheel = zoom · ⇧-wheel = ring radius"];
    ih.font = [NSFont systemFontOfSize:10]; ih.textColor = [EDLineSlider.lineGreen colorWithAlphaComponent:0.7]; ih.lineBreakMode = NSLineBreakByWordWrapping; ih.maximumNumberOfLines = 3; ih.preferredMaxLayoutWidth = 360;
    _imageBox = [NSStackView stackViewWithViews:@[_image, ih]]; _imageBox.orientation = NSUserInterfaceLayoutOrientationVertical; _imageBox.alignment = NSLayoutAttributeLeading; _imageBox.spacing = 6;
    _circles = [EDCircleTreeView new]; _circles.state = _p; [_circles.widthAnchor constraintEqualToConstant:360].active = YES; [_circles.heightAnchor constraintEqualToConstant:225].active = YES;
    __weak typeof(self) ws2 = self; _circles.onChange = ^{ EDFractalGenerator *me = ws2; [me->_host generatorChanged]; };
    NSButton *drawBtn = [NSButton checkboxWithTitle:@"Draw (print view)" target:self action:@selector(drawToggled:)];
    NSTextField *ch = [self label:@"Each circle is a sound: size = volume, left–right = time, up–down = pitch. Drag white = mother · orange = size/angle · yellow = daughters · ⇧-click = base line horizontal · wheel = size."];
    ch.font = [NSFont systemFontOfSize:10]; ch.textColor = [EDLineSlider.lineGreen colorWithAlphaComponent:0.7]; ch.lineBreakMode = NSLineBreakByWordWrapping; ch.maximumNumberOfLines = 4; ch.preferredMaxLayoutWidth = 360;
    _circleBox = [NSStackView stackViewWithViews:@[_circles, drawBtn, ch]]; _circleBox.orientation = NSUserInterfaceLayoutOrientationVertical; _circleBox.alignment = NSLayoutAttributeLeading; _circleBox.spacing = 6;
    NSStackView *midRow = [NSStackView stackViewWithViews:@[_imageBox, _circleBox, _grid]]; midRow.alignment = NSLayoutAttributeTop; midRow.spacing = 24; midRow.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    EDGenScreen *mid = [EDGenScreen new]; midRow.translatesAutoresizingMaskIntoConstraints = NO; [mid addSubview:midRow];
    [NSLayoutConstraint activateConstraints:@[[midRow.leadingAnchor constraintEqualToAnchor:mid.leadingAnchor], [midRow.trailingAnchor constraintEqualToAnchor:mid.trailingAnchor], [midRow.topAnchor constraintEqualToAnchor:mid.topAnchor], [midRow.bottomAnchor constraintEqualToAnchor:mid.bottomAnchor]]];
    _waveScope = [EDGenScope new]; _waveScope.caption = @"One cycle"; _specScope = [EDGenScope new]; _specScope.spectrum = YES; _specScope.caption = @"Harmonics";
    for (EDGenScope *sc in @[_waveScope, _specScope]) { [sc.widthAnchor constraintEqualToConstant:330].active = YES; [sc.heightAnchor constraintEqualToConstant:90].active = YES; }
    NSStackView *scopes = [NSStackView stackViewWithViews:@[_waveScope, _specScope]]; scopes.spacing = 14; _scopeRow = scopes;
    NSStackView *st = [NSStackView stackViewWithViews:@[top, nr, mid, scopes, hint]]; st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeLeading;
    st.spacing = 18; st.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24); _view = st;
    [self refresh];
}
- (void)drawToggled:(NSButton *)b { _circles.drawMode = b.state == NSControlStateValueOn; _circles.needsDisplay = YES; }
- (void)imageMoved {
    _p[@"radius"] = @(_image.radius); _p[@"viewRe"] = @(_image.viewRe); _p[@"viewIm"] = @(_image.viewIm); _p[@"zoom"] = @(_image.zoom);
    if (_kind == EDFKJulia) { _p[@"zRe"] = @(_image.zRe); _p[@"zIm"] = @(_image.zIm); } else { _p[@"cRe"] = @(_image.cRe); _p[@"cIm"] = @(_image.cIm); }
    [self refresh]; [_host generatorChanged];
}
- (void)updateScopes {
    double *c = [self cycle:512 morph:[self v:@"morph"]]; NSMutableArray *w = [NSMutableArray array], *h = [NSMutableArray array]; double mx = 1e-9, tilt = [self v:@"tilt"]; double mag[128];
    for (int i = 0; i < 512; i++) [w addObject:@(c[i])];
    for (int k = 1; k < 128; k++) { double a = 0, b = 0, ww = 2 * M_PI * k / 512; for (int i = 0; i < 512; i++) { a += c[i] * cos(ww * i); b += c[i] * sin(ww * i); } mag[k] = hypot(a, b) * (tilt != 0 ? pow(k, -tilt) : 1); mx = MAX(mx, mag[k]); }
    for (int k = 1; k < 128; k++) [h addObject:@(mag[k] / mx)];
    free(c); _waveScope.values = w; _specScope.values = h;
}
- (void)refresh {
    BOOL win = _kind == EDFKMandelbrot || _kind == EDFKJulia, circ = _kind == EDFKCircles; _imageBox.hidden = !win; _circleBox.hidden = !circ; _scopeRow.hidden = circ;
    for (NSUInteger i = 0; i < 4; i++) _nrRow.views[i].hidden = circ;   // output and note do not apply to the circle picture
    if (circ) [_circles setNeedsDisplay:YES];
    if (win) { _image.julia = _kind == EDFKJulia; _image.cRe = [self v:@"cRe"]; _image.cIm = [self v:@"cIm"]; _image.zRe = [self v:@"zRe"]; _image.zIm = [self v:@"zIm"]; _image.radius = [self v:@"radius"]; _image.viewRe = [self v:@"viewRe"]; _image.viewIm = [self v:@"viewIm"]; _image.zoom = [self v:@"zoom"]; [_image refreshImage]; }
    if (!circ) [self updateScopes];
    for (NSArray *r in paramTable()) {
        NSString *k = r[0]; _sliders[k].doubleValue = [self v:k]; _vals[k].stringValue = [NSString stringWithFormat:r[5], [self v:k]];
        BOOL show = ([r[4] integerValue] & (1 << _kind)) != 0; for (NSView *w in _rowViews[k]) w.hidden = !show;
    }
}
- (void)kindPicked:(NSPopUpButton *)p {
    _kind = p.indexOfSelectedItem;
    if (_kind == EDFKJulia) { _p[@"viewRe"] = @0; _p[@"viewIm"] = @0; _p[@"zoom"] = @1; } else if (_kind == EDFKMandelbrot) { _p[@"viewRe"] = _p[@"cRe"]; _p[@"viewIm"] = _p[@"cIm"]; _p[@"zoom"] = @4; }
    [self refresh]; [_host generatorChanged]; }
- (void)outputPicked:(NSPopUpButton *)p { _p[@"output"] = @(p.indexOfSelectedItem); [_host generatorChanged]; }
- (void)notePicked:(NSPopUpButton *)p { _p[@"note"] = @(p.selectedItem.tag); [_host generatorChanged]; }
- (void)ratePicked:(NSPopUpButton *)p { _p[@"rate"] = @(p.selectedItem.tag); [_host generatorChanged]; }
- (void)paramMoved:(EDLineSlider *)s { _p[s.identifier] = @(s.doubleValue); [self refresh]; [_host generatorChanged]; }
- (void)presetPicked:(NSPopUpButton *)p {
    if (p.indexOfSelectedItem == 0) return;
    NSArray *a = presetList()[p.indexOfSelectedItem - 1]; _kind = [a[1] integerValue]; [_p addEntriesFromDictionary:a[2]];
    if (_kind == EDFKMandelbrot) { _p[@"viewRe"] = _p[@"cRe"]; _p[@"viewIm"] = _p[@"cIm"]; _p[@"zoom"] = @4; } else if (_kind == EDFKJulia) { _p[@"viewRe"] = @0; _p[@"viewIm"] = @0; _p[@"zoom"] = @1; }
    NSPopUpButton *kp = (NSPopUpButton *)[(NSStackView *)_view.subviews.firstObject views][1]; [kp selectItemAtIndex:_kind];
    [p selectItemAtIndex:0]; [self refresh]; [_host generatorChanged];
}
- (void)resetAll:(id)s {
    [self defaults]; NSStackView *top = (NSStackView *)_view.subviews.firstObject; [(NSPopUpButton *)top.views[1] selectItemAtIndex:0];
    [self refresh]; [_host generatorChanged];
}

// MARK: DSP

- (double)outRe:(double)re im:(double)im {
    switch ((int)[self v:@"output"]) { case 0: return tanh(re * 0.7); case 1: return tanh(im * 0.7); default: return tanh(log(1 + sqrt(re * re + im * im)) - 0.5); }
}
/// One cycle of n points for detail amount t (1 = full), zero mean, peak 1.
- (double *)cycle:(int)n morph:(double)t {
    double *y = calloc((size_t)n, sizeof(double));
    if (_kind == EDFKMandelbrot || _kind == EDFKJulia) {
        double r = [self v:@"radius"] * MAX(0.02, t); int it = MAX(1, (int)llround([self v:@"iter"]));
        for (int i = 0; i < n; i++) {
            double th = 2 * M_PI * i / n, zr, zi, cr, ci;
            if (_kind == EDFKMandelbrot) { zr = 0; zi = 0; cr = [self v:@"cRe"] + r * cos(th); ci = [self v:@"cIm"] + r * sin(th); }
            else { zr = [self v:@"zRe"] + r * cos(th); zi = [self v:@"zIm"] + r * sin(th); cr = [self v:@"cRe"]; ci = [self v:@"cIm"]; }
            for (int k = 0; k < it; k++) { double nr = zr * zr - zi * zi + cr, ni = 2 * zr * zi + ci; zr = nr; zi = ni; if (zr * zr + zi * zi > 1e6) break; }
            y[i] = [self outRe:zr im:zi];
        }
    } else {
        double K = [self v:@"depth"] * t, rough = [self v:@"rough"], b = _kind == EDFKWeierstrass ? MAX(2, round([self v:@"scale"])) : 2;
        for (int k = 0; k < K; k++) {
            double w = pow(rough, k) * MIN(1, K - k), f = pow(b, k); if (f >= n / 2.0) break;
            for (int i = 0; i < n; i++) {
                if (_kind == EDFKWeierstrass) y[i] += w * cos(2 * M_PI * f * i / n);
                else { double x = f * i / n; y[i] += w * fabs(x - round(x)); }
            }
        }
    }
    double mean = 0; for (int i = 0; i < n; i++) mean += y[i]; mean /= n;
    double pk = 1e-12; for (int i = 0; i < n; i++) { y[i] -= mean; pk = MAX(pk, fabs(y[i])); }
    for (int i = 0; i < n; i++) y[i] /= pk;
    return y;
}

/// The circle picture as sound: a time / pitch / volume cloud of triangle-wave events, one-shot (no loop).
- (EDGeneratedSample *)renderCircles {
    double sr = [self v:@"rate"], seconds = [self v:@"seconds"], level = [self v:@"level"];
    NSInteger total = (NSInteger)(seconds * sr), glen = MAX(16, (NSInteger)([self v:@"tlen"] / 1000 * sr)), atk = MAX(1, MIN(glen / 2, (NSInteger)[self v:@"atkS"]));
    double lo = MAX(20, MIN([self v:@"fLo"], [self v:@"fHi"] / 1.2)), hi = MAX([self v:@"fHi"], lo * 1.2), ratio = hi / lo;
    if (total < 64 || total > 8 * 1024 * 1024) return nil;
    float *buf = calloc((size_t)(total + glen + 8), sizeof(float));
    EDCirc *cs = malloc(sizeof(EDCirc) * 4000); int n = growCircles(_p, cs, 4000); int used = 0;
    for (int i = 0; i < n; i++) {
        EDCirc c = cs[i]; if (c.x < 0 || c.x >= kAspect || c.y < 0 || c.y > 1) continue;   // outside the matrix = not converted
        double f = lo * pow(ratio, 1 - c.y), inc = f / sr, ph = 0; float amp = (float)MIN(1, c.r * 4); NSInteger start = (NSInteger)(c.x / kAspect * total); used++;
        for (NSInteger k = 0; k < glen; k++) {
            float env = k < atk ? (float)k / atk : (float)(glen - k) / (glen - atk), tri = (float)(4 * fabs(ph - 0.5) - 1);
            buf[start + k] += tri * env * amp; ph += inc; if (ph >= 1) ph -= 1;
        }
    }
    free(cs);
    if (!used) { free(buf); return nil; }
    float pk = 1e-6f; for (NSInteger i = 0; i < total; i++) pk = MAX(pk, fabsf(buf[i]));
    float g = (float)(0.9 * level) / pk;
    NSMutableData *out = [NSMutableData dataWithLength:(size_t)total * 2]; int16_t *o = out.mutableBytes;
    for (NSInteger i = 0; i < total; i++) { double v = buf[i] * g * 32767.0; o[i] = (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : lrint(v))); }
    free(buf);
    EDGeneratedSample *s = [EDGeneratedSample new]; s.name = @"Fr Circles"; s.sampleRate = (uint32_t)sr; s.left = out; s.right = nil; s.loop = NO;
    return s;
}
- (EDGeneratedSample *)render {
    if (_kind == EDFKCircles) return [self renderCircles];
    double rate = [self v:@"rate"], seconds = [self v:@"seconds"], level = [self v:@"level"], tilt = [self v:@"tilt"];
    NSInteger note = (NSInteger)[self v:@"note"]; double f = 440 * pow(2, (note - 69) / 12.0), P = rate / f;
    double minLoop = MAX(0.25, MIN(seconds, 1.0));
    NSInteger mStart = MAX(1, (NSInteger)ceil(minLoop * f)), bestM = mStart; double bestErr = INFINITY;
    for (NSInteger m = mStart; m < mStart + 60; m++) { double Lm = round(m * P), err = fabs(Lm / m - P) / P; if (err < bestErr) { bestErr = err; bestM = m; } if (err < 2e-5) break; }
    NSInteger L = (NSInteger)llround(bestM * P);
    int hMax = MAX(1, (int)(0.45 * rate / f)); hMax = MIN(hMax, kCycleN / 2 - 1);
    // harmonic analysis of the 2048-point cycle (direct DFT: only hMax bins are needed)
    double *c = [self cycle:kCycleN morph:[self v:@"morph"]];
    double *re = calloc((size_t)hMax + 1, sizeof(double)), *im = calloc((size_t)hMax + 1, sizeof(double));
    for (int h = 1; h <= hMax; h++) {
        double a = 0, b = 0, w = 2 * M_PI * h / kCycleN;
        for (int i = 0; i < kCycleN; i++) { a += c[i] * cos(w * i); b += c[i] * sin(w * i); }
        double amp = 2.0 / kCycleN * (tilt != 0 ? pow(h, -tilt) : 1);
        re[h] = a * amp; im[h] = b * amp;        // x ≈ Σ re·cos(wn) + im·sin(wn)
    }
    free(c);
    double *y = calloc((size_t)L, sizeof(double));
    for (int h = 1; h <= hMax; h++) if (fabs(re[h]) + fabs(im[h]) > 1e-12) {
        double w = 2 * M_PI * (double)(h * bestM) / L, cw = cos(w), sw = sin(w), cc = 1, ss = 0;
        for (NSInteger i = 0; i < L; i++) { y[i] += re[h] * cc + im[h] * ss; double nc = cc * cw - ss * sw; ss = ss * cw + cc * sw; cc = nc; }
    }
    free(re); free(im);
    double pk = 1e-9; for (NSInteger i = 0; i < L; i++) pk = MAX(pk, fabs(y[i]));
    double g = 0.9 * level / pk;
    NSInteger att = (NSInteger)([self v:@"attack"] / 1000 * rate);
    NSInteger introReps = att > 0 ? MAX(1, (NSInteger)ceil((double)att / L)) : 0;
    NSInteger reps = MAX(introReps + 1, (NSInteger)ceil(seconds * rate / L)), total = L * reps;
    if (total > 8 * 1024 * 1024) { free(y); return nil; }
    NSMutableData *out = [NSMutableData dataWithLength:(size_t)total * 2]; int16_t *o = out.mutableBytes;
    for (NSInteger i = 0; i < total; i++) {
        double v = y[i % L] * g * 32767.0; if (i < att) v *= (double)i / att;
        o[i] = (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : lrint(v)));
    }
    free(y);
    EDGeneratedSample *s = [EDGeneratedSample new];
    NSArray *kn = @[@"Mandel", @"Julia", @"Weier", @"Takagi", @"Circles"];
    s.name = [NSString stringWithFormat:@"Fr %@ %@", kn[_kind], noteName(note)]; s.sampleRate = (uint32_t)rate; s.left = out; s.right = nil;
    s.loop = YES; s.loopStart = (NSUInteger)(L * introReps); s.loopEnd = (NSUInteger)(total - 1);
    return s;
}
@end
