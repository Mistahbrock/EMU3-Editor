#import "EDAlert.h"
#import "EDTheme.h"

// Column caption of an LCD list: a slightly darker strip of the LCD green with bold ink text.
@interface EDLCDHeaderCell : NSTableHeaderCell
@end
@implementation EDLCDHeaderCell
- (void)drawWithFrame:(NSRect)f inView:(NSView *)v {
    [[[EDTheme lcdBackground] shadowWithLevel:0.14] setFill]; NSRectFill(f);
    [[[EDTheme lcdInk] colorWithAlphaComponent:0.35] setFill]; NSRectFill(NSMakeRect(NSMinX(f), NSMaxY(f) - 1, f.size.width, 1));
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: [EDTheme lcdInk]};
    NSSize sz = [self.stringValue sizeWithAttributes:a];
    [self.stringValue drawInRect:NSMakeRect(NSMinX(f) + 6, NSMidY(f) - sz.height / 2, f.size.width - 8, sz.height) withAttributes:a];
}
@end

@interface EDLCDRowView : NSTableRowView
@end
@implementation EDLCDRowView
// A selected row is always a darker patch of the LCD green (a little darker still while the list has focus) and keeps dark ink, never blue with white text.
- (void)drawSelectionInRect:(NSRect)r {
    [[[EDTheme lcdBackground] shadowWithLevel:self.isEmphasized ? 0.32 : 0.2] setFill]; NSRectFill(self.bounds);
}
- (NSBackgroundStyle)interiorBackgroundStyle { return NSBackgroundStyleNormal; }
@end

// Text cell of a cell-based LCD list: never paints its own highlight (the table draws the darker green selection).
@interface EDLCDCell : NSTextFieldCell
@end
@implementation EDLCDCell
- (NSColor *)highlightColorWithFrame:(NSRect)f inView:(NSView *)v { return NSColor.clearColor; }
- (NSBackgroundStyle)backgroundStyle { return NSBackgroundStyleNormal; }
- (void)setBackgroundStyle:(NSBackgroundStyle)s {}
- (void)highlight:(BOOL)flag withFrame:(NSRect)f inView:(NSView *)v {}
- (void)setHighlighted:(BOOL)h { [super setHighlighted:NO]; }
@end

// One row of an LCD context menu: the item's own title and action, drawn in the LCD colours.
@interface EDLCDMenuItemView : NSView
@property (nonatomic, weak) NSMenuItem *item;
@property (nonatomic, weak) NSPopUpButton *popup;   // set for the rows of a popup button's list
@end
@implementation EDLCDMenuItemView { BOOL _hover; }
- (instancetype)initWithItem:(NSMenuItem *)i {
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
    CGFloat w = ceil([i.title sizeWithAttributes:a].width) + 36;
    if (!(self = [super initWithFrame:NSMakeRect(0, 0, w, 24)])) return nil;
    _item = i; self.autoresizingMask = NSViewWidthSizable; return self;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; for (NSTrackingArea *t in self.trackingAreas.copy) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e { _hover = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)e { _hover = NO; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)r {
    BOOL on = _item.enabled;
    [(on && _hover ? [[EDTheme lcdBackground] shadowWithLevel:0.25] : [EDTheme lcdBackground]) setFill]; NSRectFill(self.bounds);
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                        NSForegroundColorAttributeName: on ? [EDTheme lcdInk] : [[EDTheme lcdInk] colorWithAlphaComponent:0.4]};
    NSSize sz = [_item.title sizeWithAttributes:a];
    [_item.title drawAtPoint:NSMakePoint(16, NSMidY(self.bounds) - sz.height / 2) withAttributes:a];
    if (_popup && _item.state == NSControlStateValueOn) [@"✓" drawAtPoint:NSMakePoint(3, NSMidY(self.bounds) - sz.height / 2) withAttributes:a];
}
- (void)mouseUp:(NSEvent *)e {
    if (!_item.enabled) return;
    NSMenuItem *i = _item; NSPopUpButton *p = _popup; [i.menu cancelTracking];
    // Run the action only once the menu's event-tracking loop has ended. A GCD block can fire while the menu is still tracking, and a
    // dialog opened from there (an open/save panel) would start inside that loop and receive no keyboard input.
    [NSRunLoop.mainRunLoop performInModes:@[NSDefaultRunLoopMode] block:^{
        if (p) { [p selectItem:i]; if (p.action) [NSApp sendAction:p.action to:p.target from:p]; }
        else if (i.action) [NSApp sendAction:i.action to:i.target from:i];
    }];
}
@end

// ---- A green LCD pop-up for the key menus. The system menu always adds its own pale padding above and below the items, so the key menus
// (Utils, Browse) open this borderless panel instead: items edge to edge inside a black frame.
@interface EDLCDPopRow : NSView
@property (nonatomic, copy) void (^pick)(NSMenuItem *);
- (instancetype)initWithItem:(NSMenuItem *)i width:(CGFloat)w;
@end
@implementation EDLCDPopRow { BOOL _hover; NSMenuItem *_item; }
- (instancetype)initWithItem:(NSMenuItem *)i width:(CGFloat)w { if ((self = [super initWithFrame:NSMakeRect(0, 0, w, i.isSeparatorItem ? 7 : 24)])) { _item = i; } return self; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas]; for (NSTrackingArea *t in self.trackingAreas.copy) [self removeTrackingArea:t];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e { _hover = YES; [self setNeedsDisplay:YES]; }
- (void)mouseExited:(NSEvent *)e { _hover = NO; [self setNeedsDisplay:YES]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (void)drawRect:(NSRect)r {
    if (_item.isSeparatorItem) { [EDTheme.lcdBackground setFill]; NSRectFill(self.bounds); [[EDTheme.lcdInk colorWithAlphaComponent:0.6] setFill]; NSRectFill(NSMakeRect(6, floor(NSMidY(self.bounds)), NSWidth(self.bounds) - 12, 1)); return; }
    BOOL on = _item.enabled;
    [(on && _hover ? [[EDTheme lcdBackground] shadowWithLevel:0.25] : [EDTheme lcdBackground]) setFill]; NSRectFill(self.bounds);
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: on ? [EDTheme lcdInk] : [[EDTheme lcdInk] colorWithAlphaComponent:0.4]};
    NSSize sz = [_item.title sizeWithAttributes:a];
    [_item.title drawAtPoint:NSMakePoint(16, NSMidY(self.bounds) - sz.height / 2) withAttributes:a];
}
- (void)mouseUp:(NSEvent *)e { if (!_item.isSeparatorItem && _item.enabled && _pick) _pick(_item); }
@end

