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

@interface EDLCDFrameView : NSView
@end
@implementation EDLCDFrameView
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (void)drawRect:(NSRect)r {
    CGFloat w = EDTheme.lcdFrameWidth;
    NSBezierPath *b = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, w / 2, w / 2) xRadius:5 yRadius:5];
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

@implementation EDTheme
+ (NSTableRowView *)lcdRowView { return [EDLCDRowView new]; }
+ (NSColor *)body { return [NSColor colorWithCalibratedRed:0.16 green:0.16 blue:0.165 alpha:1]; }
+ (NSColor *)bodyDark { return [NSColor colorWithCalibratedRed:0.10 green:0.10 blue:0.105 alpha:1]; }
+ (NSColor *)accent { return [NSColor colorWithCalibratedRed:0.80 green:0.09 blue:0.13 alpha:1]; }
+ (NSColor *)lcdBackground { return [NSColor colorWithCalibratedRed:0.28 green:0.50 blue:0.19 alpha:1]; }
+ (NSColor *)lcdInk { return [NSColor colorWithCalibratedRed:0.0 green:0.05 blue:0.06 alpha:1]; }
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
+ (CGFloat)lcdFrameWidth { return 3; }
+ (NSView *)framedLCD:(NSScrollView *)s {
    NSView *box = [NSView new]; box.wantsLayer = YES; box.layer.cornerRadius = 5; box.layer.masksToBounds = YES;
    EDLCDFrameView *f = [EDLCDFrameView new];
    for (NSView *v in @[s, f]) { v.translatesAutoresizingMaskIntoConstraints = NO; [box addSubview:v];
        [NSLayoutConstraint activateConstraints:@[[v.topAnchor constraintEqualToAnchor:box.topAnchor], [v.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
            [v.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:box.trailingAnchor]]]; }
    return box;
}
+ (NSView *)framedLCD:(NSScrollView *)s footer:(NSView *)footer {
    NSView *box = [NSView new]; box.wantsLayer = YES; box.layer.cornerRadius = 5; box.layer.masksToBounds = YES; box.layer.backgroundColor = EDTheme.lcdBackground.CGColor;
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

@implementation EDTheme (LCDKeys)
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
    box.layer.cornerRadius = 10; box.layer.borderColor = NSColor.blackColor.CGColor; box.layer.borderWidth = EDTheme.lcdFrameWidth + 1;
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
+ (BOOL)confirm:(NSString *)message okTitle:(NSString *)ok cancelTitle:(NSString *)cancel { return [self runLCDDialogGlyph:@"?" message:message buttons:@[cancel ?: @"Cancel", ok]] == 1; }
+ (void)notice:(NSString *)message { [self runLCDDialogGlyph:@"!" message:message buttons:@[@"OK"]]; }
@end

@implementation EDLCDSideTab { NSString *_title; }
- (instancetype)initWithTitle:(NSString *)title { if ((self = [super initWithFrame:NSZeroRect])) { _title = [title copy]; } return self; }
- (BOOL)isFlipped { return YES; }
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
    CGFloat cell = MIN(NSWidth(b) - 8, (NSHeight(b) - 16) / n), top = NSMinY(b) + 8;
    cell = MIN(cell, 56);
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:MIN(cell * 0.8, 30)], NSForegroundColorAttributeName: EDTheme.lcdInk};
    for (NSUInteger i = 0; i < n; i++) {
        NSString *ch = [_title substringWithRange:NSMakeRange(i, 1)];
        NSRect c = NSMakeRect(NSMidX(b) - cell / 2, top + i * (cell + 4), cell, cell);
        [EDTheme.lcdBackground setFill]; [[NSBezierPath bezierPathWithRoundedRect:c xRadius:3 yRadius:3] fill];
        NSSize ts = [ch sizeWithAttributes:at];
        [ch drawAtPoint:NSMakePoint(NSMidX(c) - ts.width / 2, NSMidY(c) - ts.height / 2) withAttributes:at];
    }
}
@end
