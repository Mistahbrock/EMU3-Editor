#import "EDPresetEditor.h"
#import "EDPresetLCD.h"
#import "EDPreset+Params.h"
#import "EDTheme.h"
#import "EDPlayer.h"

// outline node: the preset, one of its voices, or one sample reference of a voice
@interface EDPNode : NSObject
@property (nonatomic) NSInteger voice, ref;       // -1 = not applicable
@property (nonatomic) NSInteger lo, hi;           // key range (MIDI notes), -1 = none
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSMutableArray<EDPNode *> *children;
@end
@implementation EDPNode
- (instancetype)init { if ((self = [super init])) { _lo = _hi = -1; } return self; }
@end

// one row of the parameter table: a group heading or a parameter
@interface EDPRow : NSObject
@property (nonatomic, copy) NSString *group;
@property (nonatomic, strong, nullable) EDParam *param;
@end
@implementation EDPRow @end


// MARK: key map — voices / sample references drawn as bars across a keyboard

@interface EDKeyMapView : NSView
@property (nonatomic, copy) NSArray<NSDictionary *> *bars;                 // @{lo, hi, label, node, selected}
@property (nonatomic, copy) void (^picked)(id node);
@property (nonatomic, copy) void (^keyDown)(int key);                      // the on-screen keyboard was pressed / dragged to a new key
@property (nonatomic, copy) void (^keyUp)(void);
@property (nonatomic) int pressedKey;                                       // -1 when none
@end
@implementation EDKeyMapView
- (BOOL)isFlipped { return YES; }
- (CGFloat)xForKey:(CGFloat)k { return 8 + k / 128.0 * (self.bounds.size.width - 16); }
- (NSRect)barRect:(NSUInteger)i {
    CGFloat pianoH = 26, top = 6, avail = self.bounds.size.height - pianoH - top - 4;
    CGFloat rowH = MIN(20, avail / MAX(self.bars.count, 1));
    NSDictionary *b = self.bars[i];
    CGFloat x0 = [self xForKey:[b[@"lo"] doubleValue]], x1 = [self xForKey:[b[@"hi"] doubleValue] + 1];
    return NSMakeRect(x0, top + i * rowH, MAX(x1 - x0, 3), MAX(rowH - 2, 3));
}
- (void)drawRect:(NSRect)dirty {
    NSColor *bg = [EDTheme lcdBackground], *ink = [EDTheme lcdInk];
    [bg setFill]; NSRectFill(self.bounds);
    CGFloat H = self.bounds.size.height, pianoH = 26, py = H - pianoH;
    // octave guides: faint dotted ink
    [[ink colorWithAlphaComponent:0.28] setFill];
    for (int n = 0; n < 128; n += 12) for (CGFloat y = 0; y < py; y += 4) NSRectFill(NSMakeRect([self xForKey:n], y, 1, 2));
    // bars: outlined in ink, the selected one solid
    for (NSUInteger i = 0; i < self.bars.count; i++) {
        NSDictionary *b = self.bars[i]; NSRect r = [self barRect:i]; BOOL sel = [b[@"selected"] boolValue];
        r = NSIntegralRect(r);
        [ink setFill]; NSRectFill(r);
        if (!sel) { [bg setFill]; NSRectFill(NSInsetRect(r, 1, 1)); [[ink colorWithAlphaComponent:0.18] setFill]; NSRectFill(NSInsetRect(r, 1, 1)); }
        if (r.size.height >= 12 && r.size.width > 60) {
            NSString *l = b[@"label"]; NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByTruncatingTail;
            [l drawInRect:NSInsetRect(r, 5, 0) withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:10],
                NSForegroundColorAttributeName: sel ? bg : ink, NSParagraphStyleAttributeName: ps}];
        }
    }
    // keyboard: white keys are LCD background with ink edges, black keys solid ink
    static const BOOL black[12] = {0,1,0,1,0,0,1,0,1,0,1,0};
    CGFloat kw = ([self xForKey:128] - [self xForKey:0]) / 128;
    [ink setFill]; NSRectFill(NSMakeRect(0, py - 1, self.bounds.size.width, 1));
    for (int n = 0; n < 128; n++) {
        if (black[n % 12]) continue;
        NSRect k = NSMakeRect([self xForKey:n], py, kw * (n % 12 == 4 || n % 12 == 11 ? 1 : 1.5), pianoH);
        [ink setFill]; NSRectFill(NSMakeRect(NSMaxX(k) - 1, py, 1, pianoH));
    }
    for (int n = 0; n < 128; n++) {
        if (!black[n % 12]) continue;
        [ink setFill]; NSRectFill(NSMakeRect([self xForKey:n], py, kw, pianoH * 0.62));
    }
    NSDictionary *at = @{NSFontAttributeName: [EDTheme lcdFont:8], NSForegroundColorAttributeName: ink};
    for (int n = 0; n < 128; n += 12) [[EDParam noteName:n] drawAtPoint:NSMakePoint([self xForKey:n] + 1, py + pianoH - 11) withAttributes:at];
    // selected range marker on the keyboard
    for (NSDictionary *b in self.bars) if ([b[@"selected"] boolValue]) {
        [ink setFill]; NSRectFill(NSMakeRect([self xForKey:[b[@"lo"] doubleValue]], py - 4, [self xForKey:[b[@"hi"] doubleValue] + 1] - [self xForKey:[b[@"lo"] doubleValue]], 3));
    }
    if (self.pressedKey >= 0) {   // the key being played: inverted
        [[ink colorWithAlphaComponent:0.55] setFill];
        NSRectFillUsingOperation(NSMakeRect([self xForKey:self.pressedKey], py, MAX([self xForKey:self.pressedKey + 1] - [self xForKey:self.pressedKey], 3), pianoH), NSCompositingOperationSourceOver);
    }
    [ink setFill]; NSFrameRectWithWidth(self.bounds, 2);
}
- (int)keyAtPoint:(NSPoint)p {
    CGFloat w = self.bounds.size.width - 16; int k = (int)floor((p.x - 8) / w * 128);
    return MAX(0, MIN(127, k));
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (p.y >= self.bounds.size.height - 26) { self.pressedKey = [self keyAtPoint:p]; self.needsDisplay = YES; if (self.keyDown) self.keyDown(self.pressedKey); return; }
    for (NSUInteger i = 0; i < self.bars.count; i++) if (NSPointInRect(p, NSInsetRect([self barRect:i], 0, -1)) && self.picked) { self.picked(self.bars[i][@"node"]); return; }
}
- (void)mouseDragged:(NSEvent *)e {
    if (self.pressedKey < 0) return;
    int k = [self keyAtPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    if (k != self.pressedKey) { self.pressedKey = k; self.needsDisplay = YES; if (self.keyDown) self.keyDown(k); }
}
- (void)mouseUp:(NSEvent *)e {
    if (self.pressedKey < 0) return;
    self.pressedKey = -1; self.needsDisplay = YES; if (self.keyUp) self.keyUp();
}
@end

// The caption row above the bank samples: drag it up or down to give the list more or less room.
@interface EDHeightGrip : NSView
@property (strong) NSLayoutConstraint *target;
@property CGFloat minH, maxH;
@end
@implementation EDHeightGrip { CGFloat _startH; NSPoint _startP; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.resizeUpDownCursor]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (void)mouseDown:(NSEvent *)e { _startH = _target.constant; _startP = e.locationInWindow; }
- (void)mouseDragged:(NSEvent *)e {
    _target.constant = MAX(_minH, MIN(_maxH, _startH + (e.locationInWindow.y - _startP.y)));   // window y grows upward: dragging up makes the list taller
    [self.window invalidateCursorRectsForView:self];
}
- (void)drawRect:(NSRect)r {
    [[NSColor.secondaryLabelColor colorWithAlphaComponent:0.5] setFill];
    for (int i = 0; i < 2; i++) [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(NSMaxX(self.bounds) - 40, NSMidY(self.bounds) + 3 + i * 4, 28, 2) xRadius:0 yRadius:0] fill];
}
@end

