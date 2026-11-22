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
    [[NSColor colorWithCalibratedRed:0.045 green:0.055 blue:0.07 alpha:1] setFill]; NSRectFill(self.bounds);
    CGFloat H = self.bounds.size.height, pianoH = 26, py = H - pianoH;
    // octave guides
    for (int n = 0; n < 128; n += 12) {
        [[NSColor colorWithCalibratedWhite:0.16 alpha:1] setFill]; NSRectFill(NSMakeRect([self xForKey:n], 0, 1, py));
    }
    // bars
    for (NSUInteger i = 0; i < self.bars.count; i++) {
        NSDictionary *b = self.bars[i]; NSRect r = [self barRect:i]; BOOL sel = [b[@"selected"] boolValue];
        NSBezierPath *bp = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
        [(sel ? [EDTheme lcdBackground] : [NSColor colorWithCalibratedRed:0.20 green:0.42 blue:0.62 alpha:1]) setFill]; [bp fill];
        if (r.size.height >= 12 && r.size.width > 60) {
            NSString *l = b[@"label"]; NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByTruncatingTail;
            [l drawInRect:NSInsetRect(r, 5, 0) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: sel ? [EDTheme lcdInk] : NSColor.whiteColor, NSParagraphStyleAttributeName: ps}];
        }
    }
    // keyboard
    static const BOOL black[12] = {0,1,0,1,0,0,1,0,1,0,1,0};
    CGFloat kw = ([self xForKey:128] - [self xForKey:0]) / 128;
    for (int n = 0; n < 128; n++) {
        if (black[n % 12]) continue;
        NSRect k = NSMakeRect([self xForKey:n], py, kw * (n % 12 == 4 || n % 12 == 11 ? 1 : 1.5) , pianoH);
        [[NSColor colorWithCalibratedWhite:0.90 alpha:1] setFill]; NSRectFill(NSInsetRect(k, 0.3, 0));
    }
    for (int n = 0; n < 128; n++) {
        if (!black[n % 12]) continue;
        [[NSColor colorWithCalibratedWhite:0.08 alpha:1] setFill]; NSRectFill(NSMakeRect([self xForKey:n], py, kw, pianoH * 0.62));
    }
    NSDictionary *at = @{NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.35 alpha:1]};
    for (int n = 0; n < 128; n += 12) [[EDParam noteName:n] drawAtPoint:NSMakePoint([self xForKey:n] + 1, py + pianoH - 12) withAttributes:at];
    // selected range shading on the keyboard
    for (NSDictionary *b in self.bars) if ([b[@"selected"] boolValue]) {
        [[EDTheme accent] setFill]; NSRectFill(NSMakeRect([self xForKey:[b[@"lo"] doubleValue]], py - 3, [self xForKey:[b[@"hi"] doubleValue] + 1] - [self xForKey:[b[@"lo"] doubleValue]], 3));
    }
    if (self.pressedKey >= 0) {   // the key being played
        [[[EDTheme lcdBackground] colorWithAlphaComponent:0.85] setFill];
        NSRectFillUsingOperation(NSMakeRect([self xForKey:self.pressedKey], py, MAX([self xForKey:self.pressedKey + 1] - [self xForKey:self.pressedKey], 3), pianoH), NSCompositingOperationSourceOver);
    }
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

