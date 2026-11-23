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
    dispatch_async(dispatch_get_main_queue(), ^{
        if (p) { [p selectItem:i]; if (p.action) [NSApp sendAction:p.action to:p.target from:p]; }
        else if (i.action) [NSApp sendAction:i.action to:i.target from:i];
    });
}
@end

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
- (NSRect)thumbRect {
    NSRect t = [self trackRect]; CGFloat th = MAX(14, floor(NSHeight(t) * (self.knobProportion > 0 ? self.knobProportion : 1)));
    th = MIN(th, NSHeight(t)); CGFloat v = MAX(0, MIN(1, self.doubleValue));
    CGFloat off = (NSHeight(t) - th) * v;
    return NSMakeRect(0, self.isFlipped ? NSMinY(t) + off : NSMaxY(t) - th - off, NSWidth(t), th);
}
- (NSRect)rectForPart:(NSScrollerPart)part {
    switch (part) {
        case NSScrollerKnobSlot: return [self trackRect];
        case NSScrollerKnob: return self.knobProportion >= 1 ? NSZeroRect : [self thumbRect];
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
static NSColor *ContrastBackground(NSInteger c) {
    CGFloat t = c / 8.0, k = 1 + 0.12 * t;
    return [NSColor colorWithCalibratedRed:MIN(1, 0.28 * k) green:MIN(1, 0.50 * k) blue:MIN(1, 0.19 * k) alpha:1];
}
static NSColor *ContrastInk(NSInteger c) {
    CGFloat t = c / 8.0, f = t < 0 ? -t * 0.65 : 0;
    NSColor *bg = ContrastBackground(c);
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
    v.needsDisplay = YES;
}
+ (NSColor *)lcdBackground { return ContrastBackground(LoadContrast()); }
+ (NSColor *)lcdInk { return ContrastInk(LoadContrast()); }
+ (NSInteger)lcdContrast { return LoadContrast(); }
+ (void)setLcdContrast:(NSInteger)c {
    c = MAX(-8, MIN(7, c)); NSInteger old = LoadContrast(); if (c == old) return;
    NSColor *ob = ContrastBackground(old), *oi = ContrastInk(old), *nb = ContrastBackground(c), *ni = ContrastInk(c);
    sContrast = c;
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
    [NSLayoutConstraint activateConstraints:@[
        [s.topAnchor constraintEqualToAnchor:box.topAnchor], [s.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [s.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [s.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-6],
        fl, [footer.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor constant:-8], [footer.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8],
        [f.topAnchor constraintEqualToAnchor:box.topAnchor], [f.bottomAnchor constraintEqualToAnchor:box.bottomAnchor], [f.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [f.trailingAnchor constraintEqualToAnchor:box.trailingAnchor]]];
    return box;
}
+ (void)styleLCDMenu:(NSMenu *)m {
    m.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    for (NSMenuItem *i in m.itemArray) if (!i.isSeparatorItem) i.view = [[EDLCDMenuItemView alloc] initWithItem:i];
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
    NSTextField *t = [NSTextField wrappingLabelWithString:msg]; t.font = [EDTheme lcdFont:15]; t.textColor = EDTheme.lcdInk;
    t.frame = NSMakeRect(86, 66, W - 86 - 24, H - 66 - 24); t.preferredMaxLayoutWidth = W - 110; [box addSubview:t];
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
- (void)scrollWheel:(NSEvent *)e {
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