// "Fit presets to memory": lists every preset with its size, ticks duplicates or the largest ones, and removes the ticked ones (one undo step).
@interface EDFitPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithEditor:(EDPresetEditor *)ed limitK:(double)limit;
- (void)present;
@end
@implementation EDFitPanel {
    __weak EDPresetEditor *_ed; double _limit; NSTableView *_table; NSTextField *_summary; NSProgressIndicator *_bar; NSMutableSet<EDPreset *> *_marked;
}
- (instancetype)initWithEditor:(EDPresetEditor *)ed limitK:(double)limit {
    NSPanel *w = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 560, 600) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Fit Presets to Memory"; w.releasedWhenClosed = NO; w.minSize = NSMakeSize(480, 400);
    if ((self = [super initWithWindow:w])) { _ed = ed; _limit = limit; _marked = [NSMutableSet set]; [self build]; }
    return self;
}
- (NSArray<EDPreset *> *)presets { return _ed.bank.presets ?: @[]; }
- (double)totalK { double t = 0; for (EDPreset *p in self.presets) t += p.raw.length / 1024.0; return t; }
- (double)markedK { double t = 0; for (EDPreset *p in self.presets) if ([_marked containsObject:p]) t += p.raw.length / 1024.0; return t; }
- (void)build {
    NSTextField *intro = [NSTextField wrappingLabelWithString:@"The sampler keeps all presets of a bank in its preset memory. Tick the presets to remove (duplicates and the largest are suggested), and watch the total. Removing is undoable with Edit ▸ Undo; the samples are kept."];
    intro.font = [NSFont systemFontOfSize:11]; intro.textColor = NSColor.secondaryLabelColor; intro.preferredMaxLayoutWidth = 520;
    _summary = [NSTextField wrappingLabelWithString:@""]; _summary.font = [NSFont boldSystemFontOfSize:13]; _summary.preferredMaxLayoutWidth = 520;
    _bar = [NSProgressIndicator new]; _bar.style = NSProgressIndicatorStyleBar; _bar.indeterminate = NO; _bar.minValue = 0; _bar.translatesAutoresizingMaskIntoConstraints = NO;
    _table = [NSTableView new]; _table.dataSource = self; _table.delegate = self; _table.rowHeight = 22; _table.usesAlternatingRowBackgroundColors = YES;
    for (NSArray *c in @[@[@"tick", @"", @30], @[@"num", @"#", @44], @[@"name", @"Preset", @260], @[@"kb", @"Size (KB)", @90]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_table addTableColumn:col]; }
    NSScrollView *sv = [NSScrollView new]; sv.documentView = _table; sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder; sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv.heightAnchor constraintGreaterThanOrEqualToConstant:260].active = YES;
    NSButton *dup = [NSButton buttonWithTitle:@"Tick Duplicates" target:self action:@selector(tickDuplicates:)], *big = [NSButton buttonWithTitle:@"Tick Largest Until It Fits" target:self action:@selector(tickLargest:)],
        *clr = [NSButton buttonWithTitle:@"Clear Ticks" target:self action:@selector(clearTicks:)];
    dup.toolTip = @"Presets that are identical to another one apart from name and number: all but the lowest-numbered copy are ticked.";
    big.toolTip = @"Ticks the biggest presets, one after another, until what is left fits the preset memory.";
    NSStackView *r1 = [NSStackView stackViewWithViews:@[dup, big, clr]]; r1.spacing = 8;
    NSButton *rm = [NSButton buttonWithTitle:@"Remove Ticked" target:self action:@selector(removeTicked:)], *close = [NSButton buttonWithTitle:@"Close" target:self.window action:@selector(performClose:)];
    close.keyEquivalent = @"\e";
    NSView *sp = [NSView new]; [sp setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *r2 = [NSStackView stackViewWithViews:@[rm, sp, close]]; r2.spacing = 8;
    NSStackView *root = [NSStackView stackViewWithViews:@[intro, _summary, _bar, sv, r1, r2]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeLeading; root.spacing = 12; root.edgeInsets = NSEdgeInsetsMake(24, 20, 20, 20);
    [sv.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-40].active = YES; [_bar.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-40].active = YES; [r2.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-40].active = YES;
    [EDTheme styleWindow:self.window]; self.window.contentView = root;
}
- (void)present { [_marked removeAllObjects]; [_table reloadData]; [self updateSummary]; [self.window center]; [self showWindow:nil]; }
- (void)updateSummary {
    double total = self.totalK, after = total - self.markedK; NSUInteger n = 0; for (EDPreset *p in self.presets) if ([_marked containsObject:p]) n++;
    NSString *fit = after <= _limit ? [NSString stringWithFormat:@"fits (%.0f K to spare)", _limit - after] : [NSString stringWithFormat:@"%.0f K too much", after - _limit];
    _summary.stringValue = [NSString stringWithFormat:@"%lu presets use %.0f K of %.0f K preset memory.%@", (unsigned long)self.presets.count, total, _limit,
        n ? [NSString stringWithFormat:@"  After removing the %lu ticked: %.0f K, %@.", (unsigned long)n, after, fit] : (total <= _limit ? @"  They fit." : @"")];
    _bar.maxValue = MAX(MAX(total, _limit), 1); _bar.doubleValue = after;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)self.presets.count; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    EDPreset *p = self.presets[r]; NSString *k = c.identifier;
    if ([k isEqual:@"tick"]) { NSButton *b = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggle:)]; b.tag = r; b.state = [_marked containsObject:p] ? NSControlStateValueOn : NSControlStateValueOff; return b; }
    NSTextField *l = [NSTextField labelWithString:[k isEqual:@"num"] ? [NSString stringWithFormat:@"%u", p.number] : ([k isEqual:@"name"] ? p.name : [NSString stringWithFormat:@"%.1f", p.raw.length / 1024.0])];
    if ([k isEqual:@"kb"]) l.alignment = NSTextAlignmentRight; return l;
}
- (void)toggle:(NSButton *)b { EDPreset *p = self.presets[b.tag]; if (b.state == NSControlStateValueOn) [_marked addObject:p]; else [_marked removeObject:p]; [self updateSummary]; }
- (void)clearTicks:(id)s { [_marked removeAllObjects]; [_table reloadData]; [self updateSummary]; }
- (void)tickDuplicates:(id)s {
    NSMutableDictionary<NSData *, EDPreset *> *first = [NSMutableDictionary dictionary]; NSUInteger skipped = 0;
    for (EDPreset *p in self.presets) {   // the first 18 bytes are the number and the name; everything after is the preset itself
        if (p.raw.length <= 18) continue; NSData *key = [p.raw subdataWithRange:NSMakeRange(18, p.raw.length - 18)];
        if (first[key]) { [_marked addObject:p]; skipped++; } else first[key] = p; }
    [_table reloadData]; [self updateSummary]; if (!skipped) _summary.stringValue = [_summary.stringValue stringByAppendingString:@"  No duplicates found."];
}
- (void)tickLargest:(id)s {
    [_marked removeAllObjects]; double after = self.totalK;
    for (EDPreset *p in [self.presets sortedArrayUsingComparator:^NSComparisonResult(EDPreset *a, EDPreset *b) { return a.raw.length < b.raw.length ? NSOrderedDescending : (a.raw.length > b.raw.length ? NSOrderedAscending : NSOrderedSame); }]) {
        if (after <= _limit) break; [_marked addObject:p]; after -= p.raw.length / 1024.0; }
    [_table reloadData]; [self updateSummary];
}
- (void)removeTicked:(id)s {
    NSMutableArray *rm = [NSMutableArray array]; for (EDPreset *p in self.presets) if ([_marked containsObject:p]) [rm addObject:p];
    if (!rm.count) { NSBeep(); return; }
    [_ed removePresets:rm]; [_marked removeAllObjects]; [_table reloadData]; [self updateSummary];
}
@end