static NSPanel *gPopPanel; static id gPopMouseMonitor; static id gPopResign;
static void EDClosePop(void) {
    if (gPopMouseMonitor) { [NSEvent removeMonitor:gPopMouseMonitor]; gPopMouseMonitor = nil; }
    if (gPopResign) { [NSNotificationCenter.defaultCenter removeObserver:gPopResign]; gPopResign = nil; }
    [gPopPanel orderOut:nil]; gPopPanel = nil;
}

// A faint reflection on the glass: a soft diagonal sheen over the upper part of the screen, plus a hairline highlight along the top edge.
static void DrawGlare(NSRect b, CGFloat radius) {
    NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:b xRadius:radius yRadius:radius];
    [NSGraphicsContext saveGraphicsState];
    [clip addClip];
    CGFloat top = NSMaxY(b), h = NSHeight(b), w = NSWidth(b);
    NSBezierPath *sheen = [NSBezierPath bezierPath];       // just a hint: a small slanted wedge in the top-left corner (y grows upwards)
    CGFloat gw = MIN(w * 0.30, 330), gh = MIN(h * 0.20, 70);
    [sheen moveToPoint:NSMakePoint(NSMinX(b), top)];
    [sheen lineToPoint:NSMakePoint(NSMinX(b) + gw, top)];
    [sheen lineToPoint:NSMakePoint(NSMinX(b), top - gh)];
    [sheen closePath];
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.12] endingColor:[NSColor colorWithWhite:1 alpha:0.0]];
    [g drawInBezierPath:sheen angle:-45];
    [NSGraphicsContext restoreGraphicsState];
}

@interface EDLCDGlareView : NSView
@end
@implementation EDLCDGlareView
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)r { DrawGlare(self.bounds, 0); }
@end

@interface EDLCDFrameView : NSView
@property (nonatomic) BOOL hideGlare;   // the panel has its own glare on top of everything
@end
@implementation EDLCDFrameView
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (void)drawRect:(NSRect)r {
    CGFloat w = EDTheme.lcdFrameWidth;
    if (!self.hideGlare) DrawGlare(NSInsetRect(self.bounds, w, w), 0);
    NSBezierPath *b = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, w / 2, w / 2) xRadius:0 yRadius:0];
    b.lineWidth = w; [NSColor.blackColor setStroke]; [b stroke];
}
@end

@implementation EDLCDTableView
- (void)highlightSelectionInClipRect:(NSRect)clip {
    BOOL active = self.window.isKeyWindow && self.window.firstResponder == self;
    [[[EDTheme lcdBackground] shadowWithLevel:active ? 0.32 : 0.2] setFill];
    [self.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *stop) { NSRectFill(NSIntersectionRect([self rectOfRow:(NSInteger)r], clip)); }];
}
@end

// MARK: LCD scroll bar

