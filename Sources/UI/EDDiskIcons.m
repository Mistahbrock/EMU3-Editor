#import "EDDiskIcons.h"
#import "EDTheme.h"

@implementation EDDiskItem
@end

@implementation EDDiskIcons { NSInteger _sel; }
- (BOOL)isFlipped { return YES; }
- (void)setItems:(NSArray<EDDiskItem *> *)items { _items = [items copy]; _sel = -1; self.needsDisplay = YES; }
- (NSRect)tileRect:(NSInteger)i {
    const CGFloat w = 190, h = 150, gap = 14; NSInteger per = MAX(1, (NSInteger)((NSWidth(self.bounds) - 20) / (w + gap)));
    return NSMakeRect(14 + (i % per) * (w + gap), 14 + (i / per) * (h + gap), w, h);
}
// pixel-style icons in LCD ink, drawn on a 16 x 14 grid
static void px(NSRect r, int x, int y, int w, int h, CGFloat u) { NSRectFill(NSMakeRect(r.origin.x + x * u, r.origin.y + y * u, w * u, h * u)); }
static void drawIcon(EDDiskKind k, NSRect r) {
    CGFloat u = NSWidth(r) / 16; [EDTheme.lcdInk setFill];
    if (k == EDDiskFloppy) {   // like the sampler's floppy: outer shell, shutter, label
        px(r, 1, 0, 14, 1, u); px(r, 1, 13, 14, 1, u); px(r, 1, 0, 1, 14, u); px(r, 14, 0, 1, 14, u);
        px(r, 4, 1, 8, 5, u); px(r, 6, 2, 2, 3, u);
        px(r, 3, 8, 10, 1, u); px(r, 3, 12, 10, 1, u); px(r, 3, 8, 1, 5, u); px(r, 12, 8, 1, 5, u);
    } else if (k == EDDiskCD) {
        NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(NSMakeRect(r.origin.x, r.origin.y, 14 * u, 14 * u), u, u)]; o.lineWidth = u * 1.2; [EDTheme.lcdInk setStroke]; [o stroke];
        NSBezierPath *i = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(r.origin.x + 5.5 * u, r.origin.y + 5.5 * u, 3 * u, 3 * u)]; i.lineWidth = u; [i stroke];
    } else {   // hard disk: case, platter window, LED
        px(r, 0, 3, 16, 1, u); px(r, 0, 12, 16, 1, u); px(r, 0, 3, 1, 10, u); px(r, 15, 3, 1, 10, u);
        px(r, 3, 6, 10, 1, u); px(r, 3, 9, 10, 1, u); px(r, 3, 6, 1, 4, u); px(r, 12, 6, 1, 4, u);
        px(r, 12, 10, 2, 1, u);
    }
}
- (void)drawRect:(NSRect)dirty {
    NSDictionary *t = @{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: EDTheme.lcdInk};
    NSDictionary *t2 = @{NSFontAttributeName: [EDTheme lcdFont:11], NSForegroundColorAttributeName: [EDTheme.lcdInk colorWithAlphaComponent:0.8]};
    if (!_items.count) {
        NSString *s = @"No disks seen.\\nOpen a disk image with Open Disk, or start the Disk Manager.";
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
        [s drawInRect:NSMakeRect(20, NSHeight(self.bounds) / 2 - 30, NSWidth(self.bounds) - 40, 70) withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: EDTheme.lcdInk, NSParagraphStyleAttributeName: ps}];
        return;
    }
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) {
        NSRect tr = [self tileRect:i]; EDDiskItem *it = _items[i];
        if (i == _sel) { [[EDTheme.lcdInk colorWithAlphaComponent:0.22] setFill]; [[NSBezierPath bezierPathWithRoundedRect:tr xRadius:6 yRadius:6] fill]; }
        NSRect ic = NSMakeRect(NSMidX(tr) - 40, tr.origin.y + 10, 80, 70); drawIcon(it.kind, ic);
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter; ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSMutableDictionary *a1 = [t mutableCopy], *a2 = [t2 mutableCopy]; a1[NSParagraphStyleAttributeName] = ps; a2[NSParagraphStyleAttributeName] = ps;
        NSRect nameBar = NSMakeRect(tr.origin.x + 8, tr.origin.y + 86, tr.size.width - 16, 22);
        [[EDTheme.lcdInk colorWithAlphaComponent:0.35] setFill]; NSRectFillUsingOperation(nameBar, NSCompositingOperationSourceOver);
        [it.title drawInRect:NSInsetRect(nameBar, 3, 2) withAttributes:a1];
        [it.subtitle drawInRect:NSMakeRect(tr.origin.x + 8, tr.origin.y + 114, tr.size.width - 16, 16) withAttributes:a2];
    }
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil]; _sel = -1;
    for (NSInteger i = 0; i < (NSInteger)_items.count; i++) if (NSPointInRect(p, [self tileRect:i])) _sel = i;
    self.needsDisplay = YES;
    if (e.clickCount >= 2 && _sel >= 0 && self.onOpen) self.onOpen(_items[_sel]);
}
@end