@implementation EDPresetEditor {
    NSMenu *_outlineMenu; NSTableView *_presetTable, *_paramTable, *_sampleList; EDFitPanel *_fitPanel;
    NSMutableSet<NSNumber *> *_usedSamples;   // sample numbers the selected preset uses (marked in the bank sample list)
    NSButton *_assign, *_newVoice, *_newPreset, *_deletePreset;
    NSOutlineView *_outline;
    NSTextField *_nameField, *_numberField, *_hint;
    NSButton *_addRef, *_removeRef, *_dupVoice, *_removeVoice;
    EDPNode *_root;
    NSArray<EDPRow *> *_rows; NSInteger _setStart[3], _setEnd[3];   // the list view's three column sets, as ranges of _rows: voice parameters (two sets when long) and, last, the effects
    NSDictionary<NSNumber *, NSString *> *_sampleNames;
    EDPreset *_preset;
    EDPNode *_sel;
    EDKeyMapView *_keyMap;
    EDPlayer *_player;
    EDPresetLCD *_lcd; NSView *_paramScroll; NSSegmentedControl *_viewSeg;
}

- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) [self build];
    return self;
}

static NSView *column(NSString *title, NSView *content) {
    NSTextField *t = [NSTextField labelWithString:title.uppercaseString];
    t.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold]; t.textColor = NSColor.secondaryLabelColor;
    NSView *line = [NSView new]; line.wantsLayer = YES; line.layer.backgroundColor = EDTheme.accent.CGColor; line.translatesAutoresizingMaskIntoConstraints = NO;
    [line.heightAnchor constraintEqualToConstant:2].active = YES;
    NSStackView *st = [NSStackView stackViewWithViews:@[t, line, content]];
    st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeLeading; st.spacing = 5;
    [st setCustomSpacing:12 afterView:line];                       // a little air between the red line and the panel
    st.edgeInsets = NSEdgeInsetsMake(8, 8, 0, 8);
    [line.widthAnchor constraintEqualToAnchor:st.widthAnchor constant:-16].active = YES;
    [content.widthAnchor constraintEqualToAnchor:st.widthAnchor constant:-16].active = YES;
    return st;
}
static NSScrollView *scrollOf(NSView *v) { NSScrollView *s = [[NSScrollView alloc] init]; s.documentView = v; s.hasVerticalScroller = YES; s.borderType = NSNoBorder; return s; }
static NSView *lcdScrollOf(NSView *v) { return [EDTheme framedLCD:scrollOf(v)]; }
static NSView *lcdPanelOf(NSView *v, NSView *footer) { return [EDTheme framedLCD:scrollOf(v) footer:footer]; }