@interface EDLCDScroller : NSScroller
@end
@implementation EDLCDScroller {
    NSTimer *_repeat;
}
// Classic Mac System 1 scroll bar: an arrow box at each end, a dithered track, and a square thumb with a black border.
static const CGFloat kArrowH = 14;
+ (CGFloat)scrollerWidthForControlSize:(NSControlSize)c scrollerStyle:(NSScrollerStyle)st { return 14; }
- (BOOL)isOpaque { return YES; }
- (NSRect)upBox { return NSMakeRect(0, self.isFlipped ? 0 : NSHeight(self.bounds) - kArrowH, NSWidth(self.bounds), kArrowH); }
- (NSRect)downBox { return NSMakeRect(0, self.isFlipped ? NSHeight(self.bounds) - kArrowH : 0, NSWidth(self.bounds), kArrowH); }
- (NSRect)trackRect { NSRect b = self.bounds; return NSMakeRect(0, kArrowH, NSWidth(b), MAX(NSHeight(b) - 2 * kArrowH, 0)); }   // symmetrical, so flipping does not matter
/// Nothing to scroll (the content fits, an empty list): the thumb fills the whole track.
- (BOOL)contentFits {
    NSScrollView *sv = [self.superview isKindOfClass:NSScrollView.class] ? (NSScrollView *)self.superview : nil; NSView *d = sv.documentView;
    if (!d) return self.knobProportion >= 1;
    NSEdgeInsets in = sv.contentInsets; return NSHeight(d.frame) <= NSHeight(sv.contentView.bounds) + in.top + in.bottom + 1;
}
- (NSRect)thumbRect {
    NSRect t = [self trackRect]; if ([self contentFits]) return t; CGFloat th = MAX(14, floor(NSHeight(t) * (self.knobProportion > 0 ? self.knobProportion : 1)));
    th = MIN(th, NSHeight(t)); CGFloat v = MAX(0, MIN(1, self.doubleValue));
    CGFloat off = (NSHeight(t) - th) * v;
    return NSMakeRect(0, self.isFlipped ? NSMinY(t) + off : NSMaxY(t) - th - off, NSWidth(t), th);
}
- (NSRect)rectForPart:(NSScrollerPart)part {
    switch (part) {
        case NSScrollerKnobSlot: return [self trackRect];
        case NSScrollerKnob: return [self thumbRect];
        case NSScrollerDecrementLine: case NSScrollerDecrementPage: return self.isFlipped ? [self upBox] : [self upBox];
        case NSScrollerIncrementLine: case NSScrollerIncrementPage: return [self downBox];
        default: return [super rectForPart:part];
    }
}
- (void)drawRect:(NSRect)r {
    [EDTheme.lcdBackground setFill]; NSRectFill(self.bounds);
    [self drawKnobSlotInRect:[self trackRect] highlight:NO];
    [self drawArrow:[self upBox] up:YES]; [self drawArrow:[self downBox] up:NO];
    [self drawKnob];
}
- (void)drawArrow:(NSRect)box up:(BOOL)up {
    box = NSIntegralRect(NSInsetRect(box, 1, 0));
    [EDTheme.lcdBackground setFill]; NSRectFill(box); [EDTheme.lcdInk setFill]; NSFrameRectWithWidth(box, 1);
    CGFloat cx = NSMidX(box), cy = NSMidY(box);   // pixel triangle
    for (int i = 0; i < 4; i++) { CGFloat w = 1 + 2 * i, y = up ? cy - 3 + i : cy + 3 - i - 1;   // narrow tip first
        NSRectFill(NSMakeRect(round(cx - w / 2), self.isFlipped ? y : (up ? cy + 3 - i - 1 : cy - 3 + i), w, 1)); }
}
- (void)drawKnobSlotInRect:(NSRect)slot highlight:(BOOL)h {
    slot = NSIntegralRect(slot);
    [EDTheme.lcdBackground setFill]; NSRectFill(slot);
    [EDTheme.lcdInk setFill];
    NSRect in = NSInsetRect(slot, 1, 0);
    for (NSInteger y = (NSInteger)NSMinY(in); y < (NSInteger)NSMaxY(in); y++) for (NSInteger x = (NSInteger)NSMinX(in); x < (NSInteger)NSMaxX(in); x++)
        if (((x + y) & 1) == 0) NSRectFill(NSMakeRect(x, y, 1, 1));   // 50% dither, like System 1
}
- (void)drawKnob {
    NSRect k = [self rectForPart:NSScrollerKnob]; if (NSIsEmptyRect(k)) return;
    k = NSIntegralRect(NSInsetRect(k, 1, 0));
    [EDTheme.lcdBackground setFill]; NSRectFill(k); [EDTheme.lcdInk setFill]; NSFrameRectWithWidth(k, 1);   // white-ish square thumb, black border
}
// the arrow boxes scroll by a line, repeating while held
- (void)stepBy:(int)dir {
    NSScrollView *sv = [self.superview isKindOfClass:NSScrollView.class] ? (NSScrollView *)self.superview : nil; if (!sv) return;
    NSClipView *c = sv.contentView; NSRect vis = c.documentVisibleRect; CGFloat step = sv.verticalLineScroll > 0 ? MAX(sv.verticalLineScroll, 20) : 20;
    CGFloat docH = NSHeight(sv.documentView.frame), y = NSMinY(vis) + dir * step * (c.isFlipped ? 1 : -1);
    y = MAX(0, MIN(y, docH - NSHeight(vis))); [c scrollToPoint:NSMakePoint(vis.origin.x, y)]; [sv reflectScrolledClipView:c];
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; int dir = NSPointInRect(p, [self upBox]) ? -1 : (NSPointInRect(p, [self downBox]) ? 1 : 0);
    if (!dir) { [super mouseDown:e]; return; }
    [self stepBy:dir];
    __weak EDLCDScroller *w = self; [_repeat invalidate];
    _repeat = [NSTimer timerWithTimeInterval:0.07 repeats:YES block:^(NSTimer *t) { [w stepBy:dir]; }]; [NSRunLoop.mainRunLoop addTimer:_repeat forMode:NSRunLoopCommonModes];
    NSEvent *n; while ((n = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged untilDate:NSDate.distantFuture inMode:NSEventTrackingRunLoopMode dequeue:YES]) && n.type != NSEventTypeLeftMouseUp) {}
    [_repeat invalidate]; _repeat = nil;
}
@end

static void EDUseLCDScroller(NSView *v) {
    if (![v isKindOfClass:NSScrollView.class]) return;
    NSScrollView *s = (NSScrollView *)v; s.scrollerStyle = NSScrollerStyleLegacy; s.autohidesScrollers = NO;
    if (s.hasVerticalScroller) s.verticalScroller = [[EDLCDScroller alloc] initWithFrame:NSMakeRect(0, 0, 14, 100)];
}

