#import "EDDiskIcons.h"
#import "EDTheme.h"

@implementation EDDiskItem
@end

static const CGFloat kTileW = 200, kTileH = 128, kGap = 6, kPad = 14, kRowH = 28, kColMin = 340;

@implementation EDDiskIcons
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) { _selectedIndex = -1; _emptyText = @"No disks seen.\nOpen a disk image with Open Disk, or start the Disk Manager."; }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (EDDiskItem *)selectedItem { return _selectedIndex >= 0 && _selectedIndex < (NSInteger)_items.count ? _items[_selectedIndex] : nil; }
- (void)setItems:(NSArray<EDDiskItem *> *)items { _items = [items copy]; if (_selectedIndex >= (NSInteger)_items.count) _selectedIndex = -1; [self fitToClip]; self.needsDisplay = YES; }
- (void)setSelectedIndex:(NSInteger)i { _selectedIndex = i; [self scrollToSelection]; self.needsDisplay = YES; }
- (void)setListMode:(BOOL)on { if (_listMode == on) return; _listMode = on; [self fitToClip]; [self scrollToSelection]; self.needsDisplay = YES; }
// list view: columns filled top to bottom, as many columns as fit
- (NSInteger)listCols { return MAX(1, (NSInteger)((NSWidth(self.bounds) - 2 * kPad) / kColMin)); }
- (NSInteger)listRows { NSInteger c = [self listCols]; return MAX(1, ((NSInteger)_items.count + c - 1) / c); }
- (NSInteger)perRow { return MAX(1, (NSInteger)((NSWidth(self.bounds) - 2 * kPad + kGap) / (kTileW + kGap))); }
- (NSRect)tileRect:(NSInteger)i {
    if (_listMode) { NSInteger rows = [self listRows]; CGFloat colW = (NSWidth(self.bounds) - 2 * kPad) / [self listCols]; return NSMakeRect(kPad + (i / rows) * colW, 10 + (i % rows) * kRowH, colW - 8, kRowH); }
    NSInteger per = [self perRow];
    return NSMakeRect(kPad + (i % per) * (kTileW + kGap), 10 + (i / per) * (kTileH + kGap), kTileW, kTileH);
}
// the view is the document of a scroll view: as tall as its icons, at least as tall as the window
- (void)viewDidMoveToSuperview {
    NSClipView *c = [self.superview isKindOfClass:NSClipView.class] ? (NSClipView *)self.superview : nil;
    if (c) { c.postsFrameChangedNotifications = YES; [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(fitToClip) name:NSViewFrameDidChangeNotification object:c]; }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)fitToClip {
    NSClipView *c = [self.superview isKindOfClass:NSClipView.class] ? (NSClipView *)self.superview : nil; if (!c) return;
    NSInteger per = [self perRow], rows = (NSInteger)((_items.count + per - 1) / per);
    CGFloat h = MAX(NSHeight(c.bounds), _listMode ? 20 + [self listRows] * kRowH : 20 + rows * (kTileH + kGap));
    if (fabs(NSHeight(self.frame) - h) > 0.5 || fabs(NSWidth(self.frame) - NSWidth(c.bounds)) > 0.5) [self setFrameSize:NSMakeSize(NSWidth(c.bounds), h)];
    self.needsDisplay = YES;
}
- (void)scrollToSelection { if (_selectedIndex >= 0) [self scrollRectToVisible:NSInsetRect([self tileRect:_selectedIndex], -4, -4)]; }