- (void)build {
    _presetTable = [[NSTableView alloc] init]; _presetTable.dataSource = self; _presetTable.delegate = self; _presetTable.usesAlternatingRowBackgroundColors = YES; _presetTable.rowHeight = 24;
    for (NSArray *c in @[@[@"num", @"#", @40], @[@"name", @"Preset", @150], @[@"kb", @"KB", @50]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_presetTable addTableColumn:col];
    }
    _newPreset = [self button:@"＋ New preset" action:@selector(newPreset:)];
    _deletePreset = [self button:@"Delete preset" action:@selector(deletePresetAction:)];
    NSStackView *presetBtns = [NSStackView stackViewWithViews:@[_newPreset, _deletePreset]]; presetBtns.spacing = 4;
    NSView *left = lcdPanelOf(_presetTable, presetBtns);

    _outline = [[NSOutlineView alloc] init]; _outline.dataSource = self; _outline.delegate = self; _outline.rowHeight = 24;
    NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"n"]; oc.title = @"Structure"; [_outline addTableColumn:oc]; _outline.outlineTableColumn = oc;

    _addRef = [self button:@"＋ Sample" action:@selector(addRef:)]; _removeRef = [self button:@"－ Sample" action:@selector(removeRef:)];
    _dupVoice = [self button:@"Copy voice" action:@selector(dupVoice:)]; _removeVoice = [self button:@"Delete voice" action:@selector(removeVoice:)];
    _newVoice = [self button:@"＋ Voice" action:@selector(newVoice:)];
    _outlineMenu = [NSMenu new]; _outlineMenu.delegate = self; _outlineMenu.autoenablesItems = NO;   // right-click on the structure: the same keys as below
    for (NSArray *k in @[@[@"＋ Voice", @"newVoice:"], @[@"Copy voice", @"dupVoice:"], @[@"Delete voice", @"removeVoice:"], @"-", @[@"＋ Sample", @"addRef:"], @[@"－ Sample", @"removeRef:"]]) {
        if ([k isKindOfClass:NSString.class]) { [_outlineMenu addItem:NSMenuItem.separatorItem]; continue; }
        NSMenuItem *it = [_outlineMenu addItemWithTitle:k[0] action:NSSelectorFromString(k[1]) keyEquivalent:@""]; it.target = self; }
    _outline.menu = _outlineMenu; [EDTheme useLCDContextMenuOn:_outline];
    NSStackView *btnRow1 = [NSStackView stackViewWithViews:@[_newVoice, _dupVoice, _removeVoice]]; btnRow1.spacing = 4;
    NSStackView *btnRow2 = [NSStackView stackViewWithViews:@[_addRef, _removeRef]]; btnRow2.spacing = 4;
    NSStackView *btns = [NSStackView stackViewWithViews:@[btnRow1, btnRow2]]; btns.orientation = NSUserInterfaceLayoutOrientationVertical; btns.alignment = NSLayoutAttributeLeading; btns.spacing = 4;
    _sampleList = [[NSTableView alloc] init]; _sampleList.dataSource = self; _sampleList.delegate = self; _sampleList.usesAlternatingRowBackgroundColors = YES; _sampleList.rowHeight = 22;
    for (NSArray *c in @[@[@"num", @"#", @44], @[@"name", @"Bank sample", @240]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_sampleList addTableColumn:col];
    }
    _sampleList.doubleAction = @selector(openSampleClicked:); _sampleList.target = self;
    _assign = [self button:@"Use for this zone" action:@selector(assignSample:)];
    NSView *sampleScroll = lcdPanelOf(_sampleList, _assign); NSLayoutConstraint *sampleH = [sampleScroll.heightAnchor constraintEqualToConstant:150]; sampleH.active = YES;
    NSTextField *sampleCap = [NSTextField labelWithString:@"BANK SAMPLES  (double-click to open)"];
    { NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:@"BANK SAMPLES" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightBold], NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
      [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"   double-click to open" attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: [NSColor.secondaryLabelColor colorWithAlphaComponent:0.7]}]];
      sampleCap.attributedStringValue = as; }   // same heading style as PRESETS / STRUCTURE
    NSView *capLine = [NSView new]; capLine.wantsLayer = YES; capLine.layer.backgroundColor = EDTheme.accent.CGColor; capLine.translatesAutoresizingMaskIntoConstraints = NO;
    EDHeightGrip *grip = [EDHeightGrip new]; grip.target = sampleH; grip.minH = 60; grip.maxH = 520; grip.translatesAutoresizingMaskIntoConstraints = NO;
    sampleCap.translatesAutoresizingMaskIntoConstraints = NO; [grip addSubview:sampleCap];
    [grip addSubview:capLine];
    [NSLayoutConstraint activateConstraints:@[[sampleCap.leadingAnchor constraintEqualToAnchor:grip.leadingAnchor], [sampleCap.topAnchor constraintEqualToAnchor:grip.topAnchor constant:8],
        [capLine.leadingAnchor constraintEqualToAnchor:grip.leadingAnchor], [capLine.trailingAnchor constraintEqualToAnchor:grip.trailingAnchor], [capLine.bottomAnchor constraintEqualToAnchor:grip.bottomAnchor], [capLine.heightAnchor constraintEqualToConstant:2],
        [grip.heightAnchor constraintEqualToConstant:32], [grip.widthAnchor constraintGreaterThanOrEqualToConstant:200]]];
    NSStackView *mid = [NSStackView stackViewWithViews:@[lcdPanelOf(_outline, btns), grip, sampleScroll]];
    [grip.widthAnchor constraintEqualToAnchor:mid.widthAnchor].active = YES;
    [sampleScroll.widthAnchor constraintEqualToAnchor:mid.widthAnchor].active = YES;
    mid.orientation = NSUserInterfaceLayoutOrientationVertical; mid.alignment = NSLayoutAttributeLeading; mid.spacing = 4;
    [mid.arrangedSubviews[0].widthAnchor constraintEqualToAnchor:mid.widthAnchor].active = YES;

    _nameField = [NSTextField textFieldWithString:@""]; _nameField.delegate = self; _nameField.controlSize = NSControlSizeRegular; _nameField.font = [NSFont systemFontOfSize:13];
    [_nameField.widthAnchor constraintEqualToConstant:220].active = YES;
    _numberField = [NSTextField textFieldWithString:@""]; _numberField.delegate = self; _numberField.controlSize = NSControlSizeRegular; _numberField.font = [NSFont systemFontOfSize:13];
    [_numberField.widthAnchor constraintEqualToConstant:50].active = YES;
    NSTextField *l1 = [NSTextField labelWithString:@"Preset Name"], *l2 = [NSTextField labelWithString:@"Preset Number"];
    l1.font = l2.font = [NSFont systemFontOfSize:12];
    _hint = [NSTextField labelWithString:@""]; _hint.font = [NSFont systemFontOfSize:12]; _hint.textColor = NSColor.secondaryLabelColor;
    NSStackView *top = [NSStackView stackViewWithViews:@[l1, _nameField, l2, _numberField, _hint]]; top.spacing = 6;

    [EDTheme styleLCDTable:_presetTable]; [EDTheme styleLCDTable:_outline]; [EDTheme styleLCDTable:_sampleList];
    _paramTable = [[NSTableView alloc] init]; _paramTable.dataSource = self; _paramTable.delegate = self; _paramTable.usesAlternatingRowBackgroundColors = YES; _paramTable.rowHeight = 24;
    for (NSArray *c in @[@[@"label", @"Parameter", @150], @[@"value", @"Value", @64], @[@"info", @"", @96], @[@"gap1", @"", @44], @[@"label2", @"Parameter", @150], @[@"value2", @"Value", @64], @[@"info2", @"", @96], @[@"gap2", @"", @44], @[@"label3", @"Parameter", @150], @[@"value3", @"Value", @64], @[@"info3", @"", @96]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_paramTable addTableColumn:col];
    }
    _keyMap = [[EDKeyMapView alloc] init]; _keyMap.translatesAutoresizingMaskIntoConstraints = NO;
    [_keyMap.heightAnchor constraintEqualToConstant:176].active = YES;
    __weak EDPresetEditor *weak = self;
    _keyMap.pressedKey = -1;
    _keyMap.picked = ^(id node) { [weak pickNode:node]; };
    _keyMap.keyDown = ^(int k) { [weak playKey:k]; };
    _keyMap.keyUp = ^{ [weak endKey]; };
    [EDTheme styleLCDTable:_paramTable]; _paramScroll = lcdScrollOf(_paramTable);
    _lcd = [[EDPresetLCD alloc] initWithFrame:NSMakeRect(0, 0, 600, 420)]; _lcd.translatesAutoresizingMaskIntoConstraints = NO;
    _lcd.getValue = ^NSInteger(EDParam *pp, NSInteger v, NSInteger r) { return [weak lcdValueOf:pp voice:v ref:r]; };
    _lcd.setValue = ^(EDParam *pp, NSInteger v, NSInteger r, NSInteger val) { [weak applyParam:pp voice:v ref:r value:val]; };
    _lcd.sampleName = ^NSString *(NSInteger n) { return [weak sampleLabel:n]; };
    _lcd.navigate = ^(NSInteger v, NSInteger r) { [weak navigateToVoice:v ref:r]; };
    _viewSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"LCD", @"List"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(paramViewPicked:)]; _viewSeg.segmentStyle = NSSegmentStyleSmallSquare;
    _viewSeg.selectedSegment = 0;
    NSView *segRow = [[NSView alloc] init]; segRow.translatesAutoresizingMaskIntoConstraints = NO; _viewSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [segRow addSubview:_viewSeg];
    [NSLayoutConstraint activateConstraints:@[[_viewSeg.centerXAnchor constraintEqualToAnchor:segRow.centerXAnchor], [_viewSeg.topAnchor constraintEqualToAnchor:segRow.topAnchor], [_viewSeg.bottomAnchor constraintEqualToAnchor:segRow.bottomAnchor]]];
    NSStackView *right = [NSStackView stackViewWithViews:@[top, _keyMap, segRow, _lcd, _paramScroll]];
    right.orientation = NSUserInterfaceLayoutOrientationVertical; right.alignment = NSLayoutAttributeLeading; right.spacing = 8;
    [right.arrangedSubviews[1].widthAnchor constraintEqualToAnchor:right.widthAnchor].active = YES;
    [segRow.widthAnchor constraintEqualToAnchor:right.widthAnchor].active = YES;
    [_lcd.widthAnchor constraintEqualToAnchor:right.widthAnchor].active = YES;
    [_lcd setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    [_paramScroll.widthAnchor constraintEqualToAnchor:right.widthAnchor].active = YES;
    _paramScroll.hidden = YES;

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:self.bounds]; split.vertical = YES; split.dividerStyle = NSSplitViewDividerStyleThin;
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSView *lc = column(@"Presets", left), *mc = column(@"Structure", mid), *rc = column(@"Parameters", right);
    [split addArrangedSubview:lc]; [split addArrangedSubview:mc]; [split addArrangedSubview:rc];
    [lc.widthAnchor constraintEqualToConstant:290].active = YES; [mc.widthAnchor constraintEqualToConstant:380].active = YES;
    [split setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0]; [split setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:1];
    split.delegate = self; [self addSubview:split];
}
// the columns have fixed widths: no draggable divider, so no resize cursor either
- (NSRect)splitView:(NSSplitView *)sv effectiveRect:(NSRect)drawn forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)i { return NSZeroRect; }
- (NSButton *)button:(NSString *)t action:(SEL)a { return [EDTheme lcdKey:t target:self action:a]; }

// MARK: data