@implementation EDTheme
+ (NSTableRowView *)lcdRowView { return [EDLCDRowView new]; }
+ (NSColor *)body { return [NSColor colorWithCalibratedRed:0.16 green:0.16 blue:0.165 alpha:1]; }
+ (NSColor *)bodyDark { return [NSColor colorWithCalibratedRed:0.10 green:0.10 blue:0.105 alpha:1]; }
+ (NSColor *)accent { return [NSColor colorWithCalibratedRed:0.80 green:0.09 blue:0.13 alpha:1]; }
// LCD contrast: t = contrast / 8. Higher = a paler screen (more difference to the ink); lower = a darker screen and ink that fades into it.
static NSInteger sContrast; static BOOL sContrastLoaded;
static NSInteger LoadContrast(void) {
    if (!sContrastLoaded) {
        sContrastLoaded = YES;
        NSString *v = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerMIDIProfile"][@"contrast"];
        sContrast = MAX(-8, MIN(7, v.integerValue));
    }
    return sContrast;
}
// Screen colour: the stock green turned around the colour wheel in 1/48 steps (Shift + the Contrast control).
static NSInteger sHue; static BOOL sHueLoaded;
static NSInteger LoadHue(void) {
    if (!sHueLoaded) { sHueLoaded = YES; sHue = [NSUserDefaults.standardUserDefaults integerForKey:@"LcdHue"]; }
    return sHue;
}
static NSColor *ContrastBackgroundH(NSInteger c, NSInteger hs) {
    CGFloat t = c / 8.0, k = 1 + 0.12 * t;
    NSColor *g = [NSColor colorWithCalibratedRed:MIN(1, 0.28 * k) green:MIN(1, 0.50 * k) blue:MIN(1, 0.19 * k) alpha:1];
    if (hs == 0) return g;
    CGFloat h, sa, br, al; [g getHue:&h saturation:&sa brightness:&br alpha:&al];
    h = fmod(h + hs / 48.0 + 4, 1.0);
    return [NSColor colorWithCalibratedHue:h saturation:sa brightness:br alpha:1];
}
static NSColor *ContrastBackground(NSInteger c) { return ContrastBackgroundH(c, LoadHue()); }
static NSColor *ContrastInkH(NSInteger c, NSInteger hs) {
    CGFloat t = c / 8.0, f = t < 0 ? -t * 0.65 : 0;
    NSColor *bg = ContrastBackgroundH(c, hs);
    return [NSColor colorWithCalibratedRed:0.0 * (1 - f) + bg.redComponent * f green:0.05 * (1 - f) + bg.greenComponent * f blue:0.06 * (1 - f) + bg.blueComponent * f alpha:1];
}
static BOOL SameColor(NSColor *a, NSColor *b) {
    a = [a colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]; b = [b colorUsingColorSpace:NSColorSpace.genericRGBColorSpace];
    if (!a || !b) return NO;
    return fabs(a.redComponent - b.redComponent) < 0.004 && fabs(a.greenComponent - b.greenComponent) < 0.004 && fabs(a.blueComponent - b.blueComponent) < 0.004 && fabs(a.alphaComponent - b.alphaComponent) < 0.004;
}
static void Recolor(NSView *v, NSColor *oldBg, NSColor *newBg, NSColor *oldInk, NSColor *newInk) {
    if (v.layer) {
        if (v.layer.backgroundColor && SameColor([NSColor colorWithCGColor:v.layer.backgroundColor], oldBg)) v.layer.backgroundColor = newBg.CGColor;
        if (v.layer.borderColor && SameColor([NSColor colorWithCGColor:v.layer.borderColor], oldInk)) v.layer.borderColor = newInk.CGColor;
    }
    if ([v isKindOfClass:NSTextField.class]) {
        NSTextField *t = (NSTextField *)v;
        if (t.textColor && SameColor(t.textColor, oldInk)) t.textColor = newInk;
        if (t.drawsBackground && t.backgroundColor && SameColor(t.backgroundColor, [oldInk colorWithAlphaComponent:0.14])) t.backgroundColor = [newInk colorWithAlphaComponent:0.14];
    }
    if ([v isKindOfClass:NSTableView.class]) {
        NSTableView *tv = (NSTableView *)v;
        if (SameColor(tv.backgroundColor, oldBg)) tv.backgroundColor = newBg;
        tv.gridColor = [newInk colorWithAlphaComponent:0.22];
        [tv reloadData];
    }
    for (NSView *s in v.subviews) Recolor(s, oldBg, newBg, oldInk, newInk);
    if ([v isKindOfClass:NSTabView.class]) for (NSTabViewItem *it in ((NSTabView *)v).tabViewItems) if (it.view) Recolor(it.view, oldBg, newBg, oldInk, newInk);   // pages that are not showing are not subviews, but must change too
    v.needsDisplay = YES;
}
static NSColor *ContrastInk(NSInteger c) { return ContrastInkH(c, LoadHue()); }
+ (NSColor *)lcdBackground { return ContrastBackground(LoadContrast()); }
+ (NSColor *)lcdInk { return ContrastInk(LoadContrast()); }
+ (NSInteger)lcdContrast { return LoadContrast(); }
+ (void)setLcdContrast:(NSInteger)c { [self applyContrast:MAX(-8, MIN(7, c)) hue:LoadHue()]; }
+ (NSInteger)lcdHue { return LoadHue(); }
+ (void)setLcdHue:(NSInteger)h {
    h = ((h % 48) + 48) % 48; if (h > 24) h -= 48;   // wraps around the wheel
    [NSUserDefaults.standardUserDefaults setInteger:h forKey:@"LcdHue"];
    [self applyContrast:LoadContrast() hue:h];
}
+ (void)applyContrast:(NSInteger)c hue:(NSInteger)h {
    NSInteger oc = LoadContrast(), oh = LoadHue(); if (c == oc && h == oh) return;
    NSColor *ob = ContrastBackgroundH(oc, oh), *oi = ContrastInkH(oc, oh), *nb = ContrastBackgroundH(c, h), *ni = ContrastInkH(c, h);
    sContrast = c; sHue = h;
    for (NSWindow *w in NSApp.windows) if (w.contentView) Recolor(w.contentView, ob, nb, oi, ni);
}
+ (NSColor *)labelWhite { return [NSColor colorWithCalibratedWhite:0.93 alpha:1]; }
+ (NSColor *)logoBlue { return [NSColor colorWithCalibratedRed:0.10 green:0.45 blue:0.90 alpha:1]; }
+ (NSFont *)lcdFont:(CGFloat)size {
    NSFont *f = [NSFont fontWithName:@"Menlo-Bold" size:size];
    return f ?: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold];
}
+ (NSFont *)panelFont:(CGFloat)size { return [NSFont systemFontOfSize:size weight:NSFontWeightSemibold]; }
+ (void)styleLCDText:(NSTextField *)f { f.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]; f.textColor = [self lcdInk]; }
+ (NSTextField *)lcdLabel:(NSString *)s { NSTextField *f = [NSTextField labelWithString:s ?: @""]; [self styleLCDText:f]; f.lineBreakMode = NSLineBreakByTruncatingTail; return f; }
+ (void)styleLCDTable:(NSTableView *)t {
    if ([t isKindOfClass:[NSOutlineView class]]) t.style = NSTableViewStylePlain;   // before the colours: a style change resets them
    t.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    t.backgroundColor = [self lcdBackground]; t.usesAlternatingRowBackgroundColors = NO;
    t.gridStyleMask = NSTableViewSolidHorizontalGridLineMask; t.gridColor = [[self lcdInk] colorWithAlphaComponent:0.22];
    for (NSTableColumn *c in t.tableColumns) { EDLCDHeaderCell *h = [[EDLCDHeaderCell alloc] initTextCell:c.title]; c.headerCell = h;
        if (![t isKindOfClass:[NSOutlineView class]]) { EDLCDCell *dc = [[EDLCDCell alloc] initTextCell:@""]; dc.editable = [(NSCell *)c.dataCell isEditable]; dc.drawsBackground = NO; dc.lineBreakMode = NSLineBreakByTruncatingTail; c.dataCell = dc; } }
    t.headerView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];   // dark header text on the green panel
}
+ (CGFloat)lcdFrameWidth { return 1.5; }
+ (NSView *)framedLCD:(NSScrollView *)s {
    EDUseLCDScroller(s);
    NSView *box = [NSView new]; box.wantsLayer = YES; box.layer.cornerRadius = 0; box.layer.masksToBounds = YES;
    EDLCDFrameView *f = [EDLCDFrameView new];
    for (NSView *v in @[s, f]) { v.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:v];
        [NSLayoutConstraint activateConstraints:@[[v.topAnchor constraintEqualToAnchor:box.topAnchor], [v.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
            [v.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:box.trailingAnchor]]]; }
    return box;
}
+ (void)addGlareOver:(NSView *)panel in:(NSView *)container {
    for (NSView *v in panel.subviews) if ([v isKindOfClass:EDLCDFrameView.class]) { ((EDLCDFrameView *)v).hideGlare = YES; v.needsDisplay = YES; }
    EDLCDGlareView *g = [EDLCDGlareView new]; g.translatesAutoresizingMaskIntoConstraints = NO; [container addSubview:g positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[[g.topAnchor constraintEqualToAnchor:panel.topAnchor], [g.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor],
        [g.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [g.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor]]];
}
+ (void)addGlareTo:(NSView *)host {
    EDLCDGlareView *g = [EDLCDGlareView new]; g.translatesAutoresizingMaskIntoConstraints = NO; [host addSubview:g];
    [NSLayoutConstraint activateConstraints:@[[g.topAnchor constraintEqualToAnchor:host.topAnchor], [g.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [g.leadingAnchor constraintEqualToAnchor:host.leadingAnchor], [g.trailingAnchor constraintEqualToAnchor:host.trailingAnchor]]];
}
+ (NSView *)framedLCD:(NSView *)s footer:(NSView *)footer {
    EDUseLCDScroller(s);
    NSView *box = [NSView new]; box.wantsLayer = YES; box.layer.cornerRadius = 0; box.layer.masksToBounds = YES; box.layer.backgroundColor = EDTheme.lcdBackground.CGColor;
    EDLCDFrameView *f = [EDLCDFrameView new];
    for (NSView *v in @[s, footer, f]) { v.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:v]; }
    NSLayoutConstraint *fl = [footer.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8];
    NSView *rule = [NSView new]; rule.wantsLayer = YES; rule.layer.backgroundColor = NSColor.blackColor.CGColor; rule.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:rule];   // thin black line above the keys; the scroller ends on it
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:box.topAnchor], [s.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [s.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [rule.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [rule.trailingAnchor constraintEqualToAnchor:box.trailingAnchor], [rule.heightAnchor constraintEqualToConstant:1], [rule.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-4],
        [s.bottomAnchor constraintEqualToAnchor:rule.topAnchor],
        fl, [footer.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor constant:-8], [footer.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8],
        [f.topAnchor constraintEqualToAnchor:box.topAnchor], [f.bottomAnchor constraintEqualToAnchor:box.bottomAnchor], [f.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [f.trailingAnchor constraintEqualToAnchor:box.trailingAnchor]]];
    return box;
}
/// Shows `m` as the LCD pop-up. `anchor` is in screen coordinates: a button's frame (opens below it, or above when there is no room) or the
/// zero-size rect of a right-click (the corner opens at the pointer).
static void EDShowPop(NSMenu *m, NSRect anchor, NSScreen *screen) {
    EDClosePop(); [m update];   // run the menu's validation so items that cannot work now show greyed out
    NSMutableArray<NSMenuItem *> *items = [NSMutableArray array]; for (NSMenuItem *i in m.itemArray) if (!i.hidden) [items addObject:i];
    for (NSInteger i = (NSInteger)items.count - 1; i > 0; i--) if (items[i].isSeparatorItem && items[i - 1].isSeparatorItem) [items removeObjectAtIndex:i];   // hidden items can leave two rules side by side
    while (items.firstObject.isSeparatorItem) [items removeObjectAtIndex:0]; while (items.lastObject.isSeparatorItem) [items removeLastObject];
    if (!items.count) return;
    NSDictionary *fa = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
    CGFloat w = 0, h = 0; for (NSMenuItem *i in items) { if (!i.isSeparatorItem) w = MAX(w, ceil([i.title sizeWithAttributes:fa].width) + 36); h += i.isSeparatorItem ? 7 : 24; }
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)]; content.wantsLayer = YES;
    content.layer.backgroundColor = EDTheme.lcdBackground.CGColor; content.layer.borderColor = NSColor.blackColor.CGColor; content.layer.borderWidth = 1.5; content.layer.cornerRadius = 4; content.layer.masksToBounds = YES;
    CGFloat yy = h;
    for (NSMenuItem *it in items) {
        EDLCDPopRow *row = [[EDLCDPopRow alloc] initWithItem:it width:w]; yy -= NSHeight(row.frame); row.frame = NSMakeRect(0, yy, w, NSHeight(row.frame));
        row.pick = ^(NSMenuItem *i) { EDClosePop(); [NSRunLoop.mainRunLoop performInModes:@[NSDefaultRunLoopMode] block:^{ if (i.action) [NSApp sendAction:i.action to:i.target from:i]; }]; };
        [content addSubview:row];
    }
    NSRect vis = (screen ?: NSScreen.mainScreen).visibleFrame; BOOL point = NSIsEmptyRect(anchor);
    CGFloat x = MIN(MAX(NSMinX(anchor), NSMinX(vis)), NSMaxX(vis) - w);
    CGFloat below = point ? NSMinY(anchor) - h : NSMinY(anchor) - h - 2, above = point ? NSMinY(anchor) : NSMaxY(anchor) + 2;
    CGFloat y = below >= NSMinY(vis) ? below : above;
    NSPanel *pn = [[NSPanel alloc] initWithContentRect:NSMakeRect(x, y, w, h) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    pn.opaque = NO; pn.backgroundColor = NSColor.clearColor; pn.hasShadow = YES; pn.level = NSPopUpMenuWindowLevel; pn.contentView = content; pn.releasedWhenClosed = NO;
    gPopPanel = pn; [pn orderFront:nil];
    gPopMouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        if (e.type == NSEventTypeKeyDown) { if (e.keyCode == 53) { EDClosePop(); return nil; } return e; }
        if (e.window == gPopPanel) return e;
        EDClosePop(); return nil;   // a click outside only closes the menu
    }];
    gPopResign = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { EDClosePop(); }];
}
+ (void)popUpLCDMenu:(NSMenu *)m fromButton:(NSButton *)b {
    if (!b.window) return;
    EDShowPop(m, [b.window convertRectToScreen:[b convertRect:b.bounds toView:nil]], b.window.screen);
}
/// Right-click (or Control-click) on `v` opens its `menu` as the LCD pop-up instead of the system menu. The view's own -menuForEvent: still runs, so a table
/// selects / remembers the clicked row, and the menu delegate is asked to update the items first.
+ (void)useLCDContextMenuOn:(NSView *)v {
    static NSHashTable<NSView *> *views; static id monitor;
    if (!views) views = [NSHashTable weakObjectsHashTable];
    [views addObject:v];
    if (monitor) return;
    monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskRightMouseDown | NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *e) {
        if (e.type == NSEventTypeLeftMouseDown && !(e.modifierFlags & NSEventModifierFlagControl)) return e;
        NSView *top = e.window.contentView; if (!top) return e;
        NSView *hit = [top hitTest:[top.superview convertPoint:e.locationInWindow fromView:nil]];
        for (NSView *view in views.allObjects) {
            NSView *scope = view.enclosingScrollView ?: view; if (!hit || ![hit isDescendantOf:scope]) continue;
            NSMenu *menu = [view menuForEvent:e]; if (!menu) return e;
            if ([menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:menu];
            NSPoint scr = [e.window convertPointToScreen:e.locationInWindow];
            EDShowPop(menu, NSMakeRect(scr.x, scr.y, 0, 0), e.window.screen);
            return nil;
        }
        return e;
    }];
}
+ (void)styleLCDMenu:(NSMenu *)m {
    m.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    for (NSMenuItem *i in m.itemArray) if (!i.isSeparatorItem) i.view = [[EDLCDMenuItemView alloc] initWithItem:i];
}
+ (void)refreshLCDMenuItem:(NSMenuItem *)i {
    NSView *v = i.view; if (!v) return;
    NSDictionary *a = @{NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]};
    NSRect f = v.frame; f.size.width = ceil([i.title sizeWithAttributes:a].width) + 36; v.frame = f; v.needsDisplay = YES;
}
+ (void)styleLCDPopup:(NSPopUpButton *)p {
    p.menu.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    for (NSMenuItem *i in p.menu.itemArray) { EDLCDMenuItemView *v = [[EDLCDMenuItemView alloc] initWithItem:i]; v.popup = p; i.view = v; }
}
+ (void)styleWindow:(NSWindow *)w {
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}

