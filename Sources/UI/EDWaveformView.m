#import "EDWaveformView.h"
#import "EDTheme.h"

typedef NS_ENUM(NSInteger, EDDragTarget) { EDDragNone, EDDragLoopStart, EDDragLoopEnd, EDDragOverview };

@implementation EDWaveformView {
    EDDragTarget _drag; NSTrackingArea *_track; NSInteger _hoverFrame;
}

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) { _framesPerPixel = 1; _playhead = -1; _hoverFrame = -1; self.wantsLayer = YES; }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)setSample:(EDSample *)s { _sample = s; _playhead = -1; [self zoomToFit]; }
- (void)setPlayhead:(NSInteger)p { _playhead = p; [self setNeedsDisplay:YES]; }

- (double)xForFrame:(double)fr { return (fr - (double)_visibleStart) / _framesPerPixel; }
- (double)frameForX:(double)x { return (double)_visibleStart + x * _framesPerPixel; }

- (void)clampView {
    NSUInteger n = _sample.frameCount;
    double minFPP = 1.0 / 32.0, maxFPP = MAX(1.0, (double)n / MAX(self.bounds.size.width, 1));
    _framesPerPixel = MIN(MAX(_framesPerPixel, minFPP), maxFPP);
    double visible = _framesPerPixel * self.bounds.size.width;
    double maxStart = MAX(0.0, (double)n - visible);
    _visibleStart = (NSUInteger)MIN(MAX((double)_visibleStart, 0.0), maxStart);
}

- (void)zoomToFit {
    NSUInteger n = _sample.frameCount;
    _visibleStart = 0;
    _framesPerPixel = n ? (double)n / MAX(self.bounds.size.width, 1) : 1;
    [self clampView]; [self setNeedsDisplay:YES];
}
- (void)zoomBy:(double)factor {
    double centre = [self frameForX:self.bounds.size.width / 2];
    _framesPerPixel /= factor;
    double visible = _framesPerPixel * self.bounds.size.width;
    _visibleStart = (NSUInteger)MAX(0.0, centre - visible / 2);
    [self clampView]; [self setNeedsDisplay:YES];
}
- (void)zoomToLoop {
    if (!_sample || _sample.loopEnd <= _sample.loopStart) return;
    double span = (double)(_sample.loopEnd - _sample.loopStart) * 1.2 + 16;
    _framesPerPixel = span / MAX(self.bounds.size.width, 1);
    double visible = _framesPerPixel * self.bounds.size.width;
    double mid = (_sample.loopStart + _sample.loopEnd) / 2.0;
    _visibleStart = (NSUInteger)MAX(0.0, mid - visible / 2);
    [self clampView]; [self setNeedsDisplay:YES];
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self clampView]; }

- (void)drawChannel:(const int16_t *)d n:(NSUInteger)n inRect:(NSRect)r color:(NSColor *)c {
    CGFloat midY = NSMidY(r), half = r.size.height / 2 - 2;
    [c setFill];
    NSBezierPath *line = nil;
    for (CGFloat x = 0; x < r.size.width; x++) {
        double a = [self frameForX:x], b = [self frameForX:x + 1];
        if (a >= n) break;
        NSUInteger i0 = (NSUInteger)MAX(a, 0), i1 = MIN((NSUInteger)ceil(b), n);
        if (i1 <= i0) i1 = MIN(i0 + 1, n);
        int mn = 32767, mx = -32768;
        for (NSUInteger i = i0; i < i1; i++) { if (d[i] < mn) mn = d[i]; if (d[i] > mx) mx = d[i]; }
        CGFloat y0 = midY - (mx / 32768.0) * half, y1 = midY - (mn / 32768.0) * half;
        if (_framesPerPixel < 0.5) {   // zoomed far in: connect sample points
            if (!line) { line = [NSBezierPath bezierPath]; [line moveToPoint:NSMakePoint(r.origin.x + x, y0)]; }
            else [line lineToPoint:NSMakePoint(r.origin.x + x, y0)];
        } else {
            NSRectFill(NSMakeRect(r.origin.x + x, y0, 1, MAX(1, y1 - y0)));
        }
    }
    if (line) { [c setStroke]; [line stroke]; }
}

static const CGFloat kRulerH = 26, kOverviewH = 52;