- (void)setPresetMenu:(NSMenu *)m { _presetMenu = m; m.delegate = self; _presetTable.menu = m; [EDTheme useLCDContextMenuOn:_presetTable]; }
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == _outlineMenu) {
        NSInteger cr = _outline.clickedRow; if (cr >= 0 && cr != _outline.selectedRow) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:cr] byExtendingSelection:NO];
        NSDictionary *on = @{@"newVoice:": @(_newVoice.enabled), @"dupVoice:": @(_dupVoice.enabled), @"removeVoice:": @(_removeVoice.enabled), @"addRef:": @(_addRef.enabled), @"removeRef:": @(_removeRef.enabled)};
        for (NSMenuItem *i in menu.itemArray) if (i.action) i.enabled = [on[NSStringFromSelector(i.action)] boolValue];
        return;
    }
    NSInteger r = _presetTable.clickedRow;
    if (r >= 0 && r != _presetTable.selectedRow) [_presetTable selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
    EDPreset *p = (r >= 0 && r < (NSInteger)_bank.presets.count) ? _bank.presets[r] : nil;
    BOOL old = p.kind == EDPresetKindLegacy3X;
    NSMenuItem *info = [menu itemWithTag:901], *conv = [menu itemWithTag:902];
    info.title = !p ? @"No preset" : [NSString stringWithFormat:@"%@ · %ld voices", old ? @"Emulator 3X / ESI-32 preset (older)" : @"EOS E4 preset", (long)p.voiceCount];
    conv.hidden = !old;
    for (NSMenuItem *i in menu.itemArray) [EDTheme refreshLCDMenuItem:i];
}
- (void)setBank:(EDBank *)bank { _bank = bank; [self reload]; }
- (NSInteger)selectedIndex { return _presetTable.selectedRow; }
- (void)selectIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_bank.presets.count) return;
    [_presetTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; [_presetTable scrollRowToVisible:i];
}
- (void)reload {
    [_sampleList reloadData];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (EDSample *s in _bank.samples) names[@(s.number)] = s.name;
    _sampleNames = names;
    NSInteger keep = _presetTable.selectedRow;
    [_presetTable reloadData];
    if (_bank.presets.count) [_presetTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(keep >= 0 && keep < (NSInteger)_bank.presets.count) ? keep : 0] byExtendingSelection:NO];
    else [self selectPreset:nil];
}

- (NSString *)sampleLabel:(NSInteger)n {
    if (n >= 1000) return [NSString stringWithFormat:@"ROM sample %ld", (long)n];
    return _sampleNames[@(n)] ?: @"(not in this bank)";
}

- (EDPNode *)buildTreeFor:(EDPreset *)p {
    EDPNode *root = [EDPNode new]; root.voice = -1; root.ref = -1; root.title = [NSString stringWithFormat:@"%@", p.name]; root.children = [NSMutableArray array];
    EDParam *sampleParam = nil, *keyLow = nil, *keyHigh = nil, *root_ = nil;
    for (EDParam *q in [p paramsForScope:EDScopeRef]) { if (q.isSample) sampleParam = q; if ([q.label isEqual:@"Key low"]) keyLow = q; if ([q.label isEqual:@"Key high"]) keyHigh = q; if ([q.label isEqual:@"Root key"]) root_ = q; }
    EDParam *vKeyLow = nil, *vKeyHigh = nil;
    for (EDParam *q in [p paramsForScope:EDScopeVoice]) { if ([q.label isEqual:@"Key low"]) vKeyLow = q; if ([q.label isEqual:@"Key high"]) vKeyHigh = q; if (q.isSample) sampleParam = sampleParam ?: q; }
    EDParam *legSample = nil; for (EDParam *q in [p paramsForScope:EDScopeVoice]) if (q.isSample) legSample = q;
    NSMutableSet *used = [NSMutableSet set];
    for (NSInteger v = 0; v < p.voiceCount; v++) {
        EDPNode *vn = [EDPNode new]; vn.voice = v; vn.ref = -1; vn.children = [NSMutableArray array];
        if (vKeyLow && vKeyHigh) { vn.lo = [p valueOfParam:vKeyLow voice:v ref:0]; vn.hi = [p valueOfParam:vKeyHigh voice:v ref:0]; }
        if (p.kind == EDPresetKindE4) {
            vn.title = [NSString stringWithFormat:@"Voice %ld  %@–%@", (long)v + 1, [EDParam noteName:[p valueOfParam:vKeyLow voice:v ref:0]], [EDParam noteName:[p valueOfParam:vKeyHigh voice:v ref:0]]];
            for (NSInteger r = 0; r < [p refCountInVoice:v]; r++) {
                EDPNode *rn = [EDPNode new]; rn.voice = v; rn.ref = r; rn.children = [NSMutableArray array];
                if (keyLow && keyHigh) { rn.lo = [p valueOfParam:keyLow voice:v ref:r]; rn.hi = [p valueOfParam:keyHigh voice:v ref:r]; }
                NSInteger sn = [p valueOfParam:sampleParam voice:v ref:r]; [used addObject:@(sn)];
                rn.title = [NSString stringWithFormat:@"#%ld %@  (%@–%@)", (long)sn, [self sampleLabel:sn], [EDParam noteName:[p valueOfParam:keyLow voice:v ref:r]], [EDParam noteName:[p valueOfParam:keyHigh voice:v ref:r]]];
                [vn.children addObject:rn];
            }
        } else {
            NSInteger sn = [p valueOfParam:legSample voice:v ref:0]; [used addObject:@(sn)];
            vn.title = [NSString stringWithFormat:@"Voice %ld  #%ld %@", (long)v + 1, (long)sn, [self sampleLabel:sn]];
        }
        [root.children addObject:vn];
    }
    (void)root_; _usedSamples = used; [_sampleList reloadData]; return root;
}