@end

// MARK: LCD dialogs

@interface EDLCDButton : NSButton
@property (nonatomic) BOOL filled;   // a green key on the dark window: filled LCD green, black outline
@end
@implementation EDLCDButton
- (NSSize)intrinsicContentSize {
    NSSize ts = [self.title sizeWithAttributes:@{NSFontAttributeName: [EDTheme lcdFont:self.font.pointSize > 0 ? self.font.pointSize : 15]}];
    return NSMakeSize(ceil(ts.width) + 28, 28);
}
- (void)setEnabled:(BOOL)e { [super setEnabled:e]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)r {
    NSRect b = NSInsetRect(self.bounds, 2, 2);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:b xRadius:6 yRadius:6];
    BOOL on = self.state == NSControlStateValueOn;
    CGFloat dim = self.enabled ? 1 : 0.45;
    if (self.filled) { [[EDTheme.lcdBackground colorWithAlphaComponent:dim] setFill]; [p fill]; }
    if (on) { [EDTheme.lcdInk setFill]; [p fill]; }
    else if (self.isHighlighted) { [[EDTheme.lcdInk colorWithAlphaComponent:0.25] setFill]; [p fill]; }
    [(self.filled ? NSColor.blackColor : EDTheme.lcdInk) setStroke]; p.lineWidth = 2; [p stroke];
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:self.font.pointSize > 0 ? self.font.pointSize : 15], NSForegroundColorAttributeName: [(on ? EDTheme.lcdBackground : EDTheme.lcdInk) colorWithAlphaComponent:dim]};
    NSSize ts = [self.title sizeWithAttributes:at];
    [self.title drawAtPoint:NSMakePoint(NSMidX(b) - ts.width / 2, NSMidY(b) - ts.height / 2) withAttributes:at];
}
@end

