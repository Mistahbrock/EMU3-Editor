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
+ (NSColor *)lcdBackground { return [NSColor colorWithCalibratedRed:0.43 green:0.74 blue:0.50 alpha:1]; }
+ (NSColor *)lcdInk { return [NSColor colorWithCalibratedRed:0.02 green:0.14 blue:0.33 alpha:1]; }
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
+ (void)styleWindow:(NSWindow *)w {
    w.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
}
@end