@implementation EDPresetEditor {
    NSTableView *_presetTable, *_paramTable, *_sampleList;
    NSButton *_assign, *_newVoice, *_newPreset, *_deletePreset;
    NSOutlineView *_outline;
    NSTextField *_nameField, *_numberField, *_hint;
    NSButton *_addRef, *_removeRef, *_dupVoice, *_removeVoice;
    EDPNode *_root;
    NSArray<EDPRow *> *_rows;
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
    for (NSArray *c in @[@[@"num", @"#", @44], @[@"name", @"Preset", @200]]) {
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
    NSStackView *btnRow1 = [NSStackView stackViewWithViews:@[_newVoice, _dupVoice, _removeVoice]]; btnRow1.spacing = 4;
    NSStackView *btnRow2 = [NSStackView stackViewWithViews:@[_addRef, _removeRef]]; btnRow2.spacing = 4;
    NSStackView *btns = [NSStackView stackViewWithViews:@[btnRow1, btnRow2]]; btns.orientation = NSUserInterfaceLayoutOrientationVertical; btns.alignment = NSLayoutAttributeLeading; btns.spacing = 4;
    _sampleList = [[NSTableView alloc] init]; _sampleList.dataSource = self; _sampleList.delegate = self; _sampleList.usesAlternatingRowBackgroundColors = YES; _sampleList.rowHeight = 22;
    for (NSArray *c in @[@[@"num", @"#", @44], @[@"name", @"Bank sample", @240]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_sampleList addTableColumn:col];
    }
    _sampleList.doubleAction = @selector(assignSample:); _sampleList.target = self;
    _assign = [self button:@"Use for this zone" action:@selector(assignSample:)];
    NSView *sampleScroll = lcdPanelOf(_sampleList, _assign); [sampleScroll.heightAnchor constraintEqualToConstant:150].active = YES;
    NSTextField *sampleCap = [NSTextField labelWithString:@"BANK SAMPLES  (double-click to assign)"];
    sampleCap.font = [NSFont systemFontOfSize:11 weight:NSFontWeightBold]; sampleCap.textColor = NSColor.secondaryLabelColor;
    NSStackView *mid = [NSStackView stackViewWithViews:@[lcdPanelOf(_outline, btns), sampleCap, sampleScroll]];
    [sampleScroll.widthAnchor constraintEqualToAnchor:mid.widthAnchor].active = YES;
    mid.orientation = NSUserInterfaceLayoutOrientationVertical; mid.alignment = NSLayoutAttributeLeading; mid.spacing = 4;
    [mid.arrangedSubviews[0].widthAnchor constraintEqualToAnchor:mid.widthAnchor].active = YES;

    _nameField = [NSTextField textFieldWithString:@""]; _nameField.delegate = self; _nameField.controlSize = NSControlSizeRegular; _nameField.font = [NSFont systemFontOfSize:13];
    [_nameField.widthAnchor constraintEqualToConstant:220].active = YES;
    _numberField = [NSTextField textFieldWithString:@""]; _numberField.delegate = self; _numberField.controlSize = NSControlSizeRegular; _numberField.font = [NSFont systemFontOfSize:13];
    [_numberField.widthAnchor constraintEqualToConstant:50].active = YES;
    NSTextField *l1 = [NSTextField labelWithString:@"Name"], *l2 = [NSTextField labelWithString:@"Number"];
    l1.font = l2.font = [NSFont systemFontOfSize:12];
    _hint = [NSTextField labelWithString:@""]; _hint.font = [NSFont systemFontOfSize:12]; _hint.textColor = NSColor.secondaryLabelColor;
    NSStackView *top = [NSStackView stackViewWithViews:@[l1, _nameField, l2, _numberField, _hint]]; top.spacing = 6;

    [EDTheme styleLCDTable:_presetTable]; [EDTheme styleLCDTable:_outline]; [EDTheme styleLCDTable:_sampleList];
    _paramTable = [[NSTableView alloc] init]; _paramTable.dataSource = self; _paramTable.delegate = self; _paramTable.usesAlternatingRowBackgroundColors = YES; _paramTable.rowHeight = 24;
    for (NSArray *c in @[@[@"label", @"Parameter", @220], @[@"value", @"Value", @80], @[@"info", @"", @220]]) {
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
    _viewSeg = [NSSegmentedControl segmentedControlWithLabels:@[@"LCD", @"List"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(paramViewPicked:)];
    _viewSeg.selectedSegment = 0;
    NSStackView *right = [NSStackView stackViewWithViews:@[top, _keyMap, _viewSeg, _lcd, _paramScroll]];
    right.orientation = NSUserInterfaceLayoutOrientationVertical; right.alignment = NSLayoutAttributeLeading; right.spacing = 8;
    [right.arrangedSubviews[1].widthAnchor constraintEqualToAnchor:right.widthAnchor].active = YES;
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
    [self addSubview:split];
}
- (NSButton *)button:(NSString *)t action:(SEL)a { return [EDTheme lcdKey:t target:self action:a]; }

// MARK: data

- (void)setPresetMenu:(NSMenu *)m { _presetMenu = m; m.delegate = self; _presetTable.menu = m; }
- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSInteger r = _presetTable.clickedRow;
    if (r >= 0 && r != _presetTable.selectedRow) [_presetTable selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
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
    for (NSInteger v = 0; v < p.voiceCount; v++) {
        EDPNode *vn = [EDPNode new]; vn.voice = v; vn.ref = -1; vn.children = [NSMutableArray array];
        if (vKeyLow && vKeyHigh) { vn.lo = [p valueOfParam:vKeyLow voice:v ref:0]; vn.hi = [p valueOfParam:vKeyHigh voice:v ref:0]; }
        if (p.kind == EDPresetKindE4) {
            vn.title = [NSString stringWithFormat:@"Voice %ld  %@–%@", (long)v + 1, [EDParam noteName:[p valueOfParam:vKeyLow voice:v ref:0]], [EDParam noteName:[p valueOfParam:vKeyHigh voice:v ref:0]]];
            for (NSInteger r = 0; r < [p refCountInVoice:v]; r++) {
                EDPNode *rn = [EDPNode new]; rn.voice = v; rn.ref = r; rn.children = [NSMutableArray array];
                if (keyLow && keyHigh) { rn.lo = [p valueOfParam:keyLow voice:v ref:r]; rn.hi = [p valueOfParam:keyHigh voice:v ref:r]; }
                NSInteger sn = [p valueOfParam:sampleParam voice:v ref:r];
                rn.title = [NSString stringWithFormat:@"#%ld %@  (%@–%@)", (long)sn, [self sampleLabel:sn], [EDParam noteName:[p valueOfParam:keyLow voice:v ref:r]], [EDParam noteName:[p valueOfParam:keyHigh voice:v ref:r]]];
                [vn.children addObject:rn];
            }
        } else {
            NSInteger sn = [p valueOfParam:legSample voice:v ref:0];
            vn.title = [NSString stringWithFormat:@"Voice %ld  #%ld %@", (long)v + 1, (long)sn, [self sampleLabel:sn]];
        }
        [root.children addObject:vn];
    }
    (void)root_; return root;
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
    NSMutableArray *rows = [NSMutableArray array];
    if (_preset && _sel) {
        EDParamScope sc = _sel.ref >= 0 ? EDScopeRef : (_sel.voice >= 0 ? EDScopeVoice : EDScopePreset);
        NSString *last = nil;
        for (EDParam *p in [_preset paramsForScope:sc]) {
            if (![p.group isEqualToString:last]) { EDPRow *h = [EDPRow new]; h.group = p.group; [rows addObject:h]; last = p.group; }
            EDPRow *r = [EDPRow new]; r.group = p.group; r.param = p; [rows addObject:r];
        }
    }
    _rows = rows; [_paramTable reloadData]; [self refreshLCD];
    BOOL e4 = _preset.canEditStructure, onVoice = _sel.voice >= 0;
    _newVoice.enabled = e4;
    _addRef.enabled = e4 && onVoice; _removeRef.enabled = e4 && _sel.ref >= 0 && [_preset refCountInVoice:_sel.voice] > 1;
    _dupVoice.enabled = e4 && onVoice; _removeVoice.enabled = e4 && onVoice && _preset.voiceCount > 1;
}

// MARK: tables / outline data

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { if (t == _sampleList) return (NSInteger)_bank.samples.count; return t == _presetTable ? (NSInteger)_bank.presets.count : (NSInteger)_rows.count; }
- (BOOL)tableView:(NSTableView *)t isGroupRow:(NSInteger)r { return t == _paramTable && _rows[r].param == nil; }
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r { return [EDTheme lcdRowView]; }
- (NSTableRowView *)outlineView:(NSOutlineView *)ov rowViewForItem:(id)item { return [EDTheme lcdRowView]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSString *k = c.identifier;
    if (t == _sampleList) { EDSample *sm = _bank.samples[r]; return [EDTheme lcdLabel:[k isEqual:@"num"] ? [NSString stringWithFormat:@"%u", sm.number] : sm.name]; }
    if (t == _presetTable) {
        EDPreset *p = _bank.presets[r];
        return [EDTheme lcdLabel:[k isEqual:@"num"] ? [NSString stringWithFormat:@"%u", p.number] : p.name];
    }
    EDPRow *row = _rows[r];
    if (!row.param) { if (c && ![k isEqual:@"label"]) return nil; NSTextField *f = [EDTheme lcdLabel:row.group]; f.font = [EDTheme lcdFont:13]; return f; }
    EDParam *p = row.param;
    if ([k isEqual:@"label"]) return [EDTheme lcdLabel:p.label];
    NSInteger v = [_preset valueOfParam:p voice:MAX(_sel.voice, 0) ref:MAX(_sel.ref, 0)];
    if ([k isEqual:@"value"]) {
        NSTextField *f = [NSTextField textFieldWithString:[NSString stringWithFormat:@"%ld", (long)v]];
        f.delegate = self; f.tag = r; f.editable = !p.readOnly; f.bordered = NO; f.drawsBackground = NO; f.font = [EDTheme lcdFont:13]; f.textColor = EDTheme.lcdInk; f.focusRingType = NSFocusRingTypeNone;
        f.wantsLayer = YES; f.layer.borderWidth = p.readOnly ? 0 : 1.5; f.layer.borderColor = EDTheme.lcdInk.CGColor; f.layer.cornerRadius = 3; f.alignment = NSTextAlignmentCenter;
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
    if (r != NSNotFound) [_presetTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:r] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
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
    if (nv == old) { [_paramTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 3)]]; return; }
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
@end