@interface EDLCDDialogPanel : NSPanel
@end
@implementation EDLCDDialogPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)cancelOperation:(id)s { [NSApp stopModalWithCode:NSModalResponseCancel]; }
@end

@interface EDLCDDialogHandler : NSObject
@end
@implementation EDLCDDialogHandler
- (void)pick:(NSButton *)b { [NSApp stopModalWithCode:b.tag + 100]; }
@end

@implementation EDTheme (LCDButtons)
+ (NSButton *)lcdButton:(NSString *)title target:(id)t action:(SEL)a {
    EDLCDButton *b = [[EDLCDButton alloc] initWithFrame:NSMakeRect(0, 0, 90, 30)]; b.title = title; b.target = t; b.action = a; b.bordered = NO;
    b.font = [EDTheme lcdFont:13]; [b setButtonType:NSButtonTypePushOnPushOff]; b.translatesAutoresizingMaskIntoConstraints = NO;
    [b.heightAnchor constraintEqualToConstant:30].active = YES;
    return b;
}
@end

@implementation EDTheme (LCDScreens)
+ (void)styleLCDField:(NSTextField *)t {
    t.font = [EDTheme lcdFont:13]; t.textColor = EDTheme.lcdInk; t.bezeled = NO; t.bordered = NO; t.focusRingType = NSFocusRingTypeNone;
    t.drawsBackground = YES; t.backgroundColor = [EDTheme.lcdInk colorWithAlphaComponent:0.14];
}
+ (NSTextField *)lcdLabel:(NSString *)s size:(CGFloat)pt {
    NSTextField *t = [NSTextField labelWithString:s]; t.font = [EDTheme lcdFont:pt]; t.textColor = EDTheme.lcdInk; return t;
}
+ (NSView *)lcdScreenAround:(NSView *)content {
    NSView *box = [NSView new]; box.wantsLayer = YES; box.layer.backgroundColor = EDTheme.lcdBackground.CGColor; box.layer.cornerRadius = 0;
    box.layer.borderColor = NSColor.blackColor.CGColor; box.layer.borderWidth = EDTheme.lcdFrameWidth;
    content.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:content];
    [NSLayoutConstraint activateConstraints:@[[content.topAnchor constraintEqualToAnchor:box.topAnchor], [content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor]]];
    return box;
}
@end