- (NSRect)waveRect { NSRect b = self.bounds; return NSMakeRect(0, kRulerH, b.size.width, MAX(b.size.height - kRulerH - kOverviewH, 20)); }
- (NSRect)overviewRect { NSRect b = self.bounds; return NSMakeRect(0, b.size.height - kOverviewH + 6, b.size.width, kOverviewH - 8); }

- (void)drawRuler {
    CGFloat w = self.bounds.size.width;
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1] setFill]; NSRectFill(NSMakeRect(0, 0, w, kRulerH));
    [[NSColor colorWithCalibratedWhite:0.28 alpha:1] setFill]; NSRectFill(NSMakeRect(0, kRulerH - 1, w, 1));
    double rate = MAX(_sample.sampleRate, 1);
    double secPerPx = _framesPerPixel / rate, minStep = secPerPx * 90, step = 0.001;
    static const double nice[] = {1, 2, 5};
    for (double dec = 0.0001; dec < 1000; dec *= 10) { BOOL ok = NO; for (int i = 0; i < 3; i++) if (dec * nice[i] >= minStep) { step = dec * nice[i]; ok = YES; break; } if (ok) break; }
    NSDictionary *at = @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular], NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.72 alpha:1]};
    double t0 = [self frameForX:0] / rate, t1 = [self frameForX:w] / rate;
    for (double t = ceil(t0 / step) * step; t <= t1; t += step) {
        CGFloat x = (CGFloat)[self xForFrame:t * rate];
        [[NSColor colorWithCalibratedWhite:0.45 alpha:1] setFill]; NSRectFill(NSMakeRect(x, kRulerH - 9, 1, 8));
        NSString *l = step < 0.01 ? [NSString stringWithFormat:@"%.1f ms", t * 1000] : (step < 1 ? [NSString stringWithFormat:@"%.3f s", t] : [NSString stringWithFormat:@"%.1f s", t]);
        if (step >= 0.01 && step < 1) l = [NSString stringWithFormat:@"%.*f s", step < 0.1 ? 2 : 1, t];
        [l drawAtPoint:NSMakePoint(x + 4, 4) withAttributes:at];
    }
    if (_hoverFrame >= 0) {
        NSString *h = [NSString stringWithFormat:@"frame %ld  ·  %.4f s", (long)_hoverFrame, _hoverFrame / rate];
        NSDictionary *ha = @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: [EDTheme lcdBackground]};
        NSSize sz = [h sizeWithAttributes:ha];
        NSRect r = NSMakeRect(w - sz.width - 18, 3, sz.width + 12, 19);
        [[NSColor colorWithCalibratedRed:0.04 green:0.20 blue:0.38 alpha:1] setFill]; [[NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4] fill];
        [h drawAtPoint:NSMakePoint(r.origin.x + 6, r.origin.y + 2) withAttributes:ha];
    }
}

- (void)drawOverview {
    NSRect o = [self overviewRect]; NSUInteger n = _sample.frameCount;
    [[NSColor colorWithCalibratedRed:0.04 green:0.07 blue:0.10 alpha:1] setFill]; NSRectFill(NSMakeRect(0, o.origin.y - 6, o.size.width, o.size.height + 8));
    [[NSColor colorWithCalibratedWhite:0.28 alpha:1] setFill]; NSRectFill(NSMakeRect(0, o.origin.y - 6, o.size.width, 1));
    const int16_t *d = _sample.leftFrames; CGFloat mid = NSMidY(o), half = o.size.height / 2 - 2;
    [[NSColor colorWithCalibratedRed:0.30 green:0.62 blue:0.78 alpha:1] setFill];
    for (CGFloat x = 0; x < o.size.width; x++) {
        NSUInteger i0 = (NSUInteger)((double)x / o.size.width * n), i1 = MIN((NSUInteger)((double)(x + 1) / o.size.width * n) + 1, n);
        int mn = 32767, mx = -32768; for (NSUInteger i = i0; i < i1; i++) { if (d[i] < mn) mn = d[i]; if (d[i] > mx) mx = d[i]; }
        if (mx < mn) continue;
        NSRectFill(NSMakeRect(x, mid - (mx / 32768.0) * half, 1, MAX(1, (mx - mn) / 32768.0 * half)));
    }
    if (_sample.loopEnabled) {
        CGFloat xs = (CGFloat)_sample.loopStart / n * o.size.width, xe = (CGFloat)_sample.loopEnd / n * o.size.width;
        [[NSColor colorWithCalibratedRed:0.2 green:0.4 blue:0.9 alpha:0.28] setFill]; NSRectFillUsingOperation(NSMakeRect(xs, o.origin.y - 5, xe - xs, o.size.height + 6), NSCompositingOperationSourceOver);
    }
    CGFloat vx = (CGFloat)_visibleStart / n * o.size.width, vw = MIN(_framesPerPixel * self.bounds.size.width / n * o.size.width, o.size.width - vx);
    NSRect vr = NSMakeRect(vx, o.origin.y - 4, MAX(vw, 3), o.size.height + 4);
    [[NSColor colorWithCalibratedWhite:1 alpha:0.10] setFill]; NSRectFillUsingOperation(vr, NSCompositingOperationSourceOver);
    [[NSColor colorWithCalibratedRed:0.75 green:0.92 blue:0.85 alpha:1] setStroke]; NSBezierPath *bp = [NSBezierPath bezierPathWithRect:NSInsetRect(vr, 0.5, 0.5)]; bp.lineWidth = 1.5; [bp stroke];
}

- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithCalibratedRed:0.045 green:0.055 blue:0.07 alpha:1] setFill]; NSRectFill(self.bounds);
    if (!_sample || _sample.frameCount == 0) return;
    NSUInteger n = _sample.frameCount;
    BOOL st = _sample.right != nil;
    NSRect wr = [self waveRect]; CGFloat w = wr.size.width, top = wr.origin.y, h = wr.size.height;
    NSColor *wave = [EDTheme lcdBackground];
    NSRect rl = NSMakeRect(0, top, w, st ? h / 2 : h), rr = NSMakeRect(0, top + h / 2, w, h / 2);

    // loop region tint
    if (_sample.loopEnabled) {
        double xs = [self xForFrame:_sample.loopStart], xe = [self xForFrame:_sample.loopEnd];
        [[NSColor colorWithCalibratedRed:0.12 green:0.32 blue:0.85 alpha:0.20] setFill];
        NSRectFillUsingOperation(NSMakeRect(xs, top, xe - xs, h), NSCompositingOperationSourceOver);
    }
    // amplitude grid (50 %) and zero line(s)
    for (NSValue *v in (st ? @[[NSValue valueWithRect:rl], [NSValue valueWithRect:rr]] : @[[NSValue valueWithRect:rl]])) {
        NSRect r = v.rectValue; CGFloat mid = NSMidY(r), half = r.size.height / 2 - 2;
        [[NSColor colorWithCalibratedWhite:0.15 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, mid - half / 2, w, 1)); NSRectFill(NSMakeRect(0, mid + half / 2, w, 1));
        [[NSColor colorWithCalibratedWhite:0.30 alpha:1] setFill]; NSRectFill(NSMakeRect(0, mid, w, 1));
    }
    [self drawChannel:_sample.leftFrames n:n inRect:rl color:wave];
    if (st) [self drawChannel:_sample.rightFrames n:n inRect:rr color:wave];

    // loop markers
    NSDictionary *attr = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: NSColor.whiteColor};
    for (int k = 0; k < 2; k++) {
        NSUInteger fr = k == 0 ? _sample.loopStart : _sample.loopEnd;
        double x = [self xForFrame:fr];
        if (x < -2 || x > w + 2) continue;
        NSColor *mc = _sample.loopEnabled ? (k == 0 ? [NSColor systemYellowColor] : [NSColor systemOrangeColor]) : NSColor.grayColor;
        [mc setFill]; NSRectFill(NSMakeRect(x - 0.5, top, 1.5, h));
        [(k == 0 ? @"S" : @"E") drawAtPoint:NSMakePoint(x + 4, top + 3) withAttributes:attr];
    }
    if (_playhead >= 0) {
        double x = [self xForFrame:_playhead];
        [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(x, top, 1, h));
    }
    [self drawRuler];
    [self drawOverview];
}

// MARK: interaction