- (void)selectPreset:(EDPreset *)p {
    _preset = p;
    _root = p ? [self buildTreeFor:p] : nil;
    [_outline reloadData]; if (_root) { [_outline expandItem:nil expandChildren:YES]; [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        // row 0 may already have been selected, in which case no selection event fires: refresh from the new tree explicitly
        _sel = [_outline itemAtRow:0]; [self rebuildRows]; [self updateKeyMap]; [self updateAssign]; }
    else { _sel = nil; [self rebuildRows]; [self updateKeyMap]; }
    _deletePreset.enabled = p != nil && [_bank.formType hasPrefix:@"E4B"]; _newPreset.enabled = _bank != nil && ![_bank.formType isEqualToString:@"3X"];
    _nameField.stringValue = p.name ?: @""; _nameField.enabled = p != nil;
    _numberField.stringValue = p ? [NSString stringWithFormat:@"%u", p.number] : @""; _numberField.enabled = p.kind == EDPresetKindE4;
    _hint.stringValue = p.kind == EDPresetKindLegacy3X ? @"Emulator 3X preset: only the sample reference of each voice is decoded; other voice bytes are shown raw." : @"";
}

- (void)rebuildRows {
    // Dual pane: the left pane lists the selected preset / voice / zone, the right pane always lists the preset's effects.
    NSMutableArray *left = [NSMutableArray array], *right = [NSMutableArray array];
    void (^addGroup)(NSMutableArray *, EDParam *, NSString **) = ^(NSMutableArray *dst, EDParam *p, NSString **last) {
        if (![p.group isEqualToString:*last]) { EDPRow *h = [EDPRow new]; h.group = p.group; [dst addObject:h]; *last = p.group; }
        EDPRow *r = [EDPRow new]; r.group = p.group; r.param = p; [dst addObject:r];
    };
    NSString *leftTitle = @"Parameter";
    if (_preset && _sel) {
        EDParamScope sc = _sel.ref >= 0 ? EDScopeRef : (_sel.voice >= 0 ? EDScopeVoice : EDScopePreset);
        leftTitle = sc == EDScopeRef ? @"Zone" : (sc == EDScopeVoice ? [NSString stringWithFormat:@"Voice %ld", (long)_sel.voice + 1] : @"Preset");
        NSString *last = nil;
        for (EDParam *p in [_preset paramsForScope:sc]) if (![p.group hasPrefix:@"Effect"]) addGroup(left, p, &last);
    }
    if (_preset) { NSString *last = nil; for (EDParam *p in [_preset paramsForScope:EDScopePreset]) if ([p.group hasPrefix:@"Effect"]) addGroup(right, p, &last); }
    // a long left pane (a voice or a zone) runs over two column sets, split at a group heading near the middle; the effects are always the last set
    NSInteger cut = (NSInteger)left.count;
    if (left.count >= 18) { NSInteger best = -1; for (NSInteger k = 1; k < (NSInteger)left.count; k++) if (!((EDPRow *)left[k]).param && (best < 0 || llabs(k - (NSInteger)left.count / 2) < llabs(best - (NSInteger)left.count / 2))) best = k; if (best > 0) cut = best; }
    NSInteger nl = (NSInteger)left.count, nr = (NSInteger)right.count; [left addObjectsFromArray:right]; _rows = left;
    BOOL twoLeft = cut < nl;
    _setStart[0] = 0; _setEnd[0] = cut;
    if (twoLeft) { _setStart[1] = cut; _setEnd[1] = nl; _setStart[2] = nl; _setEnd[2] = nl + nr; }
    else { _setStart[1] = nl; _setEnd[1] = nl + nr; _setStart[2] = nl + nr; _setEnd[2] = nl + nr; }   // effects take the second set when the left pane is short
    [_paramTable tableColumnWithIdentifier:@"label"].headerCell.stringValue = leftTitle;
    [_paramTable tableColumnWithIdentifier:@"label2"].headerCell.stringValue = twoLeft ? @"" : (nr ? @"Effects" : @"");
    [_paramTable tableColumnWithIdentifier:@"label3"].headerCell.stringValue = twoLeft && nr ? @"Effects" : @"";
    for (NSInteger k = 0; k < 3; k++) {   // headings only over sets that hold rows
        NSString *sfx = k == 0 ? @"" : (k == 1 ? @"2" : @"3"); BOOL used = _setEnd[k] > _setStart[k];
        [_paramTable tableColumnWithIdentifier:[@"value" stringByAppendingString:sfx]].headerCell.stringValue = used ? @"Value" : @"";
        if (k) { NSTableColumn *lc = [_paramTable tableColumnWithIdentifier:[@"label" stringByAppendingString:sfx]]; if (!used) lc.headerCell.stringValue = @""; }
    }
    [_paramTable.headerView setNeedsDisplay:YES];
    [_paramTable reloadData]; [self refreshLCD];
    BOOL e4 = _preset.canEditStructure, onVoice = _sel.voice >= 0;
    _newVoice.enabled = e4;
    _addRef.enabled = e4 && onVoice; _removeRef.enabled = e4 && _sel.ref >= 0 && [_preset refCountInVoice:_sel.voice] > 1;
    _dupVoice.enabled = e4 && onVoice; _removeVoice.enabled = e4 && onVoice && _preset.voiceCount > 1;
}

// MARK: tables / outline data

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { if (t == _sampleList) return (NSInteger)_bank.samples.count; if (t == _presetTable) return (NSInteger)_bank.presets.count; return MAX(_setEnd[0] - _setStart[0], MAX(_setEnd[1] - _setStart[1], _setEnd[2] - _setStart[2])); }
- (BOOL)tableView:(NSTableView *)t isGroupRow:(NSInteger)r { return NO; }   // group headings are drawn as a bold label in the first cell of their column set
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r { return [EDTheme lcdRowView]; }
- (NSTableRowView *)outlineView:(NSOutlineView *)ov rowViewForItem:(id)item { return [EDTheme lcdRowView]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSString *k = c.identifier;
    if (t == _sampleList) { EDSample *sm = _bank.samples[r]; BOOL used = [_usedSamples containsObject:@(sm.number)];   // samples the selected preset uses are marked and bold
        NSTextField *l = [EDTheme lcdLabel:[k isEqual:@"num"] ? (used ? [NSString stringWithFormat:@"● %u", sm.number] : [NSString stringWithFormat:@"%u", sm.number]) : sm.name];
        if (used) l.font = [NSFont boldSystemFontOfSize:l.font.pointSize]; return l; }
    if (t == _presetTable) {
        EDPreset *p = _bank.presets[r];
        return [EDTheme lcdLabel:[k isEqual:@"num"] ? [NSString stringWithFormat:@"%u", p.number] : ([k isEqual:@"kb"] ? [NSString stringWithFormat:@"%.1f", p.raw.length / 1024.0] : p.name)];
    }
    if ([k hasPrefix:@"gap"]) return nil;
    NSInteger set = 0; if ([k hasSuffix:@"2"]) set = 1; else if ([k hasSuffix:@"3"]) set = 2;
    if (set) k = [k substringToIndex:k.length - 1];
    NSInteger flat = _setStart[set] + r;
    if (flat >= _setEnd[set]) return nil;            // a shorter column ends here
    r = flat;
    EDPRow *row = _rows[r];
    if (!row.param) { if (![k isEqual:@"label"]) return nil; NSTextField *f = [EDTheme lcdLabel:row.group]; f.font = [EDTheme lcdFont:13]; return f; }
    EDParam *p = row.param;
    if ([k isEqual:@"label"]) return [EDTheme lcdLabel:p.label];
    NSInteger v = [_preset valueOfParam:p voice:MAX(_sel.voice, 0) ref:MAX(_sel.ref, 0)];
    if ([k isEqual:@"value"]) {
        NSTextField *f = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%ld", (long)v]];
        f.delegate = self; f.tag = r; f.editable = !p.readOnly; f.bordered = NO; f.drawsBackground = NO; f.font = [EDTheme lcdFont:13]; f.textColor = EDTheme.lcdInk; f.focusRingType = NSFocusRingTypeNone;
        f.wantsLayer = YES; f.layer.borderWidth = p.readOnly ? 0 : 1.5; f.layer.borderColor = EDTheme.lcdInk.CGColor; f.layer.cornerRadius = 0; f.alignment = NSTextAlignmentCenter;
        return f;
    }
    NSString *info = p.isSample ? [self sampleLabel:v] : [p displayForValue:v];
    if (!p.isSample && !p.names && !p.isNote) info = [NSString stringWithFormat:@"%ld … %ld", (long)p.min, (long)p.max];
    NSTextField *f = [EDTheme lcdLabel:info]; f.font = [EDTheme lcdFont:11]; return f;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object == _sampleList) { [self updateAssign]; return; }
    if (n.object == _presetTable) { NSInteger r = _presetTable.selectedRow; [self selectPreset:(r >= 0 && r < (NSInteger)_bank.presets.count) ? _bank.presets[r] : nil]; if (self.selectionChanged) self.selectionChanged(); }
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(EDPNode *)i { return i ? (NSInteger)i.children.count : (_root ? 1 : 0); }
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)idx ofItem:(EDPNode *)i { return i ? i.children[idx] : _root; }
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(EDPNode *)i { return i.children.count > 0; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)c item:(EDPNode *)i { return [EDTheme lcdLabel:i.title]; }
- (void)outlineViewSelectionDidChange:(NSNotification *)n { _sel = [_outline itemAtRow:_outline.selectedRow]; [self rebuildRows]; [self updateKeyMap]; [self updateAssign]; }
static BOOL InView(id r, NSView *v) { return [r isKindOfClass:NSView.class] && [(NSView *)r isDescendantOf:v]; }
- (BOOL)handleEnter {
    if (!_preset || !_root) return NO;
    id fr = self.window.firstResponder; BOOL inOutline = InView(fr, _outline), inList = InView(fr, _presetTable);
    if (inList) { [self.window makeFirstResponder:_outline]; if (_outline.selectedRow < 0) [self pickNode:_root]; return YES; }
    if (!inOutline) return NO;
    EDPNode *n = _sel ?: _root;
    if (n == _root) { EDPNode *v = _root.children.firstObject; if (v) [self pickNode:v]; return YES; }
    if (n.ref < 0 && n.children.count) { [self pickNode:n.children.firstObject]; return YES; }
    return YES;   // already at the deepest level
}
- (BOOL)handleExit {
    if (!_preset || !_root) return NO;
    id fr = self.window.firstResponder; if (!InView(fr, self) || InView(fr, _presetTable)) return NO;   // on the preset list: Exit leaves the page
    if (!InView(fr, _outline)) { [self.window makeFirstResponder:_outline]; return YES; }   // from the parameters back to the structure
    EDPNode *n = _sel ?: _root;
    if (n == _root) { [self.window makeFirstResponder:_presetTable]; return YES; }
    if (n.ref >= 0) { for (EDPNode *v in _root.children) if ([v.children containsObject:n]) { [self pickNode:v]; return YES; } }
    [self pickNode:_root]; return YES;
}
- (void)pickNode:(EDPNode *)node {
    NSInteger r = [_outline rowForItem:node]; if (r >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
}
- (void)updateKeyMap {
    NSMutableArray *bars = [NSMutableArray array];
    for (EDPNode *v in _root.children) {
        NSArray *items = v.children.count ? v.children : @[v];
        for (EDPNode *n in items) {
            if (n.lo < 0 || n.hi < n.lo) continue;
            BOOL sel = _sel == n || (_sel == v && v.children.count) || _sel == _root;
            [bars addObject:@{@"lo": @(MAX(0, MIN(127, n.lo))), @"hi": @(MAX(0, MIN(127, n.hi))), @"label": n.title ?: @"", @"node": n, @"selected": @(sel && _sel != _root)}];
        }
    }
    _keyMap.bars = bars; _keyMap.needsDisplay = YES;
}

// MARK: playing the on-screen keyboard

/// Plays the zone under `key`: the first zone (in voice order) whose key window contains it, at the pitch of that key relative to the zone's
/// root key. Held until the mouse is released; a looped sample sustains. Only the zone's key window, root key and sample are used — not the
/// voice's envelopes, filter, tuning or velocity, so it is an audition, not an emulation of the sampler.
- (void)playKey:(int)k {
    if (_preset.kind != EDPresetKindE4) { _hint.stringValue = @"Keyboard audition works on EOS presets."; return; }
    EDParam *sp = nil, *rk = nil;
    for (EDParam *q in [_preset paramsForScope:EDScopeRef]) { if (q.isSample) sp = q; if ([q.label isEqual:@"Root key"]) rk = q; }
    EDPNode *hit = nil;
    for (EDPNode *v in _root.children) { for (EDPNode *n in v.children) if (n.lo >= 0 && k >= n.lo && k <= n.hi) { hit = n; break; } if (hit) break; }
    if (!hit || !sp) { _hint.stringValue = [NSString stringWithFormat:@"%@: no zone covers this key", [EDParam noteName:k]]; [_player stop]; return; }
    NSInteger sn = [_preset valueOfParam:sp voice:hit.voice ref:hit.ref], root = rk ? [_preset valueOfParam:rk voice:hit.voice ref:hit.ref] : 60;
    EDSample *smp = nil; for (EDSample *x in _bank.samples) if (x.number == sn) { smp = x; break; }
    if (!smp) { _hint.stringValue = [NSString stringWithFormat:@"%@: %@", [EDParam noteName:k], sn >= 1000 ? @"ROM samples can't be played here" : @"sample is not in this bank"]; [_player stop]; return; }
    if (!_player) _player = [EDPlayer new];
    [_player playSample:smp ratio:pow(2.0, (double)(k - root) / 12.0)];
    _hint.stringValue = [NSString stringWithFormat:@"%@  →  #%ld %@  (root %@)", [EDParam noteName:k], (long)sn, smp.name, [EDParam noteName:root]];
    if (_sel != hit) [self pickNode:hit];
}
- (BOOL)auditionKey:(int)key {
    if (!_preset) return NO;
    _keyMap.pressedKey = key; _keyMap.needsDisplay = YES; [self playKey:key]; return YES;
}
- (void)endAudition { _keyMap.pressedKey = -1; _keyMap.needsDisplay = YES; [self endKey]; }
- (void)endKey { [_player stop]; _hint.stringValue = _preset.kind == EDPresetKindLegacy3X ? @"Emulator 3X preset: only the sample reference of each voice is decoded; other voice bytes are shown raw." : @""; }

// MARK: choosing a sample for a zone

// The sample parameter that applies to the selected node: a zone (E4) or a voice (3X); nil on the preset or on an E4 voice.
- (EDParam *)assignableSampleParam {
    if (!_preset || !_sel) return nil;
    BOOL e4 = _preset.kind == EDPresetKindE4;
    if (e4 && _sel.ref < 0) return nil;
    if (!e4 && _sel.voice < 0) return nil;
    for (EDParam *q in [_preset paramsForScope:(e4 ? EDScopeRef : EDScopeVoice)]) if (q.isSample) return q;
    return nil;
}
- (void)updateAssign {
    BOOL ok = [self assignableSampleParam] != nil && _sampleList.selectedRow >= 0;
    _assign.enabled = ok;
    _assign.title = [self assignableSampleParam] ? @"Use for this zone" : @"Select a zone first";
}
- (void)openSampleClicked:(id)sender {
    NSInteger row = _sampleList.clickedRow >= 0 ? _sampleList.clickedRow : _sampleList.selectedRow;
    if (row >= 0 && row < (NSInteger)_bank.samples.count && _openSample) _openSample(_bank.samples[row]);
}
- (void)assignSample:(id)sender {
    EDParam *sp = [self assignableSampleParam]; NSInteger row = _sampleList.clickedRow >= 0 ? _sampleList.clickedRow : _sampleList.selectedRow;
    if (!sp || row < 0 || row >= (NSInteger)_bank.samples.count) { NSBeep(); return; }
    NSInteger v = MAX(_sel.voice, 0), r = MAX(_sel.ref, 0), nv = _bank.samples[row].number;
    if ([_preset valueOfParam:sp voice:v ref:r] == nv) return;
    NSDictionary *before = [self snapshot];
    [_preset setValue:nv ofParam:sp voice:v ref:r];
    [self registerUndo:before name:@"Change Sample"];
    [self refreshTreeKeepingSelection]; [self rebuildRows]; [self changed];
}

// MARK: editing

static NSInteger parseValue(NSString *s, EDParam *p) {
    NSString *t = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (p.isNote && t.length >= 2 && [[NSCharacterSet letterCharacterSet] characterIsMember:[t characterAtIndex:0]]) {   // "C#3" style note names
        static NSString *const names[] = {@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"};
        for (int n = 0; n < 128; n++) if ([[EDParam noteName:n] caseInsensitiveCompare:t] == NSOrderedSame) return n;
        (void)names;
    }
    return t.integerValue;
}

- (NSDictionary *)snapshot { return @{@"raw": [_preset.raw copy], @"name": _preset.name, @"number": @(_preset.number)}; }
- (void)restore:(NSDictionary *)s onPreset:(EDPreset *)p {
    NSDictionary *now = @{@"raw": [p.raw copy], @"name": p.name, @"number": @(p.number)};
    [p.raw setData:s[@"raw"]]; p.name = s[@"name"]; p.number = [s[@"number"] unsignedShortValue];
    [[self.undoManager prepareWithInvocationTarget:self] restore:now onPreset:p];
    if (p == _preset) { NSInteger keep = _outline.selectedRow; [self selectPreset:p]; if (keep >= 0 && keep < _outline.numberOfRows) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:keep] byExtendingSelection:NO]; }
    [self changed];
}
- (void)registerUndo:(NSDictionary *)before name:(NSString *)n { [[self.undoManager prepareWithInvocationTarget:self] restore:before onPreset:_preset]; [self.undoManager setActionName:n]; }
- (void)changed {
    NSInteger r = [_bank.presets indexOfObject:_preset];
    if (r != NSNotFound) [_presetTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:r] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 3)]];
    if (_edited) _edited();
}