@implementation EDTheme (LCDKeys)
+ (void)useLCDScroller:(NSScrollView *)s { EDUseLCDScroller(s); }
+ (NSButton *)lcdKey:(NSString *)title target:(id)t action:(SEL)a {
    EDLCDButton *b = [[EDLCDButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 28)]; b.title = title; b.target = t; b.action = a; b.bordered = NO; b.filled = YES;
    b.font = [EDTheme lcdFont:13]; [b setButtonType:NSButtonTypeMomentaryPushIn]; return b;
}
@end

@implementation EDTheme (Dialogs)
+ (NSInteger)runLCDDialogGlyph:(NSString *)glyph message:(NSString *)msg buttons:(NSArray<NSString *> *)titles {
    const CGFloat W = 560, H = 190;
    EDLCDDialogPanel *w = [[EDLCDDialogPanel alloc] initWithContentRect:NSMakeRect(0, 0, W, H) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    w.opaque = NO; w.backgroundColor = NSColor.clearColor; w.hasShadow = YES; w.level = NSModalPanelWindowLevel;
    NSView *box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, H)];
    box.wantsLayer = YES; box.layer.backgroundColor = EDTheme.lcdBackground.CGColor;
    box.layer.cornerRadius = 0; box.layer.borderColor = NSColor.blackColor.CGColor; box.layer.borderWidth = EDTheme.lcdFrameWidth + 1;
    w.contentView = box;
    EDLCDDialogHandler *h = [EDLCDDialogHandler new];
    NSTextField *g = [NSTextField labelWithString:glyph]; g.font = [EDTheme lcdFont:44]; g.textColor = EDTheme.lcdInk; g.frame = NSMakeRect(24, H - 110, 50, 60); [box addSubview:g];
    NSTextField *t = [NSTextField ed_wrappingLabelWithString:msg]; t.font = [EDTheme lcdFont:15]; t.textColor = EDTheme.lcdInk;
    t.frame = NSMakeRect(86, 66, W - 86 - 56, H - 66 - 24); t.preferredMaxLayoutWidth = W - 142; [box addSubview:t];   // stops short of the close box in the corner
    EDLCDButton *x = [[EDLCDButton alloc] initWithFrame:NSMakeRect(W - 14 - 30, H - 14 - 30, 30, 30)]; x.title = @"×"; x.target = h; x.action = @selector(pick:); x.tag = -1; x.bordered = NO;   // close box: same as Esc
    x.toolTip = @"Close"; [box addSubview:x];
    NSInteger n = (NSInteger)titles.count; const CGFloat bw = 130, margin = 24;
    for (NSInteger i = 0; i < n; i++) {
        CGFloat x = n == 1 ? W - margin - bw : margin + i * ((W - 2 * margin - bw) / MAX(n - 1, 1));
        EDLCDButton *b = [[EDLCDButton alloc] initWithFrame:NSMakeRect(x, 16, bw, 38)]; b.title = titles[i]; b.target = h; b.action = @selector(pick:); b.tag = i; b.bordered = NO;
        if (i == n - 1) b.keyEquivalent = @"\r";
        [box addSubview:b];
    }
    NSWindow *parent = NSApp.keyWindow ?: NSApp.mainWindow;
    if (parent) [w setFrameOrigin:NSMakePoint(NSMidX(parent.frame) - W / 2, NSMidY(parent.frame) - H / 2)]; else [w center];
    [w makeKeyAndOrderFront:nil];
    NSModalResponse r = [NSApp runModalForWindow:w];
    [w orderOut:nil];
    (void)h;
    return r >= 100 ? r - 100 : -1;   // Esc = -1
}
+ (NSInteger)choose:(NSString *)message buttons:(NSArray<NSString *> *)titles { return [self runLCDDialogGlyph:@"?" message:message buttons:titles]; }
// standard dialogs (same look as About)
+ (BOOL)confirm:(NSString *)message okTitle:(NSString *)ok cancelTitle:(NSString *)cancel {
    EDAlert *a = [EDAlert new]; a.messageText = message; [a addButtonWithTitle:ok ?: @"OK"]; [a addButtonWithTitle:cancel ?: @"Cancel"];
    return [a runModal] == NSAlertFirstButtonReturn;
}
+ (void)notice:(NSString *)message { EDAlert *a = [EDAlert new]; a.messageText = message; [a addButtonWithTitle:@"OK"]; [a runModal]; }
@end