- (void)scrollOverviewTo:(CGFloat)x {
    NSUInteger n = _sample.frameCount; double visible = _framesPerPixel * self.bounds.size.width;
    double start = (double)x / MAX(self.bounds.size.width, 1) * n - visible / 2;
    _visibleStart = (NSUInteger)MAX(0.0, start);
    [self clampView]; [self.window invalidateCursorRectsForView:self]; [self setNeedsDisplay:YES];
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_track) [self removeTrackingArea:_track];
    _track = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_track];
}
- (void)mouseMoved:(NSEvent *)ev {
    NSPoint p = [self convertPoint:ev.locationInWindow fromView:nil];
    NSInteger f = (_sample && p.y < NSMaxY([self waveRect])) ? (NSInteger)MAX(0, MIN([self frameForX:p.x], (double)_sample.frameCount - 1)) : -1;
    if (f != _hoverFrame) { _hoverFrame = f; [self setNeedsDisplayInRect:NSMakeRect(0, 0, self.bounds.size.width, kRulerH)]; }
}
- (void)mouseExited:(NSEvent *)ev { _hoverFrame = -1; [self setNeedsDisplayInRect:NSMakeRect(0, 0, self.bounds.size.width, kRulerH)]; }

- (void)mouseDown:(NSEvent *)ev {
    NSPoint p = [self convertPoint:ev.locationInWindow fromView:nil];
    _drag = EDDragNone;
    if (!_sample) return;
    if (p.y > NSMaxY([self waveRect])) { _drag = EDDragOverview; [self scrollOverviewTo:p.x]; return; }
    double ds = fabs(p.x - [self xForFrame:_sample.loopStart]), de = fabs(p.x - [self xForFrame:_sample.loopEnd]);
    if (MIN(ds, de) <= 7) _drag = ds <= de ? EDDragLoopStart : EDDragLoopEnd;
}
- (void)mouseDragged:(NSEvent *)ev {
    if (_drag == EDDragNone || !_sample) return;
    NSPoint p = [self convertPoint:ev.locationInWindow fromView:nil];
    if (_drag == EDDragOverview) { [self scrollOverviewTo:p.x]; return; }
    double fr = MAX(0, MIN([self frameForX:p.x], (double)_sample.frameCount - 1));
    NSUInteger f = (NSUInteger)llround(fr);
    if (ev.modifierFlags & NSEventModifierFlagOption) f = [self snapToZeroCrossing:f];
    if (_drag == EDDragLoopStart) _sample.loopStart = MIN(f, _sample.loopEnd);
    else _sample.loopEnd = MAX(f, _sample.loopStart);
    [self setNeedsDisplay:YES];
    if (_loopChanged) _loopChanged(NO);
}
- (void)mouseUp:(NSEvent *)ev { if ((_drag == EDDragLoopStart || _drag == EDDragLoopEnd) && _loopChanged) _loopChanged(YES); _drag = EDDragNone; }
- (void)resetCursorRects {
    if (_sample) {
        for (NSUInteger fr : (NSUInteger[]){_sample.loopStart, _sample.loopEnd}) {
            double x = [self xForFrame:fr];
            [self addCursorRect:NSMakeRect(x - 6, [self waveRect].origin.y, 12, [self waveRect].size.height) cursor:NSCursor.resizeLeftRightCursor];
        }
    }
}
- (void)scrollWheel:(NSEvent *)ev {
    if (ev.modifierFlags & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) {
        NSPoint p = [self convertPoint:ev.locationInWindow fromView:nil];
        double anchor = [self frameForX:p.x];
        _framesPerPixel *= exp(-ev.scrollingDeltaY * 0.02);
        [self clampView];
        _visibleStart = (NSUInteger)MAX(0.0, anchor - p.x * _framesPerPixel);
    } else {
        double d = (fabs(ev.scrollingDeltaX) > fabs(ev.scrollingDeltaY) ? ev.scrollingDeltaX : ev.scrollingDeltaY);
        double nv = (double)_visibleStart - d * _framesPerPixel * 3;
        _visibleStart = (NSUInteger)MAX(0.0, nv);
    }
    [self clampView]; [self.window invalidateCursorRectsForView:self]; [self setNeedsDisplay:YES];
}
- (void)magnifyWithEvent:(NSEvent *)ev { [self zoomBy:1 + ev.magnification]; }

- (NSUInteger)snapToZeroCrossing:(NSUInteger)f {
    const int16_t *d = _sample.leftFrames; NSUInteger n = _sample.frameCount;
    for (NSUInteger r = 0; r < 2000; r++) {
        for (int sgn = -1; sgn <= 1; sgn += 2) {
            long i = (long)f + sgn * (long)r;
            if (i < 1 || i >= (long)n) continue;
            if ((d[i - 1] <= 0 && d[i] > 0) || (d[i - 1] >= 0 && d[i] < 0)) return (NSUInteger)i;
        }
    }
    return f;
}
@end