- (void)controlTextDidChange:(NSNotification *)n {
    NSTextField *f = n.object;   // E-mu names are 16 characters: stop at the limit while typing
    if (f == _nameField && f.stringValue.length > 16) {
        NSText *ed = f.currentEditor; NSString *cut = [f.stringValue substringToIndex:16];
        if (ed) { ed.string = cut; ed.selectedRange = NSMakeRange(16, 0); } else f.stringValue = cut;
        NSBeep();
    }
}
- (void)controlTextDidEndEditing:(NSNotification *)n {
    NSTextField *f = n.object; if (!_preset) return;
    NSDictionary *before = [self snapshot];
    if (f == _nameField) { if ([_nameField.stringValue isEqualToString:_preset.name]) return; _preset.name = _nameField.stringValue; _root.title = _preset.name; [_outline reloadItem:_root]; [self registerUndo:before name:@"Rename Preset"]; [self changed]; return; }
    if (f == _numberField) { NSInteger v = MAX(0, MIN(999, _numberField.integerValue)); if (v == _preset.number) return; _preset.number = (uint16_t)v; [self registerUndo:before name:@"Change Preset Number"]; [self changed]; return; }
    NSInteger row = f.tag; if (row < 0 || row >= (NSInteger)_rows.count || !_rows[row].param) return;
    EDParam *p = _rows[row].param;
    NSInteger nv = parseValue(f.stringValue, p);
    NSInteger old = [_preset valueOfParam:p voice:MAX(_sel.voice, 0) ref:MAX(_sel.ref, 0)];
    if (nv == old) { [_paramTable reloadData]; return; }
    [self applyParam:p voice:MAX(_sel.voice, 0) ref:MAX(_sel.ref, 0) value:nv];
}
/// One parameter change, from the list or from the LCD pages: undo, structure refresh, dirty state.
- (void)applyParam:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r value:(NSInteger)nv {
    if (!_preset) return;
    NSDictionary *before = [self snapshot];
    [_preset setValue:nv ofParam:p voice:v ref:r];
    [self registerUndo:before name:[NSString stringWithFormat:@"Change %@", p.label]];
    [_paramTable reloadData];
    if (p.isSample || p.isNote || [p.label hasPrefix:@"Key"]) [self refreshTreeKeepingSelection];
    [self refreshLCD];
    [self changed];
}
- (NSInteger)lcdValueOf:(EDParam *)p voice:(NSInteger)v ref:(NSInteger)r { return _preset ? [_preset valueOfParam:p voice:v ref:r] : 0; }
- (void)refreshLCD { [_lcd showPreset:_preset voice:_sel ? _sel.voice : -1 ref:_sel ? _sel.ref : -1]; }
- (void)paramViewPicked:(NSSegmentedControl *)s { BOOL lcd = s.selectedSegment == 0; _lcd.hidden = !lcd; _paramScroll.hidden = lcd; }
- (void)navigateToVoice:(NSInteger)v ref:(NSInteger)r {
    EDPNode *n = v >= 0 && v < (NSInteger)_root.children.count ? _root.children[v] : _root;
    if (r >= 0 && r < (NSInteger)n.children.count) n = n.children[r];
    NSInteger row = [_outline rowForItem:n]; if (row >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (void)refreshTreeKeepingSelection {
    NSInteger keep = _outline.selectedRow; EDPNode *old = _sel;
    _root = [self buildTreeFor:_preset]; [_outline reloadData]; [_outline expandItem:nil expandChildren:YES]; [self updateKeyMap];
    if (keep >= 0 && keep < _outline.numberOfRows) { [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:keep] byExtendingSelection:NO]; _sel = [_outline itemAtRow:keep]; }
    (void)old;
}

- (void)structural:(BOOL (^)(void))op name:(NSString *)name {
    if (!_preset) return;
    NSDictionary *before = [self snapshot];
    if (!op()) { NSBeep(); return; }
    [self registerUndo:before name:name];
    [self refreshTreeKeepingSelection]; [self rebuildRows]; [self changed];
}
- (void)newPreset:(id)s {
    EDPreset *p = [_bank addPresetNamed:@"New Preset"]; if (!p) { NSBeep(); return; }
    [[self.undoManager prepareWithInvocationTarget:self] removePresetObject:p]; [self.undoManager setActionName:@"New Preset"];
    [self reload]; NSInteger row = (NSInteger)[_bank.presets indexOfObject:p]; if (row >= 0) [self selectIndex:row];
    [self changed]; if (_presetCountChanged) _presetCountChanged();
}
// Delete (Preset Manage > Delete) and its inverse; each registers the other with the undo manager, so undo and redo both work.
- (void)deletePresetFromMenu:(id)s { [self deletePresetAction:s]; }
- (void)deletePresetAction:(id)s { if (_preset) [self removePresetObject:_preset]; }
- (void)removePresetObject:(EDPreset *)p {
    NSInteger row = (NSInteger)[_bank.presets indexOfObject:p];
    NSDictionary *st = [_bank detachPreset:p]; if (!st) { NSBeep(); return; }
    [[self.undoManager prepareWithInvocationTarget:self] restorePresetState:st]; if (!self.undoManager.isUndoing && !self.undoManager.isRedoing) [self.undoManager setActionName:@"Delete Preset"];
    [self reload]; NSInteger n = (NSInteger)_bank.presets.count;
    if (n) [self selectIndex:MIN(MAX(row, 0), n - 1)]; else [self selectPreset:nil];
    if (_edited) _edited(); if (self.selectionChanged) self.selectionChanged(); if (_presetCountChanged) _presetCountChanged();
}
- (void)removePresets:(NSArray<EDPreset *> *)ps {
    [self.undoManager beginUndoGrouping];
    for (EDPreset *p in ps) [self removePresetObject:p];
    [self.undoManager setActionName:[NSString stringWithFormat:@"Delete %lu Presets", (unsigned long)ps.count]];
    [self.undoManager endUndoGrouping];
}
- (void)presentFitToMemoryLimitK:(double)limitK {
    if (!_bank) { NSBeep(); return; }
    _fitPanel = [[EDFitPanel alloc] initWithEditor:self limitK:limitK]; [_fitPanel present];
}
- (void)restorePresetState:(NSDictionary *)st {
    EDPreset *p = st[@"preset"]; [_bank reattachPreset:st];
    [[self.undoManager prepareWithInvocationTarget:self] removePresetObject:p];
    [self reload]; NSInteger row = (NSInteger)[_bank.presets indexOfObject:p]; if (row >= 0) [self selectIndex:row];
    if (_edited) _edited(); if (self.selectionChanged) self.selectionChanged(); if (_presetCountChanged) _presetCountChanged();
}
- (void)newVoice:(id)s {
    NSInteger row = _sampleList.selectedRow, sn = row >= 0 && row < (NSInteger)_bank.samples.count ? _bank.samples[row].number : (_bank.samples.count ? _bank.samples[0].number : 1);
    [self structural:^BOOL { return [self->_preset addVoiceWithSampleNumber:sn]; } name:@"New Voice"];
    EDPNode *last = _root.children.lastObject; if (last) [self pickNode:last];
}
- (void)addRef:(id)s { NSInteger v = _sel.voice; [self structural:^BOOL { return [self->_preset addRefToVoice:v]; } name:@"Add Sample to Voice"]; }
- (void)removeRef:(id)s { NSInteger v = _sel.voice, r = _sel.ref; [self structural:^BOOL { return [self->_preset removeRef:r fromVoice:v]; } name:@"Remove Sample from Voice"]; }
- (void)dupVoice:(id)s { NSInteger v = _sel.voice; [self structural:^BOOL { return [self->_preset duplicateVoice:v]; } name:@"Duplicate Voice"]; }
- (void)removeVoice:(id)s { NSInteger v = _sel.voice; [self structural:^BOOL { return [self->_preset removeVoice:v]; } name:@"Remove Voice"]; }
- (NSView *)lcdView { return _lcd; }
@end