@implementation EDLCDSideTab { NSString *_title; }
- (instancetype)initWithTitle:(NSString *)title { if ((self = [super initWithFrame:NSZeroRect])) { _title = [title copy]; } return self; }
- (BOOL)isFlipped { return YES; }
- (void)setTitleString:(NSString *)t { _title = [t copy]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)dirty {
    NSRect b = NSInsetRect(self.bounds, 1.5, 1.5);
    NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:b xRadius:3 yRadius:3];
    [EDTheme.lcdBackground setFill]; [frame fill];
    [NSGraphicsContext saveGraphicsState]; [frame addClip];
    // cross-hatch like the LCD's dithered strip
    [[EDTheme.lcdInk colorWithAlphaComponent:0.55] setFill];
    for (CGFloat y = NSMinY(b); y < NSMaxY(b); y += 3) for (CGFloat x = NSMinX(b) + (fmod(y - NSMinY(b), 6) < 3 ? 0 : 1.5); x < NSMaxX(b); x += 3) NSRectFill(NSMakeRect(x, y, 1.5, 1.5));
    [NSGraphicsContext restoreGraphicsState];
    [NSColor.blackColor setStroke]; frame.lineWidth = EDTheme.lcdFrameWidth; [frame stroke];
    NSUInteger n = _title.length; if (!n) return;
    CGFloat cell = MIN(NSWidth(b) - 4, (NSHeight(b) - 16) / n), top = NSMinY(b) + 8;
    cell = MIN(cell, 60);
    CGFloat fs = MIN(cell * 0.95, 38);
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
    // the dotted pattern surrounds each letter: a halo in the LCD colour, then the ink letter on top
    NSDictionary *halo = @{NSFontAttributeName: [EDTheme lcdFont:fs], NSStrokeWidthAttributeName: @(14), NSStrokeColorAttributeName: EDTheme.lcdBackground, NSForegroundColorAttributeName: EDTheme.lcdBackground, NSParagraphStyleAttributeName: ps};
    NSDictionary *ink = @{NSFontAttributeName: [EDTheme lcdFont:fs], NSForegroundColorAttributeName: EDTheme.lcdInk, NSParagraphStyleAttributeName: ps};
    for (NSUInteger i = 0; i < n; i++) {
        NSString *ch = [_title substringWithRange:NSMakeRange(i, 1)];
        NSSize ts = [ch sizeWithAttributes:ink];
        NSRect c = NSMakeRect(NSMinX(b), top + i * (cell + 6) + (cell - ts.height) / 2, NSWidth(b), ts.height);
        [ch drawInRect:c withAttributes:halo];
        [ch drawInRect:c withAttributes:ink];
    }
}
@end


@implementation EDWheelPopUp {
    CGFloat _acc;
}
- (BOOL)isContrast { return [self.identifier isEqual:@"contrast"]; }
- (void)resetContrast {
    [EDTheme setLcdHue:0];
    NSInteger i = [self indexOfItemWithTitle:@"+0"]; if (i >= 0) { [self selectItemAtIndex:i]; [self sendAction:self.action to:self.target]; }
}
// Contrast: a double click sets it (and the screen colour) back to the default; the menu opens after the double-click time
- (void)mouseDown:(NSEvent *)e {
    if (![self isContrast] || !self.isEnabled) { [super mouseDown:e]; return; }
    if (e.clickCount >= 2) { [self resetContrast]; return; }
    NSEvent *up = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate dateWithTimeIntervalSinceNow:0.25] inMode:NSEventTrackingRunLoopMode dequeue:YES];
    if (!up) { [super mouseDown:e]; return; }    // held down: the menu as usual
    NSEvent *dn = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDown untilDate:[NSDate dateWithTimeIntervalSinceNow:NSEvent.doubleClickInterval] inMode:NSEventTrackingRunLoopMode dequeue:YES];
    if (dn) { [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp untilDate:[NSDate dateWithTimeIntervalSinceNow:0.3] inMode:NSEventTrackingRunLoopMode dequeue:YES]; [self resetContrast]; return; }
    [self performClick:nil];
}
- (void)scrollWheel:(NSEvent *)e {
    if ([self isContrast] && (e.modifierFlags & NSEventModifierFlagShift) && self.isEnabled) {   // Shift + wheel: the colour of the green screens
        CGFloat d = e.scrollingDeltaY ?: e.scrollingDeltaX; if (d == 0) return;
        if (e.phase == NSEventPhaseBegan || e.phase == NSEventPhaseMayBegin) _acc = 0;
        _acc += e.hasPreciseScrollingDeltas ? d : (d > 0 ? 1 : -1);
        CGFloat step = e.hasPreciseScrollingDeltas ? 10 : 1;
        while (fabs(_acc) >= step) { NSInteger dir = _acc > 0 ? 1 : -1; _acc -= dir * step; [EDTheme setLcdHue:EDTheme.lcdHue + dir]; }
        return;
    }
    if (!self.isEnabled || self.numberOfItems < 2) { [super scrollWheel:e]; return; }
    CGFloat dy = e.scrollingDeltaY;
    if (dy == 0) { [super scrollWheel:e]; return; }
    // a mouse wheel click = one entry, whatever its acceleration; trackpads send many small deltas, so those accumulate
    CGFloat step = e.hasPreciseScrollingDeltas ? 10 : 1;
    if (e.phase == NSEventPhaseBegan || e.phase == NSEventPhaseMayBegin) _acc = 0;
    _acc += e.hasPreciseScrollingDeltas ? dy : (dy > 0 ? 1 : -1);
    while (fabs(_acc) >= step) {
        NSInteger dir = _acc > 0 ? 1 : -1; _acc -= dir * step;
        NSInteger i = self.indexOfSelectedItem + dir;
        while (i >= 0 && i < self.numberOfItems && ![self itemAtIndex:i].isEnabled) i += dir;
        if (i < 0 || i >= self.numberOfItems) { _acc = 0; break; }
        [self selectItemAtIndex:i];
        [self sendAction:self.action to:self.target];
    }
}
@end

@implementation NSTextField (EDLabels)
+ (instancetype)ed_wrappingLabelWithString:(NSString *)s { NSTextField *f = [NSTextField wrappingLabelWithString:s]; f.selectable = NO; return f; }
@end