// ── pixel art. '#': ink outline   'o': body (filled in ink when selected)   'x': detail (ink, or the screen colour when selected)
static void art(NSArray<NSString *> *rows, NSPoint o, CGFloat u, BOOL sel) {
    NSColor *ink = EDTheme.lcdInk, *bg = EDTheme.lcdBackground;
    for (NSUInteger y = 0; y < rows.count; y++) for (NSUInteger x = 0; x < rows[y].length; x++) {
        unichar c = [rows[y] characterAtIndex:x];
        if (c == '#') [ink setFill]; else if (c == 'o') { if (!sel) continue; [ink setFill]; } else if (c == 'x') [(sel ? bg : ink) setFill]; else continue;
        NSRectFill(NSMakeRect(o.x + x * u, o.y + y * u, u, u));
    }
}
static void drawIcon(EDDiskKind k, NSRect area, BOOL sel) {
    NSColor *ink = EDTheme.lcdInk, *bg = EDTheme.lcdBackground; CGFloat u = 5;
    if (k == EDDiskHard) {
        NSArray *a = @[@"################", @"#oooooooooooooo#", @"#oxxxxxxxxxxxxo#", @"#ox..........xo#", @"#ox..........xo#", @"#oxxxxxxxxxxxxo#", @"#oooooooooxxooo#", @"#oooooooooooooo#", @"################"];
        art(a, NSMakePoint(NSMidX(area) - 8 * u, NSMinY(area) + 12), u, sel);
    } else if (k == EDDiskFloppy) {
        NSArray *a = @[@"##############", @"#oooxxxxxxxoo#", @"#oooxoooooxoo#", @"#oooxooxxoxoo#", @"#oooxxxxxxxoo#", @"#oooooooooooo#", @"#ooxxxxxxxxoo#", @"#ooxooooooxoo#", @"#ooxooooooxoo#",
                       @"#ooxooooooxoo#", @"#ooxooooooxoo#", @"#oooooooooooo#", @"##############"];
        art(a, NSMakePoint(NSMidX(area) - 7 * u, NSMinY(area) - 2), u, sel);
    } else if (k == EDDiskFolder) {
        NSArray *a = @[@"#####...........", @"#ooooo##########", @"#oooooooooooooo#", @"#oooooooooooooo#", @"#oooooooooooooo#", @"#oooooooooooooo#", @"#oooooooooooooo#", @"#oooooooooooooo#", @"#oooooooooooooo#", @"################"];
        art(a, NSMakePoint(NSMidX(area) - 8 * u, NSMinY(area) + 8), u, sel);
    } else if (k == EDDiskBank) {
        // a little disk label: "E IV" on the top, a rule near the bottom
        NSPoint o = NSMakePoint(NSMidX(area) - 7 * u, NSMinY(area) - 4);
        NSMutableArray *rows = [NSMutableArray array];
        for (int y = 0; y < 15; y++) {
            NSMutableString *r = [NSMutableString stringWithString:(y == 0 || y == 14) ? @"##############" : @"#oooooooooooo#"]; [rows addObject:r];
        }
        void (^set)(int, int) = ^(int x, int y) { [rows[y] replaceCharactersInRange:NSMakeRange(x, 1) withString:@"x"]; };
        for (int y = 2; y <= 6; y++) set(2, y);
        for (int x = 2; x <= 4; x++) { set(x, 2); set(x, 4); set(x, 6); }
        for (int y = 2; y <= 6; y++) { set(6, y); }
        for (int y = 2; y <= 4; y++) { set(8, y); set(11, y); }
        set(9, 5); set(10, 5); set(9, 6); set(10, 6);   // the V
        for (int x = 2; x <= 11; x++) set(x, 10);
        art(rows, o, u, sel);
    } else if (k == EDDiskSample) {
        // the sampler's sample icon: "E III" on top, a framed waveform below
        NSArray *rows = @[@"###.###.###.###", @"#....#...#...#.", @"##...#...#...#.", @"#....#...#...#.", @"###.###.###.###", @"...............", @"###############", @"#oooxooooxoooo#", @"#ooxoxooxoxooo#", @"#oxooxoxooxoxo#", @"#xoooooxoooxox#", @"###############"];
        art(rows, NSMakePoint(NSMidX(area) - 7.5 * u, NSMinY(area) - 2), u, sel);
    } else {   // CD
        CGFloat d = 14 * u; NSRect r = NSMakeRect(NSMidX(area) - d / 2, NSMinY(area) - 2, d, d);
        NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 3, 3)]; if (sel) { [ink setFill]; [o fill]; } o.lineWidth = u * 0.9; [ink setStroke]; [o stroke];
        NSBezierPath *i = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(r) - 1.5 * u, NSMidY(r) - 1.5 * u, 3 * u, 3 * u)]; i.lineWidth = u * 0.8; [(sel ? bg : ink) setStroke]; [i stroke];
    }
}
// small icons for the list view (2 px per cell)
static NSArray<NSString *> *miniArt(EDDiskKind k) {
    switch (k) {
        case EDDiskFolder: return @[@"####.......", @"#.#########", @"#.........#", @"#.........#", @"#.........#", @"###########"];
        case EDDiskBank: case EDDiskFloppy: return @[@"###########", @"#.........#", @"#.xxxxxxx.#", @"#.x.....x.#", @"#.xxxxxxx.#", @"#.........#", @"#...xx....#", @"###########"];
        case EDDiskHard: case EDDiskCD: return @[@"###########", @"#.........#", @"#.xxxxxxx.#", @"#.......xx#", @"#.........#", @"###########"];
        default: return @[@"###########", @"#.........#", @"#..x...x..#", @"#.x.x.x.x.#", @"#x...x...x#", @"#.........#", @"###########"];
    }
}
- (void)drawRect:(NSRect)dirty {
    if (!_items.count) {
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
        [_emptyText drawInRect:NSMakeRect(20, MAX(10, NSHeight(self.superview.bounds) / 2 - 30), NSWidth(self.bounds) - 40, 70) withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: EDTheme.lcdInk, NSParagraphStyleAttributeName: ps}];
        return;
    }
    if (_listMode) {
        for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
            NSRect tr = [self tileRect:i]; if (!NSIntersectsRect(tr, dirty)) continue;
            EDDiskItem *it = _items[i]; BOOL sel = i == _selectedIndex;
            if (sel) { [EDTheme.lcdInk setFill]; NSRectFill(tr); }
            NSArray *mini = miniArt(it.kind); NSMutableArray *fillable = [NSMutableArray array]; for (NSString *r in mini) [fillable addObject:[r stringByReplacingOccurrencesOfString:@"." withString:@"o"]];
            CGFloat iy = tr.origin.y + (kRowH - 2 * mini.count) / 2;
            if (sel) { NSMutableArray *inv = [NSMutableArray array]; for (NSString *r in fillable) [inv addObject:[r stringByReplacingOccurrencesOfString:@"#" withString:@"x"]]; art(inv, NSMakePoint(tr.origin.x + 4, iy), 2, YES); } else art(fillable, NSMakePoint(tr.origin.x + 4, iy), 2, NO);
            NSString *label = it.tag.length ? [NSString stringWithFormat:@"%@  %@", it.tag, it.title] : it.title;
            NSDictionary *a = @{NSFontAttributeName: [EDTheme lcdFont:14], NSForegroundColorAttributeName: sel ? EDTheme.lcdBackground : EDTheme.lcdInk};
            NSSize ts = [label sizeWithAttributes:a]; [label drawAtPoint:NSMakePoint(tr.origin.x + 34, tr.origin.y + (kRowH - ts.height) / 2) withAttributes:a];
            if (it.loop) { NSArray *la = @[@"..####.", @"#.....#", @"#..####", @"#.....#", @"..####."];
                NSMutableArray *fl = [NSMutableArray array]; for (NSString *r in la) [fl addObject:[r stringByReplacingOccurrencesOfString:@"#" withString:@"x"]];
                art(fl, NSMakePoint(tr.origin.x + 34 + ts.width + 8, tr.origin.y + 8), 2, sel); }
        }
        return;
    }
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter; ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        NSRect tr = [self tileRect:i]; if (!NSIntersectsRect(tr, dirty)) continue;
        EDDiskItem *it = _items[i]; BOOL sel = i == _selectedIndex;
        drawIcon(it.kind, NSMakeRect(tr.origin.x, tr.origin.y, tr.size.width, 82), sel);
        NSRect nameBar = NSMakeRect(tr.origin.x + 10, tr.origin.y + 86, tr.size.width - 20, 22);
        if (sel) { [EDTheme.lcdInk setFill]; NSRectFill(nameBar); }
        NSDictionary *a = @{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: sel ? EDTheme.lcdBackground : EDTheme.lcdInk, NSParagraphStyleAttributeName: ps};
        [it.title drawInRect:NSInsetRect(nameBar, 3, 2) withAttributes:a];
        if (it.subtitle.length) [it.subtitle drawInRect:NSMakeRect(tr.origin.x + 8, tr.origin.y + 110, tr.size.width - 16, 16)
            withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:11], NSForegroundColorAttributeName: [EDTheme.lcdInk colorWithAlphaComponent:0.8], NSParagraphStyleAttributeName: ps}];
    }
}
- (void)mouseDown:(NSEvent *)e {
    [self.window makeFirstResponder:self];
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; NSInteger hit = -1;
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) if (NSPointInRect(p, [self tileRect:i])) hit = i;
    _selectedIndex = hit; self.needsDisplay = YES;
    EDDiskItem *it = self.selectedItem; if (!it) return;
    if (e.clickCount >= 2) { if (self.onOpen) self.onOpen(it); } else if (self.onSelect) self.onSelect(it);
}
- (void)keyDown:(NSEvent *)e {
    NSInteger n = (NSInteger)_items.count, per = [self perRow], i = _selectedIndex;
    if (_listMode) {   // down/up move inside a column, left/right jump a column
        unichar lc = e.characters.length ? [e.characters characterAtIndex:0] : 0; NSInteger rows = [self listRows];
        if (n && (lc == NSUpArrowFunctionKey || lc == NSDownArrowFunctionKey || lc == NSLeftArrowFunctionKey || lc == NSRightArrowFunctionKey)) {
            NSInteger step = lc == NSUpArrowFunctionKey ? -1 : lc == NSDownArrowFunctionKey ? 1 : lc == NSLeftArrowFunctionKey ? -rows : rows;
            self.selectedIndex = MAX(0, MIN(n - 1, (i < 0 ? 0 : i) + step)); if (self.selectedItem && self.onSelect) self.onSelect(self.selectedItem); return;
        }
    } unichar c = e.characters.length ? [e.characters characterAtIndex:0] : 0;
    if (!n) { [super keyDown:e]; return; }
    if (c == NSLeftArrowFunctionKey) i = MAX(0, i - 1); else if (c == NSRightArrowFunctionKey) i = MIN(n - 1, i + 1);
    else if (c == NSUpArrowFunctionKey) i = i < 0 ? 0 : MAX(0, i - per); else if (c == NSDownArrowFunctionKey) i = i < 0 ? 0 : MIN(n - 1, i + per);
    else if (e.keyCode == 53) { if (self.onExit) self.onExit(); return; }   // Escape
    else if (c == '\r' || c == '\n' || c == 3) { if (self.selectedItem && self.onOpen) self.onOpen(self.selectedItem); return; }
    else { [super keyDown:e]; return; }
    self.selectedIndex = i; if (self.selectedItem && self.onSelect) self.onSelect(self.selectedItem);
}
@end
