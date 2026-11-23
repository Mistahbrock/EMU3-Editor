#import "EDAlert.h"
#import "NSData+EDWrite.h"
#import "EDMainWindowController.h"
#import "EDSDSPanel.h"
#import "EDSMDIPanel.h"
#include <sys/mount.h>
#import "EDBank.h"
#import "EDSample+Ops.h"
#import "EDWaveformView.h"
#import "EDPlayer.h"
#import "EDPresetEditor.h"
#import "EDMIDIEditor.h"
#import "EDHomeList.h"
#import "EDUtils.h"
#import "EDMemoryView.h"
#import "EDTheme.h"
#import "EDDiskIcons.h"
#import "EDNewImage.h"
#import "EDBlueSCSIIni.h"
#import "EMU3Filesystem.h"
#import "EMU3Directory.h"
#import "EMU3File.h"

// ── source-list node ─────────────────────────────────────────────────────────
@interface EDNode : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) EMU3Directory *directory;   // folders (and the image root)
@property (nonatomic, strong) EMU3File *file;             // bank files
@property (nonatomic, copy) NSArray<NSString *> *path;    // folder names from the root to the containing folder
@property (nonatomic, strong) NSMutableArray<EDNode *> *children;
@end
@implementation EDNode
@end

// ── themed header: wordmark + LCD readout ────────────────────────────────────
@interface EDLogoView : NSView
@end
@implementation EDLogoView
- (NSSize)intrinsicContentSize { return NSMakeSize(210, 44); }
// clicking the logo opens the About box (the app menu no longer has an About item)
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (void)mouseDown:(NSEvent *)e { [NSApp sendAction:NSSelectorFromString(@"showAbout:") to:NSApp.delegate from:self]; }
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
- (NSString *)toolTip { return @"About EMU3 Editor"; }
- (void)drawRect:(NSRect)r {
    // the logo is Graphics/emu-logo.png (copied into the app); drawn in code only if that file is missing
    static NSImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{ img = [NSImage imageNamed:@"emu-logo"]; });
    if (img) { [img drawInRect:self.bounds fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}]; return; }
    NSDictionary *emu = @{NSFontAttributeName: [NSFont systemFontOfSize:34 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: EDTheme.logoBlue, NSKernAttributeName: @(-1)};
    NSDictionary *sub = @{NSFontAttributeName: [NSFont systemFontOfSize:9 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: EDTheme.labelWhite, NSKernAttributeName: @(2.2)};
    NSSize es = [@"E-MU" sizeWithAttributes:emu];
    CGFloat top = NSHeight(self.bounds) - 40;
    [@"E-MU" drawAtPoint:NSMakePoint(0, top + 6) withAttributes:emu];
    [EDTheme.logoBlue setFill];
    for (int i = 0; i < 3; i++) NSRectFill(NSMakeRect(es.width + 8, top + 12 + i * 9, 26, 5));
    [@"SAMPLER EDITOR" drawAtPoint:NSMakePoint(2, top - 4) withAttributes:sub];
}
@end

@interface EDLCDStrip : NSView
@property (nonatomic, copy) NSString *line1, *line2;
@end
@implementation EDLCDStrip
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 36); }
- (void)setLine1:(NSString *)l { _line1 = [l copy]; self.needsDisplay = YES; }
- (void)setLine2:(NSString *)l { _line2 = [l copy]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)r {
    // plain right-aligned text in the same grey as the status line on the left (no green panel)
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByTruncatingMiddle; ps.alignment = NSTextAlignmentCenter;
    NSDictionary *a1 = @{NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: [NSColor colorWithWhite:0.88 alpha:1], NSParagraphStyleAttributeName: ps};
    CGFloat w = NSWidth(self.bounds);
    NSString *one = _line2.length ? [NSString stringWithFormat:@"%@ — %@", _line1 ?: @"", _line2] : (_line1 ?: @"");
    [one drawInRect:NSMakeRect(0, 10, w, 16) withAttributes:a1];
}
- (BOOL)isFlipped { return YES; }
@end

@implementation EDMainWindowController {
    NSView *_cmdBar, *_cmdRule; NSPopUpButton *_linkSampler, *_linkHost; NSButton *_linkServe; NSPopUpButton *_linkID, *_linkAccess; NSTextField *_linkInfo; EDDiskIcons *_mountsIcons; NSTextField *_mountsDetail;
    NSLayoutConstraint *_statusWidth, *_statusWide, *_statusLead, *_lcdLead, *_lcdTrail; NSString *_autoStatus; NSMutableArray<NSNumber *> *_tabHistory; NSInteger _curTab; BOOL _tabBack; NSTimer *_statusTimer; NSString *_statusSig; BOOL _statusBusy;
    // model
    EMU3Filesystem *_fs;
    EDNode *_rootNode;
    EDNode *_currentNode;          // bank node currently open
    NSURL *_standaloneURL;         // set when a bare .e4b file is open
    NSData *_originalData;         // bytes as loaded, for backups
    NSString *_bankTitle;
    EDBank *_bank;
    EDSample *_sample;
    EDPlayer *_player;
    NSTimer *_playTimer;
    // views
    NSOutlineView *_outline;
    NSTableView *_sampleTable;
    EDWaveformView *_wave;
    NSLayoutConstraint *_presetNoteLeading; NSTextField *_presetNote, *_nameField, *_rateField, *_loopStartField, *_loopEndField, *_info, *_status;
    NSButton *_loopCheck, *_releaseCheck, *_playButton;
    NSTabView *_tabs;
    NSSegmentedControl *_tabPicker;
    EDLCDStrip *_lcd;
    id _spaceMonitor;
    NSMutableArray<NSButton *> *_sampleBtns, *_bankBtns;
    NSTextField *_masterSummary;
    NSUndoManager *_undo;
    EDSDSPanel *_sds;
    EDSMDIPanel *_smdi;
    EDPresetEditor *_presetEditor;
    EDMIDIEditor *_midiEditor; NSSegmentedControl *_masterPicker; NSView *_masterOverview; NSButton *_autoSaveBtn; BOOL _autoBackedUp;
    EDHomeList *_home;
    EDMemoryView *_memory;
    NSTextField *_samplerStatus; EDDiskIcons *_diskHint;
    NSScrollView *_diskScroll, *_outlineScroll; EDLCDSideTab *_diskSideTab; EDNode *_browseNode; BOOL _listView, _inBank, _bankList; NSArray<EDDiskItem *> *_diskItems; NSButton *_viewKey, *_loadKey, *_saveKey, *_infoKey;
}

- (instancetype)init {
    NSRect vis = NSScreen.mainScreen.visibleFrame;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, MAX(1280, vis.size.width * 0.86), MAX(780, vis.size.height * 0.88))
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    w.title = @"EMU3 Editor"; w.releasedWhenClosed = NO;
    [EDTheme styleWindow:w];
    w.backgroundColor = EDTheme.body;
    w.minSize = NSMakeSize(1180, 600);
    [w setFrameAutosaveName:@"EMU3EditorMain"];
    if ((self = [super initWithWindow:w])) {
        w.delegate = self;
        _player = [EDPlayer new];
        __weak EDMainWindowController *weak = self;
        _player.onStop = ^{ [weak playbackStopped]; };
        [self buildUI];
        [self refreshAll];
        // Space = play / stop from anywhere in the window except while typing in a text field.
        _spaceMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
            EDMainWindowController *me = weak;
            if (!me || e.window != me.window || e.keyCode != 49) return e;
            if (e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) return e;
            if ([me.window.firstResponder isKindOfClass:[NSText class]] || me.window.attachedSheet) return e;
            if (me->_sample && !me->_sample.locked) [me togglePlay:nil];
            return nil;
        }];
    }
    return self;
}

// MARK: front-panel state

- (EDBank *)bank { return _bank; }
- (NSString *)bankTitle { return _bankTitle; }
- (NSString *)diskTitle { return _fs.imageURL.lastPathComponent; }
- (NSString *)statusText { return _status.stringValue; }
- (NSInteger)selectedSampleIndex { return _sample ? (NSInteger)[_bank.samples indexOfObject:_sample] : -1; }
- (NSInteger)selectedPresetIndex { return _presetEditor.selectedIndex; }
- (void)selectSampleAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_bank.samples.count) return;
    [_sampleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; [_sampleTable scrollRowToVisible:i];
}
- (void)selectPresetAtIndex:(NSInteger)i { [_presetEditor selectIndex:i]; }
- (void)showEditorTab:(NSString *)ident {
    if (ident) [self selectTabNamed:ident];
    [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}
- (void)modelChanged { [self updateLCD]; if (self.onModelChange) self.onModelChange(); }

// MARK: UI construction

static NSTextField *lcdLabel(NSString *s) {
    NSTextField *t = [NSTextField labelWithString:s]; t.font = [EDTheme lcdFont:12]; t.textColor = EDTheme.lcdInk; return t;
}
static NSTextField *label(NSString *s) {
    NSTextField *t = [NSTextField labelWithString:s]; t.font = [NSFont systemFontOfSize:12]; t.textColor = NSColor.secondaryLabelColor; return t;
}
static NSTextField *toolNote(NSString *s) {
    NSTextField *t = [NSTextField wrappingLabelWithString:s]; t.font = [NSFont systemFontOfSize:12]; t.textColor = NSColor.secondaryLabelColor;
    t.preferredMaxLayoutWidth = 380; [t.widthAnchor constraintLessThanOrEqualToConstant:380].active = YES; return t;
}
- (NSTextField *)field:(CGFloat)width {
    NSTextField *t = [NSTextField textFieldWithString:@""]; t.delegate = self; t.controlSize = NSControlSizeRegular;
    t.font = [NSFont systemFontOfSize:13]; [t.widthAnchor constraintEqualToConstant:width].active = YES; return t;
}
- (NSTextField *)lcdField:(CGFloat)width {
    NSTextField *t = [self field:width]; t.font = [EDTheme lcdFont:13]; t.textColor = EDTheme.lcdInk; t.bezeled = NO; t.bordered = NO; t.focusRingType = NSFocusRingTypeNone;
    t.drawsBackground = YES; t.backgroundColor = [EDTheme.lcdInk colorWithAlphaComponent:0.14]; return t;
}
- (NSButton *)button:(NSString *)title action:(SEL)sel {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:sel]; b.controlSize = NSControlSizeRegular; b.bezelStyle = NSBezelStyleRounded; return b;
}
- (NSScrollView *)scroll:(NSView *)v {
    NSScrollView *s = [[NSScrollView alloc] init]; s.documentView = v; s.hasVerticalScroller = YES; s.borderType = NSNoBorder; return s;
}
- (NSTableView *)table:(NSArray<NSArray<NSString *> *> *)cols {
    NSTableView *t = [[EDLCDTableView alloc] init]; t.dataSource = self; t.delegate = self; t.usesAlternatingRowBackgroundColors = YES; t.focusRingType = NSFocusRingTypeNone;
    for (NSArray *c in cols) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [t addTableColumn:col];
    }
    return t;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    // left: source list
    _outline = [[NSOutlineView alloc] init];
    NSTableColumn *oc = [[NSTableColumn alloc] initWithIdentifier:@"name"]; oc.title = @"Disk"; [_outline addTableColumn:oc];
    _outline.outlineTableColumn = oc; _outline.dataSource = self; _outline.delegate = self;
    _outline.style = NSTableViewStyleSourceList; _outline.doubleAction = @selector(outlineDoubleClick:); _outline.target = self;
    [EDTheme styleLCDTable:_outline];
    // the sampler's key row: Utils / Browse / View / Load / Save / Info
    NSButton *kUtils = [EDTheme lcdKey:@"Utils ▴" target:self action:@selector(browserUtilsMenu:)], *kBrowse = [EDTheme lcdKey:@"Browse ▴" target:self action:@selector(browserBrowseMenu:)];
    _viewKey = [EDTheme lcdKey:@"View" target:self action:@selector(browserToggleView:)]; _loadKey = [EDTheme lcdKey:@"Load…" target:self action:@selector(browserLoad:)];
    _saveKey = [EDTheme lcdKey:@"Save…" target:self action:@selector(saveBank:)]; _infoKey = [EDTheme lcdKey:@"Info…" target:self action:@selector(browserInfo:)];
    NSStackView *diskBar = [NSStackView stackViewWithViews:@[kUtils, kBrowse, _viewKey, _loadKey, _saveKey, _infoKey]];
    diskBar.spacing = 8; diskBar.distribution = NSStackViewDistributionFillEqually;
    for (NSButton *k in diskBar.arrangedSubviews) [k.widthAnchor constraintEqualToConstant:150].active = YES;
    NSScrollView *outlineScroll = [self scroll:_outline]; _outlineScroll = outlineScroll;
    NSView *left = [EDTheme framedLCD:outlineScroll footer:diskBar];

    // sample list
    _sampleTable = [self table:@[@[@"num", @"#", @"40"], @[@"name", @"Sample", @"170"], @[@"rate", @"Rate", @"64"], @[@"len", @"Frames", @"80"], @[@"loop", @"Loop", @"44"]]];
    _sampleTable.headerView = [[NSTableHeaderView alloc] init]; _sampleTable.rowHeight = 24;
    [EDTheme styleLCDTable:_sampleTable];
    NSView *sampleScroll = [EDTheme framedLCD:[self scroll:_sampleTable]];

    // waveform + transport
    _wave = [[EDWaveformView alloc] init];
    __weak EDMainWindowController *weak = self;
    _wave.loopChanged = ^(BOOL final) { [weak loopDragged:final]; };
    [_wave.heightAnchor constraintGreaterThanOrEqualToConstant:320].active = YES;

    // the whole sample editor is one green LCD screen: waveform on top, keys and fields below
    _playButton = [EDTheme lcdKey:@"▶ Play" target:self action:@selector(togglePlay:)];
    NSButton *zi = [EDTheme lcdKey:@"＋" target:self action:@selector(zoomIn:)], *zo = [EDTheme lcdKey:@"－" target:self action:@selector(zoomOut:)];
    NSButton *zf = [EDTheme lcdKey:@"Fit" target:self action:@selector(zoomFit:)], *zl = [EDTheme lcdKey:@"Loop" target:self action:@selector(zoomLoop:)];
    _info = lcdLabel(@"");
    NSStackView *transport = [NSStackView stackViewWithViews:@[_playButton, zo, zi, zf, zl, _info]];
    transport.spacing = 6;

    _nameField = [self lcdField:150]; _rateField = [self lcdField:70]; _loopStartField = [self lcdField:80]; _loopEndField = [self lcdField:80];
    _loopCheck = [EDTheme lcdButton:@"Loop" target:self action:@selector(inspectorChanged:)];
    _releaseCheck = [EDTheme lcdButton:@"Loop in release" target:self action:@selector(inspectorChanged:)];
    for (NSButton *b in @[_loopCheck, _releaseCheck]) b.translatesAutoresizingMaskIntoConstraints = NO;
    [_loopCheck.widthAnchor constraintEqualToConstant:64].active = YES; [_releaseCheck.widthAnchor constraintEqualToConstant:140].active = YES;
    NSStackView *insp = [NSStackView stackViewWithViews:@[lcdLabel(@"Name"), _nameField, lcdLabel(@"Rate Hz"), _rateField,
        lcdLabel(@"Loop start"), _loopStartField, lcdLabel(@"Loop end"), _loopEndField, _loopCheck, _releaseCheck]];
    insp.spacing = 6;
    NSStackView *editorFoot = [NSStackView stackViewWithViews:@[transport, insp]];
    editorFoot.orientation = NSUserInterfaceLayoutOrientationVertical; editorFoot.alignment = NSLayoutAttributeLeading; editorFoot.spacing = 6;
    NSView *editor = [EDTheme framedLCD:_wave footer:editorFoot];

    NSSplitView *samplesSplit = [[NSSplitView alloc] init]; samplesSplit.vertical = YES; samplesSplit.dividerStyle = NSSplitViewDividerStyleThin;
    [samplesSplit addArrangedSubview:sampleScroll]; [samplesSplit addArrangedSubview:editor];
    [sampleScroll.widthAnchor constraintEqualToConstant:420].active = YES;
    [samplesSplit setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];

    _presetEditor = [[EDPresetEditor alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
    _presetEditor.edited = ^{ [weak updateTitle]; [weak modelChanged]; };
    _presetEditor.selectionChanged = ^{ [weak modelChanged]; };
    _presetEditor.presetCountChanged = ^{ [weak refreshBankStatus]; };
    NSMenu *pm = [[NSMenu alloc] initWithTitle:@"Preset"];
    NSMenuItem *m1 = [pm addItemWithTitle:@"Save as Bank on Sampler Disk…" action:@selector(sendPresetToSamplerDisk:) keyEquivalent:@""]; m1.target = self;
    NSMenuItem *m2 = [pm addItemWithTitle:@"Export as Bank File…" action:@selector(exportPresetBank:) keyEquivalent:@""]; m2.target = self;
    [pm addItem:NSMenuItem.separatorItem];
    NSMenuItem *m3 = [pm addItemWithTitle:@"Delete Preset" action:@selector(deletePresetFromMenu:) keyEquivalent:@""]; m3.target = _presetEditor;
    NSMenuItem *m4 = [pm addItemWithTitle:@"Clear All Presets…" action:@selector(clearAllPresets:) keyEquivalent:@""]; m4.target = self;
    [EDTheme styleLCDMenu:pm]; _presetEditor.presetMenu = pm;

    // Disk tab: open keys live in the green screen
    NSView *diskView = [NSView new];
    EDLCDSideTab *diskTab = [[EDLCDSideTab alloc] initWithTitle:@"DISK"]; _diskSideTab = diskTab;
    left.translatesAutoresizingMaskIntoConstraints = NO; [diskView addSubview:left];
    diskTab.translatesAutoresizingMaskIntoConstraints = NO; [left addSubview:diskTab];   // the DISK strip lives inside the green screen, above the keys
    for (NSLayoutConstraint *c in left.constraints) if (c.firstItem == outlineScroll && c.firstAttribute == NSLayoutAttributeLeading) c.constant = 60;
    _diskHint = [[EDDiskIcons alloc] initWithFrame:NSZeroRect];
    _diskScroll = [NSScrollView new]; _diskScroll.hasVerticalScroller = YES; _diskScroll.drawsBackground = NO; _diskScroll.documentView = _diskHint; [EDTheme useLCDScroller:_diskScroll];
    _diskHint.autoresizingMask = NSViewWidthSizable;
    _diskScroll.translatesAutoresizingMaskIntoConstraints = NO; [diskView addSubview:_diskScroll];
    [NSLayoutConstraint activateConstraints:@[[_diskScroll.topAnchor constraintEqualToAnchor:left.topAnchor constant:6], [_diskScroll.bottomAnchor constraintEqualToAnchor:left.bottomAnchor constant:-52],
        [_diskScroll.leadingAnchor constraintEqualToAnchor:left.leadingAnchor constant:60], [_diskScroll.trailingAnchor constraintEqualToAnchor:left.trailingAnchor constant:-4]]];
    __weak EDMainWindowController *weakSelf = self;
    _diskHint.onOpen = ^(EDDiskItem *it) { [weakSelf openBrowserItem:it]; };
    _diskHint.onSelect = ^(EDDiskItem *it) { [weakSelf browserSelectionChanged]; };
    _diskHint.onExit = ^{ [weakSelf browserGoUp]; };
    [NSLayoutConstraint activateConstraints:@[
        [left.topAnchor constraintEqualToAnchor:diskView.topAnchor constant:10], [left.leadingAnchor constraintEqualToAnchor:diskView.leadingAnchor constant:10],
        [diskTab.topAnchor constraintEqualToAnchor:left.topAnchor constant:8], [diskTab.bottomAnchor constraintEqualToAnchor:diskBar.topAnchor constant:-8],
        [diskTab.leadingAnchor constraintEqualToAnchor:left.leadingAnchor constant:8], [diskTab.widthAnchor constraintEqualToConstant:46],
        [left.trailingAnchor constraintEqualToAnchor:diskView.trailingAnchor constant:-10], [left.bottomAnchor constraintEqualToAnchor:diskView.bottomAnchor constant:-10]]];
    [EDTheme addGlareOver:left in:diskView];   // above the DISK strip and the icons

    // Master tab: sampler status and shortcuts | banks to open (sampler disk + recent) | current bank
    _samplerStatus = [NSTextField wrappingLabelWithString:@""]; _samplerStatus.font = [NSFont systemFontOfSize:14]; _samplerStatus.textColor = EDTheme.labelWhite;
    _masterSummary = [NSTextField wrappingLabelWithString:@""]; _masterSummary.font = [NSFont systemFontOfSize:15]; _masterSummary.textColor = EDTheme.labelWhite;
    NSStackView *gSampler = [self group:@"Sampler" views:@[_samplerStatus]];   // status only; the sampler tools live on the Tools tab
    NSStackView *gUtils = [self group:@"Utils" views:@[
        [self wideButton:@"Assign Key…" action:@selector(showAssignKeys:)], [self wideButton:@"Channel Volume…" action:@selector(showChannelVolume:)],
        [self wideButton:@"Tones…" action:@selector(showTones:)]]];
    NSStackView *gMasterMenu = [self group:@"Master" views:@[
        [self wideButton:@"MIDI (Mode, Controllers, Prefs)…" action:@selector(showMIDITab:)], [self wideButton:@"Setup (Tune, Output, Misc, SCSI)…" action:@selector(showSetupTab:)],
        [self wideButton:@"Bank (Erase, Name, Auto, Flash)…" action:@selector(showBankTab:)]]];
    NSStackView *leftCol = [NSStackView stackViewWithViews:@[gSampler, gMasterMenu, gUtils]]; leftCol.orientation = NSUserInterfaceLayoutOrientationVertical;
    leftCol.alignment = NSLayoutAttributeLeading; leftCol.spacing = 22;
    [gSampler.widthAnchor constraintEqualToAnchor:leftCol.widthAnchor].active = YES; [gUtils.widthAnchor constraintEqualToAnchor:leftCol.widthAnchor].active = YES; [gMasterMenu.widthAnchor constraintEqualToAnchor:leftCol.widthAnchor].active = YES;
    _home = [EDHomeList new]; __weak EDMainWindowController *wself = self;
    _home.onOpen = ^(NSURL *u) { [wself openURL:u]; };
    NSScrollView *homeScroll = [NSScrollView new]; homeScroll.documentView = _home.table; homeScroll.hasVerticalScroller = YES; NSView *homeFrame = [EDTheme framedLCD:homeScroll];
    NSTextField *homeHint = label(@"Double-click a bank to open it.");
    NSStackView *gOpen = [self group:@"Open a bank" views:@[homeHint, homeFrame]];
    [homeFrame.widthAnchor constraintEqualToAnchor:gOpen.widthAnchor].active = YES;
    [homeFrame.heightAnchor constraintGreaterThanOrEqualToConstant:240].active = YES;
    _memory = [EDMemoryView new]; _memory.residentTotalK = 768; _memory.presetTotalK = 404;
    NSInteger mb = [NSUserDefaults.standardUserDefaults integerForKey:@"SamplerSampleMB"]; if (mb <= 0) mb = 40; _memory.sampleTotalMB = mb;
    NSTextField *ramRow = label([NSString stringWithFormat:@"Sample memory: %ld MB (installed in the sampler)", (long)mb]);
    ramRow.toolTip = @"Information only: the sampler's sample RAM is physical (SIMMs) and cannot be read over SCSI. The Memory box uses this size for its percentages.";
    _autoSaveBtn = [NSButton checkboxWithTitle:@"Save to sampler automatically" target:self action:@selector(autoSaveToggled:)];
    _autoSaveBtn.state = [NSUserDefaults.standardUserDefaults boolForKey:@"AutoSaveToSampler"] ? NSControlStateValueOn : NSControlStateValueOff;
    _autoSaveBtn.toolTip = @"When the open bank is on the sampler's disk, writes it back a few seconds after you stop editing. The sampler still needs a SCSI rescan and a bank reload to see the change. The original is backed up once per opened bank.";
    NSStackView *gBank = [self group:@"Current bank" views:@[_masterSummary, _memory, ramRow, _autoSaveBtn,
        [self wideButton:@"Save Bank" action:@selector(saveBank:)], [self wideButton:@"Save Bank As…" action:@selector(saveBankAs:)],
        [self wideButton:@"Open Bank File…" action:@selector(openBankFile:)],
        [self wideButton:@"Send Sample to Sampler Disk…" action:@selector(sendToSamplerDisk:)]]];
    NSView *masterView = [NSView new];
    for (NSView *v in @[leftCol, gOpen, gBank]) { v.translatesAutoresizingMaskIntoConstraints = NO; [masterView addSubview:v]; [v.topAnchor constraintEqualToAnchor:masterView.topAnchor constant:-10].active = YES; }
    [NSLayoutConstraint activateConstraints:@[
        [leftCol.leadingAnchor constraintEqualToAnchor:masterView.leadingAnchor constant:40], [leftCol.widthAnchor constraintEqualToConstant:270],
        [gOpen.leadingAnchor constraintEqualToAnchor:leftCol.trailingAnchor constant:40], [gOpen.bottomAnchor constraintEqualToAnchor:masterView.bottomAnchor constant:-8],
        [gBank.leadingAnchor constraintEqualToAnchor:gOpen.trailingAnchor constant:40], [gBank.trailingAnchor constraintEqualToAnchor:masterView.trailingAnchor constant:-40],
        [gBank.widthAnchor constraintEqualToConstant:420]]];

    // Master tab = overview | MIDI | Setup (the sampler's Master menus), switched by a small picker on top
    NSView *masterRoot = [NSView new];
    NSSegmentedControl *mp = [NSSegmentedControl segmentedControlWithLabels:@[@"Utilities", @"Bank", @"Setup", @"FX", @"MIDI"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(masterPicked:)];
    mp.selectedSegment = 0; _masterPicker = mp;
    [self applyFXBoardSetting];
    _midiEditor = [[EDMIDIEditor alloc] initWithFrame:NSMakeRect(0, 0, 800, 500)];
    _midiEditor.edited = ^{ [weak updateTitle]; [weak modelChanged]; };
    _midiEditor.action = ^(NSString *n) { [weak masterAction:n]; };
    _midiEditor.memoryChanged = ^(NSInteger k) { EDMainWindowController *s = weak; if (s) s->_memory.presetTotalK = k; };
    NSString *pm0 = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"SamplerMIDIProfile"][@"memprefer"]; if (pm0.integerValue > 0) _memory.presetTotalK = pm0.integerValue;
    _masterOverview = masterView; _midiEditor.hidden = YES;
    for (NSView *v in @[mp, masterView, _midiEditor]) { v.translatesAutoresizingMaskIntoConstraints = NO; [masterRoot addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [mp.topAnchor constraintEqualToAnchor:masterRoot.topAnchor constant:10], [mp.centerXAnchor constraintEqualToAnchor:masterRoot.centerXAnchor],
        [masterView.topAnchor constraintEqualToAnchor:mp.bottomAnchor constant:4], [masterView.leadingAnchor constraintEqualToAnchor:masterRoot.leadingAnchor],
        [masterView.trailingAnchor constraintEqualToAnchor:masterRoot.trailingAnchor], [masterView.bottomAnchor constraintEqualToAnchor:masterRoot.bottomAnchor],
        [_midiEditor.topAnchor constraintEqualToAnchor:mp.bottomAnchor constant:0], [_midiEditor.leadingAnchor constraintEqualToAnchor:masterRoot.leadingAnchor],
        [_midiEditor.trailingAnchor constraintEqualToAnchor:masterRoot.trailingAnchor], [_midiEditor.bottomAnchor constraintEqualToAnchor:masterRoot.bottomAnchor]]];

    // tabs, driven by the segmented picker in the header
    _tabs = [[NSTabView alloc] init]; _tabs.tabViewType = NSNoTabsNoBorder; _tabs.delegate = self;
    // Tools tab: making and preparing disk images (ported from the EMU3 Disk Manager)
    NSStackView *gImages = [self group:@"Disk images" views:@[
        toolNote(@"New images are formatted as empty EOS disks."),
        [self wideButton:@"New Floppy Image… (1.44 MB)" action:@selector(newFloppyImage:)],
        [self wideButton:@"New Disk Image…" action:@selector(newDiskImage:)]]];
    NSStackView *gCard = [self group:@"BlueSCSI SD card" views:@[
        toolNote(@"For a card that goes into a BlueSCSI in the sampler (or into a card reader)."),
        [self wideButton:@"Copy Disk Image to SD Card…" action:@selector(copyToSDCard:)],
        [self wideButton:@"Write bluescsi.ini…" action:@selector(writeBlueSCSIIni:)]]];
    // Sampler link: the helper's settings files in ~/Library/Application Support/EMU3 (same files as the Disk Manager)
    _linkID = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; 
    _linkID.target = self; _linkID.action = @selector(linkSettingChanged:);
    _linkSampler = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; _linkHost = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSPopUpButton *p in @[_linkSampler, _linkHost]) { for (int i = 0; i < 8; i++) [p addItemWithTitle:[NSString stringWithFormat:@"%d", i]]; p.target = self; p.action = @selector(linkBusChanged:); }
    _linkAccess = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [_linkAccess addItemsWithTitles:@[@"Read-write", @"Read-only"]]; _linkAccess.target = self; _linkAccess.action = @selector(linkSettingChanged:);
    _linkInfo = toolNote(@" ");
    NSStackView *busRow = [NSStackView stackViewWithViews:@[label(@"Sampler ID:"), _linkSampler, label(@"Host (initiator) ID:"), _linkHost]]; busRow.spacing = 8;
    NSStackView *idRow = [NSStackView stackViewWithViews:@[label(@"SCSI ID of the served disk:"), _linkID]]; idRow.spacing = 8;
    NSStackView *accRow = [NSStackView stackViewWithViews:@[label(@"Access:"), _linkAccess]]; accRow.spacing = 8;
    NSStackView *gLink = [self group:@"Server setup" views:@[
        toolNote(@"Bus IDs: the sampler is normally ID 6 and the board is the host (initiator) at ID 7, so the served disk takes one of the others (0–5). Change them here if your setup differs; rescan on the sampler afterwards."),
        busRow, idRow, accRow, _linkInfo, _linkServe = [self wideButton:@"Stop Serving" action:@selector(toggleServing:)], [self wideButton:@"Image Folder…" action:@selector(chooseImageFolder:)]]];
    NSStackView *gSamplerTools = [self group:@"Sampler" views:@[
        toolNote(@"Find the sampler on the SCSI bus, send samples by MIDI, or see the disk it uses. SMDI transfers are on the Samples page."),
        [self wideButton:@"Find Sampler (SCSI scan)…" action:@selector(findSampler:)],
        [self wideButton:@"MIDI Sample Dump…" action:@selector(sdsTransfer:)],
        [self wideButton:@"Show Sampler Disk" action:@selector(showSamplerDisk:)],
        [self wideButton:@"Open Disk Image…" action:@selector(openDiskImage:)]]];
    NSView *toolsView = [NSView new];
    // MOUNTS: green panel with an icon per disk image found on a mounted volume (top level only) and a description of the selected one
    _mountsIcons = [[EDDiskIcons alloc] initWithFrame:NSZeroRect]; _mountsIcons.autoresizingMask = NSViewWidthSizable; _mountsIcons.emptyText = @"No disk images on mounted drives.";
    NSScrollView *mScroll = [NSScrollView new]; mScroll.hasVerticalScroller = YES; mScroll.drawsBackground = NO; mScroll.documentView = _mountsIcons;
    _mountsDetail = [NSTextField wrappingLabelWithString:@" "]; _mountsDetail.font = [EDTheme lcdFont:12]; _mountsDetail.textColor = EDTheme.lcdInk; _mountsDetail.maximumNumberOfLines = 3;
    NSView *mounts = [EDTheme framedLCD:mScroll footer:_mountsDetail];
    EDLCDSideTab *mTab = [[EDLCDSideTab alloc] initWithTitle:@"MOUNTS"]; mTab.translatesAutoresizingMaskIntoConstraints = NO; [mounts addSubview:mTab];
    for (NSLayoutConstraint *c in mounts.constraints) if (c.firstItem == mScroll && c.firstAttribute == NSLayoutAttributeLeading) c.constant = 60;
    [NSLayoutConstraint activateConstraints:@[[mTab.topAnchor constraintEqualToAnchor:mounts.topAnchor constant:8], [mTab.bottomAnchor constraintEqualToAnchor:_mountsDetail.topAnchor constant:-8],
        [mTab.leadingAnchor constraintEqualToAnchor:mounts.leadingAnchor constant:8], [mTab.widthAnchor constraintEqualToConstant:70],
        [_mountsDetail.heightAnchor constraintEqualToConstant:54], [_mountsDetail.trailingAnchor constraintEqualToAnchor:mounts.trailingAnchor constant:-12]]];
    _mountsIcons.onSelect = ^(EDDiskItem *it) { [weakSelf mountsSelectionChanged]; };
    _mountsIcons.onOpen = ^(EDDiskItem *it) { if (it.url) [weakSelf showImageOnDisk:it.url]; };
    for (NSView *v in @[gImages, gCard, gLink, gSamplerTools, mounts]) { v.translatesAutoresizingMaskIntoConstraints = NO; [toolsView addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [gImages.topAnchor constraintEqualToAnchor:toolsView.topAnchor constant:30], [gCard.topAnchor constraintEqualToAnchor:toolsView.topAnchor constant:30],
        [gImages.leadingAnchor constraintEqualToAnchor:toolsView.leadingAnchor constant:40],
        [gCard.leadingAnchor constraintEqualToAnchor:gImages.trailingAnchor constant:40], [gCard.widthAnchor constraintEqualToAnchor:gImages.widthAnchor],
        [gLink.topAnchor constraintEqualToAnchor:toolsView.topAnchor constant:30], [gLink.leadingAnchor constraintEqualToAnchor:gCard.trailingAnchor constant:40], [gLink.widthAnchor constraintEqualToAnchor:gImages.widthAnchor], [gSamplerTools.topAnchor constraintEqualToAnchor:toolsView.topAnchor constant:30], [gSamplerTools.leadingAnchor constraintEqualToAnchor:gLink.trailingAnchor constant:40], [gSamplerTools.widthAnchor constraintEqualToAnchor:gImages.widthAnchor], [gSamplerTools.trailingAnchor constraintEqualToAnchor:toolsView.trailingAnchor constant:-40],
        [mounts.topAnchor constraintGreaterThanOrEqualToAnchor:gCard.bottomAnchor constant:30], [mounts.topAnchor constraintGreaterThanOrEqualToAnchor:gSamplerTools.bottomAnchor constant:30], [mounts.topAnchor constraintGreaterThanOrEqualToAnchor:gLink.bottomAnchor constant:30], [mounts.topAnchor constraintGreaterThanOrEqualToAnchor:gImages.bottomAnchor constant:30], [mounts.leadingAnchor constraintEqualToAnchor:toolsView.leadingAnchor constant:40],
        [mounts.trailingAnchor constraintEqualToAnchor:toolsView.trailingAnchor constant:-40], [mounts.bottomAnchor constraintEqualToAnchor:toolsView.bottomAnchor constant:-30]]];
    [EDTheme addGlareOver:mounts in:toolsView];
    NSArray *defs = @[@[@"master", @"Master", masterRoot], @[@"disk", @"Disk", diskView], @[@"samples", @"Samples", samplesSplit], @[@"presets", @"Presets", _presetEditor], @[@"tools", @"Tools", toolsView]];
    for (NSArray *d in defs) { NSTabViewItem *t = [[NSTabViewItem alloc] initWithIdentifier:d[0]]; t.label = d[1]; t.view = d[2]; [_tabs addTabViewItem:t]; }
    _tabPicker = [NSSegmentedControl segmentedControlWithLabels:@[@"Master", @"Disk", @"Samples", @"Presets", @"Tools"] trackingMode:NSSegmentSwitchTrackingSelectOne
        target:self action:@selector(tabPicked:)];
    _tabPicker.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold]; _tabPicker.selectedSegment = 0;
    for (NSInteger i = 0; i < 5; i++) [_tabPicker setWidth:80 forSegment:i];

    // header: wordmark, tab picker, LCD readout, red rule
    _lcd = [EDLCDStrip new];
    EDLogoView *logo = [EDLogoView new];
    NSView *head = [NSView new]; head.wantsLayer = YES; head.layer.backgroundColor = EDTheme.bodyDark.CGColor;
    for (NSView *v in @[logo, _tabPicker]) { v.translatesAutoresizingMaskIntoConstraints = NO; [head addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [head.heightAnchor constraintEqualToConstant:72],
        [logo.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:18], [logo.centerYAnchor constraintEqualToAnchor:head.centerYAnchor],
        [_tabPicker.centerXAnchor constraintEqualToAnchor:head.centerXAnchor], [_tabPicker.centerYAnchor constraintEqualToAnchor:head.centerYAnchor]]];
    NSView *rule = [NSView new]; rule.wantsLayer = YES; rule.layer.backgroundColor = EDTheme.accent.CGColor;
    [rule.heightAnchor constraintEqualToConstant:3].active = YES;

    // command bar: every action as a themed key, grouped like the panel's labelled blocks
    _sampleBtns = [NSMutableArray array]; _bankBtns = [NSMutableArray array];
    NSStackView *bar = [NSStackView stackViewWithViews:@[
        [self barGroup:@"File" keys:@[@[@"Open Disk", @"openDiskImage:", @0], @[@"Open Bank", @"openBankFile:", @0], @[@"Save", @"saveBank:", @2], @[@"Save As", @"saveBankAs:", @2]]],
        [self barGroup:@"Audition" keys:@[@[@"▶ Play", @"togglePlay:", @1]]],
        [self barGroup:@"Sample edit" keys:@[@[@"Normalize", @"normalize:", @1], @[@"Reverse", @"reverseSample:", @1], @[@"Fade In", @"fadeIn:", @1], @[@"Fade Out", @"fadeOut:", @1],
            @[@"Remove DC", @"removeDC:", @1], @[@"Crop Loop", @"cropToLoop:", @1], @[@"X-Fade Loop", @"crossfadeLoop:", @1]]],
        [self barGroup:@"Convert" keys:@[@[@"Export WAV", @"exportWAV:", @1], @[@"Replace", @"importWAV:", @1]]],
        [self barGroup:@"Transfer" keys:@[@[@"SMDI", @"smdiTransfer:", @0], @[@"MIDI Dump", @"sdsTransfer:", @1], @[@"To Disk", @"sendToSamplerDisk:", @1]]],
        [self barGroup:@"Zoom" keys:@[@[@"−", @"zoomOut:", @0], @[@"+", @"zoomIn:", @0], @[@"Fit", @"zoomFit:", @0], @[@"Loop", @"zoomLoop:", @0]]]]];
    _cmdBar = bar;
    bar.spacing = 24; bar.alignment = NSLayoutAttributeTop;
    { NSArray *gs = bar.arrangedSubviews; for (NSView *v in gs) [bar removeArrangedSubview:v]; [bar setViews:gs inGravity:NSStackViewGravityCenter]; } bar.edgeInsets = NSEdgeInsetsMake(12, 36, 0, 36);
    bar.wantsLayer = YES; bar.layer.backgroundColor = NSColor.clearColor.CGColor;
    [bar.heightAnchor constraintEqualToConstant:96].active = YES;
    NSView *rule2 = [NSView new]; rule2.wantsLayer = YES; rule2.layer.backgroundColor = NSColor.clearColor.CGColor;
    [rule2.heightAnchor constraintEqualToConstant:1].active = YES; _cmdRule = rule2;

    _status = label(@"Open a disk image or a bank file."); _status.lineBreakMode = NSLineBreakByTruncatingTail; _status.font = [NSFont systemFontOfSize:13]; _status.textColor = [NSColor colorWithWhite:0.88 alpha:1];
    _presetNote = label(@"Pages follow the sampler's Preset Edit menus. Changes go straight into the preset (Edit ▸ Undo works).");
    // footer: status text on the left, the green LCD readout on the right
    NSView *foot = [NSView new]; _presetNote.hidden = YES;
    // the readout lines up with the left edge of the bank list above (x = 350); the status text wraps in the space to its left
    [_status addObserver:self forKeyPath:@"stringValue" options:0 context:NULL];
    _status.lineBreakMode = NSLineBreakByTruncatingTail; _status.maximumNumberOfLines = 1; _status.preferredMaxLayoutWidth = 322;
    [_status setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    for (NSView *v in @[_status, _lcd]) { v.translatesAutoresizingMaskIntoConstraints = NO; [foot addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [foot.heightAnchor constraintEqualToConstant:36],
        (_statusLead = [_status.leadingAnchor constraintEqualToAnchor:foot.leadingAnchor constant:14]), [_status.centerYAnchor constraintEqualToAnchor:foot.centerYAnchor],
        (_lcdLead = [_lcd.leadingAnchor constraintEqualToAnchor:foot.leadingAnchor constant:350]), (_lcdTrail = [_lcd.trailingAnchor constraintEqualToAnchor:foot.trailingAnchor constant:-501]),
        [_lcd.centerYAnchor constraintEqualToAnchor:foot.centerYAnchor], [_lcd.heightAnchor constraintEqualToConstant:36]]];
    _statusWidth = [_status.widthAnchor constraintEqualToConstant:322]; _statusWide = [_status.trailingAnchor constraintEqualToAnchor:foot.trailingAnchor constant:-14]; _statusWide.active = YES;
    _status.alignment = NSTextAlignmentCenter;   // centred under the page (beside the readout on Master ▸ Utilities)
    NSStackView *root = [NSStackView stackViewWithViews:@[head, rule, bar, rule2, _tabs, foot]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.spacing = 0; root.alignment = NSLayoutAttributeLeading;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor], [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor], [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-4],
        [head.widthAnchor constraintEqualToAnchor:root.widthAnchor], [bar.widthAnchor constraintEqualToAnchor:root.widthAnchor], [rule2.widthAnchor constraintEqualToAnchor:root.widthAnchor], [rule.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [_tabs.widthAnchor constraintEqualToAnchor:root.widthAnchor], [foot.widthAnchor constraintEqualToAnchor:root.widthAnchor]]];
    // the Presets note lines up with the left edge of the LCD screen, on the status line
    _presetNote.translatesAutoresizingMaskIntoConstraints = NO; [foot addSubview:_presetNote];
    [_presetNote.centerYAnchor constraintEqualToAnchor:_status.centerYAnchor].active = YES;
    [self updateLCD];
}

// A captioned group with a red rule, in the style of the preset editor's columns.
- (NSStackView *)group:(NSString *)title views:(NSArray<NSView *> *)views {
    NSTextField *cap = [NSTextField labelWithString:title.uppercaseString];
    cap.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold]; cap.textColor = EDTheme.labelWhite;
    NSView *line = [NSView new]; line.wantsLayer = YES; line.layer.backgroundColor = EDTheme.accent.CGColor;
    [line.heightAnchor constraintEqualToConstant:2].active = YES;
    NSStackView *g = [NSStackView stackViewWithViews:[@[cap, line] arrayByAddingObjectsFromArray:views]];
    g.orientation = NSUserInterfaceLayoutOrientationVertical; g.alignment = NSLayoutAttributeLeading; g.spacing = 8;
    [g setCustomSpacing:14 afterView:line];
    [line.widthAnchor constraintEqualToAnchor:g.widthAnchor].active = YES;
    return g;
}
// kind: 0 always enabled, 1 needs an editable sample, 2 needs an open bank
- (NSStackView *)barGroup:(NSString *)title keys:(NSArray<NSArray *> *)keys {
    NSMutableArray *btns = [NSMutableArray array];
    for (NSArray *k in keys) {
        NSButton *b = [self button:k[0] action:NSSelectorFromString(k[1])];   // same buttons as the Tools page
        if (k.count > 3) b.toolTip = k[3];
        if ([k[2] intValue] == 1) [_sampleBtns addObject:b]; else if ([k[2] intValue] == 2) [_bankBtns addObject:b];
        [btns addObject:b];
    }
    NSStackView *row = [NSStackView stackViewWithViews:btns]; row.spacing = 8;
    NSTextField *cap = [NSTextField labelWithString:title.uppercaseString];
    cap.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold]; cap.textColor = EDTheme.labelWhite;
    NSView *line = [NSView new]; line.wantsLayer = YES; line.layer.backgroundColor = EDTheme.accent.CGColor;
    [line.heightAnchor constraintEqualToConstant:2].active = YES;
    NSStackView *g = [NSStackView stackViewWithViews:@[cap, line, row]];
    g.orientation = NSUserInterfaceLayoutOrientationVertical; g.alignment = NSLayoutAttributeLeading; g.spacing = 8; [g setCustomSpacing:14 afterView:line];
    [line.widthAnchor constraintEqualToAnchor:g.widthAnchor].active = YES;
    return g;
}
- (NSButton *)wideButton:(NSString *)title action:(SEL)sel {
    NSButton *b = [self button:title action:sel]; [b.widthAnchor constraintEqualToConstant:260].active = YES; return b;
}

// MARK: tabs and header readout

- (void)selectTabNamed:(NSString *)ident {
    if ([ident isEqual:@"editor"]) ident = @"samples";
    [_tabs selectTabViewItemWithIdentifier:ident];
    [self showPresetNote:[ident isEqual:@"presets"]];
    if ([ident isEqual:@"tools"]) { [self refreshMountedImages]; [self refreshLinkSettings]; }
    _cmdBar.hidden = _cmdRule.hidden = !([ident isEqual:@"disk"] || [ident isEqual:@"samples"]); [self updateCmdBarGroups:[ident isEqual:@"disk"]];
}
- (void)showPresetNote:(BOOL)show {
    _presetNote.hidden = YES; (void)show;   // the status line carries this help now
    // the note lines up with the LCD screen's left edge; that view only joins the hierarchy once its tab is shown
    if (show && !_presetNoteLeading) { _presetNoteLeading = [_presetNote.leadingAnchor constraintEqualToAnchor:_presetEditor.lcdView.leadingAnchor]; _presetNoteLeading.active = YES; }
}
// the readout line only belongs on Master > Overview
- (void)dealloc { @try { [_status removeObserver:self forKeyPath:@"stringValue"]; } @catch (NSException *e) {} }
// idle help line: what the current page is for
- (NSArray<NSString *> *)allHelp {
    return @[@"Open a disk image or a bank file.",
        @"Utilities: open banks from the sampler disk.",
        @"Bank: name, erase and auto-load the bank.",
        @"Setup: tuning, outputs and other settings.",
        @"FX: set up the effects board.",
        @"MIDI: mode, controllers and preferences.",
        @"Disk: browse a disk like the sampler's Disk screen. Return opens, Esc goes back, Load… brings a bank into the editor.",
        @"Samples: select a sample to see its waveform, set loops, audition it and edit it with the toolbar.",
        @"Presets: here you can edit presets, voices and zones, as in the sampler's Preset Edit menus. Changes go straight into the preset (Edit ▸ Undo works).",
        @"Tools: here you can make new floppy or hard disk images, open images from mounted drives and prepare a BlueSCSI SD card."];
}
// Escape always goes back to the page you came from
- (void)cancelOperation:(id)sender {
    while (_tabHistory.count) {
        NSInteger t = _tabHistory.lastObject.integerValue; [_tabHistory removeLastObject];
        if (t == _curTab) continue;
        _tabBack = YES; [_tabs selectTabViewItemAtIndex:t]; _tabBack = NO; _tabPicker.selectedSegment = t;
        if (t == 1) [self focusBrowser];
        return;
    }
}
- (NSString *)bankSummaryLine {
    if (!_bank) return @"No bank open";
    unsigned long long sb = 0; for (EDSample *sm in _bank.samples) sb += sm.left.length + sm.right.length;
    return [NSString stringWithFormat:@"%@  ·  %lu samples  ·  %@", _bankTitle ?: @"Bank", (unsigned long)_bank.samples.count, EMU3FormatBytes(sb)];
}
- (void)resetStatus { _status.stringValue = _tabPicker.selectedSegment == 2 ? [self bankSummaryLine] : [self pageHelp]; }   // a page change clears the last message
- (BOOL)isHelpText:(NSString *)s { return [[self allHelp] containsObject:s]; }
- (NSString *)sampleInfoLine:(EDSample *)sm {
    double rate = sm.sampleRate ?: 1;
    NSString *loop = sm.loopEnabled ? [NSString stringWithFormat:@"loop %lu–%lu%@", (unsigned long)sm.loopStart, (unsigned long)sm.loopEnd, sm.loopInRelease ? @" (in release)" : @""] : @"no loop";
    return [NSString stringWithFormat:@"S%03u  %@  ·  %u Hz  ·  %@  ·  %lu frames (%.3f s)  ·  %@%@", sm.number, sm.name ?: @"", sm.sampleRate, sm.isStereo ? @"stereo" : @"mono", (unsigned long)sm.frameCount, sm.frameCount / rate, loop, sm.locked ? @"  ·  locked" : @""];
}
- (NSString *)pageHelp {
    NSArray *h = [self allHelp]; NSInteger t = _tabPicker.selectedSegment;
    if (t == 0) { NSInteger m = _masterPicker.selectedSegment; return h[1 + MAX(0, MIN(4, m))]; }
    if (t == 2 && _sample) return [self sampleInfoLine:_sample];   // Samples page: facts about the selected sample
    if (t == 1) {   // Disk page: facts about the selected icon
        EDDiskItem *it = _diskHint.selectedItem;
        if (it.kind == EDDiskSample) return [self sampleInfoLine:it.node];
        if (it) {
            NSString *kind = it.kind == EDDiskBank ? @"Bank" : (it.kind == EDDiskFolder ? @"Folder" : @"Disk");
            NSMutableString *m = [NSMutableString stringWithFormat:@"%@ %@", kind, it.title];
            if (it.kind == EDDiskFolder) [m appendFormat:@"  ·  %lu entries", (unsigned long)((EDNode *)it.node).children.count];
            if (it.kind == EDDiskBank && it.node == _currentNode && _bank) [m appendFormat:@"  ·  %lu samples, %lu presets", (unsigned long)_bank.samples.count, (unsigned long)_bank.presets.count];
            if (it.subtitle.length && it.kind != EDDiskBank && it.kind != EDDiskFolder) [m appendFormat:@"  ·  %@", it.subtitle];
            return m;
        }
    }
    if (t == 2) return _bank ? @"Pick a sample from the list to see its waveform and facts." : @"Open a disk and load a bank on the Disk page, or use Open Bank.";
    if (t == 3 && !_bank) return @"Presets appear here once a bank is loaded.";
    if (t == 1 && !_fs && !_bank) return @"Use Open Disk, or pick a disk image here.";
    return h[5 + t];
}
- (void)refreshLCDVisibility {
    BOOL overview = _tabPicker.selectedSegment == 0 && _masterPicker.selectedSegment == 0;
    BOOL samples = _tabPicker.selectedSegment == 2;   // Samples: bank summary under the sample list, sample facts under the waveform
    BOOL split = overview || samples;
    _lcd.hidden = !split; _cmdBar.hidden = _cmdRule.hidden = _tabPicker.selectedSegment != 1 && _tabPicker.selectedSegment != 2;
    _statusWidth.active = split; _statusWide.active = !split;
    _statusLead.constant = overview ? 40 : (samples ? 2 : 14); _statusWidth.constant = overview ? 270 : 414;
    _lcdLead.constant = samples ? 424 : 350; _lcdTrail.constant = samples ? -2 : -501;
    _status.preferredMaxLayoutWidth = split ? _statusWidth.constant : 1500;
    if (samples) { _lcd.line1 = [self pageHelp]; _lcd.line2 = nil; }
    NSString *help = samples ? [self bankSummaryLine] : [self pageHelp], *cur = _status.stringValue;
    if (![cur isEqualToString:help] && (cur.length == 0 || [self isHelpText:cur] || [cur isEqualToString:_autoStatus])) _status.stringValue = help;
    _autoStatus = help;   // real messages stay until replaced
    for (NSTableView *t in @[_sampleTable]) { t.focusRingType = NSFocusRingTypeNone; t.enclosingScrollView.focusRingType = NSFocusRingTypeNone; }
}
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)o change:(NSDictionary *)c context:(void *)ctx {
    if (o == _status) [self refreshLCDVisibility]; else [super observeValueForKeyPath:kp ofObject:o change:c context:ctx];
}
- (void)updateCmdBarGroups:(BOOL)diskOnly {   // Disk shows only the file operations; Samples only the sample tools
    NSArray *gs = [(NSStackView *)_cmdBar views];
    for (NSUInteger i = 0; i < gs.count; i++) [gs[i] setHidden:i == 0 ? !diskOnly : diskOnly];   // File: Disk only; the rest: Samples only
}
- (IBAction)tabPicked:(id)sender { [_tabs selectTabViewItemAtIndex:_tabPicker.selectedSegment]; [self resetStatus]; [self showPresetNote:_tabPicker.selectedSegment == 3]; if (_tabPicker.selectedSegment == 4) { [self refreshMountedImages]; [self refreshLinkSettings]; } _cmdBar.hidden = _cmdRule.hidden = _tabPicker.selectedSegment != 1 && _tabPicker.selectedSegment != 2; [self updateCmdBarGroups:_tabPicker.selectedSegment == 1]; [self refreshLCDVisibility]; }
- (IBAction)showMasterTab:(id)s { [self selectTabNamed:@"master"]; }
- (IBAction)showDiskTab:(id)s { [self selectTabNamed:@"disk"]; }
- (IBAction)showSamplesTab:(id)s { [self selectTabNamed:@"samples"]; }
- (IBAction)showPresetsTab:(id)s { [self selectTabNamed:@"presets"]; }
// MARK: server setup (scsiid.txt, serve.txt, watch.txt in ~/Library/Application Support/EMU3)
static NSString *LinkDir(void) { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/EMU3"]; }
static NSString *LinkFile(NSString *n) { return [LinkDir() stringByAppendingPathComponent:n]; }
- (void)refreshLinkSettings {
    NSString *t = [NSString stringWithContentsOfFile:LinkFile(@"scsiid.txt") encoding:NSUTF8StringEncoding error:nil];
    NSInteger cur = t.length ? t.integerValue : 7, sampler = SamplerBusID(), host = HostBusID();
    [_linkSampler selectItemAtIndex:sampler]; [_linkHost selectItemAtIndex:host];
    [_linkID removeAllItems];
    for (int i = 0; i < 8; i++) if (i != sampler && i != host) [_linkID addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
    NSInteger ix = [_linkID indexOfItemWithTitle:[NSString stringWithFormat:@"%ld", (long)cur]]; [_linkID selectItemAtIndex:ix];   // -1 when the stored ID is taken: pick a free one
    NSArray *l = [[NSString stringWithContentsOfFile:LinkFile(@"serve.txt") encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"];
    NSString *img = l.count ? (NSString *)l[0] : @"";
    BOOL ro = l.count > 1 && [[(NSString *)l[1] lowercaseString] hasPrefix:@"ro"];
    [_linkAccess selectItemAtIndex:ro ? 1 : 0]; _linkAccess.enabled = img.length > 0;
    NSString *w = [[NSString stringWithContentsOfFile:LinkFile(@"watch.txt") encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"].firstObject;
    _linkServe.title = img.length ? @"Stop Serving" : @"Start Serving";
    _linkInfo.stringValue = [NSString stringWithFormat:@"Serving: %@\nImage folder: %@", img.length ? img.lastPathComponent : @"nothing", w.length ? w : @"~/EMU3 Images (default)"];
}
static NSInteger SamplerBusID(void) { NSString *v = [NSUserDefaults.standardUserDefaults stringForKey:@"SMDITarget"]; return v.length ? MAX(0, MIN(7, v.integerValue)) : 6; }
static NSInteger HostBusID(void) { id v = [NSUserDefaults.standardUserDefaults objectForKey:@"HostID"]; return v ? MAX(0, MIN(7, [v integerValue])) : 7; }
- (IBAction)linkBusChanged:(id)sender {
    NSInteger sm = _linkSampler.indexOfSelectedItem, host = _linkHost.indexOfSelectedItem;
    if (sm == host) { _status.stringValue = @"The sampler and the host cannot share a SCSI ID."; [self refreshLinkSettings]; return; }
    [NSUserDefaults.standardUserDefaults setObject:@(sm).stringValue forKey:@"SMDITarget"]; [NSUserDefaults.standardUserDefaults setObject:@(host) forKey:@"HostID"];
    _status.stringValue = [NSString stringWithFormat:@"Sampler is ID %ld, host (initiator) ID %ld. The host ID reaches the board through bluescsi.ini (Write bluescsi.ini…).", (long)sm, (long)host];
    [self refreshLinkSettings];
}
- (IBAction)linkSettingChanged:(id)sender {
    [NSFileManager.defaultManager createDirectoryAtPath:LinkDir() withIntermediateDirectories:YES attributes:nil error:nil];
    if (sender == _linkID) {
        NSInteger sid = _linkID.titleOfSelectedItem.integerValue;
        [[NSString stringWithFormat:@"%ld\n", (long)sid] writeToFile:LinkFile(@"scsiid.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
        _status.stringValue = [NSString stringWithFormat:@"The served disk answers at SCSI ID %ld. Rescan on the sampler.", (long)sid];
    } else {
        NSArray *l = [[NSString stringWithContentsOfFile:LinkFile(@"serve.txt") encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByString:@"\n"];
        if (((NSString *)l.firstObject).length) {
            [[NSString stringWithFormat:@"%@\n%@\n", l[0], _linkAccess.indexOfSelectedItem == 1 ? @"ro" : @"rw"] writeToFile:LinkFile(@"serve.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
            _status.stringValue = @"Access saved. It applies the next time serving starts.";
        }
    }
    [self refreshLinkSettings]; [self refreshMountedImages];
}
/// Start / stop serving: the helper watches serve.txt, so writing or clearing it starts or stops the disk on the board.
- (IBAction)toggleServing:(id)sender {
    [NSFileManager.defaultManager createDirectoryAtPath:LinkDir() withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cur = ServedImagePath();
    if (cur) {
        [NSUserDefaults.standardUserDefaults setObject:cur forKey:@"LastServedImage"];
        [@"" writeToFile:LinkFile(@"serve.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
        _status.stringValue = @"Stopped serving. The sampler no longer sees the disk."; [self refreshLinkSettings]; [self refreshMountedImages]; return;
    }
    NSString *img = _mountsIcons.selectedItem.url.path;   // the selected mount, else the open image, else the one served last
    if (![img.pathExtension.lowercaseString isEqualToString:@"hda"] && ![img.pathExtension.lowercaseString isEqualToString:@"img"]) img = nil;
    if (!img) img = _fs.imageURL.path;
    if (!img) img = [NSUserDefaults.standardUserDefaults stringForKey:@"LastServedImage"];
    if (!img || ![NSFileManager.defaultManager fileExistsAtPath:img]) {
        NSOpenPanel *p = [NSOpenPanel openPanel]; p.message = @"Choose the disk image to serve to the sampler"; p.canChooseDirectories = NO;
        if ([p runModal] != NSModalResponseOK) return; img = p.URL.path;
    }
    [[NSString stringWithFormat:@"%@\n%@\n", img, _linkAccess.indexOfSelectedItem == 1 ? @"ro" : @"rw"] writeToFile:LinkFile(@"serve.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    _status.stringValue = [NSString stringWithFormat:@"Serving %@ at SCSI ID %@.", img.lastPathComponent, BoardIDText()];
    [self refreshLinkSettings]; [self refreshMountedImages];
}
- (IBAction)chooseImageFolder:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseDirectories = YES; p.canChooseFiles = NO; p.canCreateDirectories = YES; p.prompt = @"Choose"; p.message = @"The folder the helper watches for disk images to serve";
    if ([p runModal] != NSModalResponseOK) return;
    [NSFileManager.defaultManager createDirectoryAtPath:LinkDir() withIntermediateDirectories:YES attributes:nil error:nil];
    [[p.URL.path stringByAppendingString:@"\n"] writeToFile:LinkFile(@"watch.txt") atomically:YES encoding:NSUTF8StringEncoding error:nil];
    _status.stringValue = @"Image folder saved."; [self refreshLinkSettings];
}
// disk images on mounted volumes (SD cards, drives): top level of each volume only
- (void)refreshMountedImages {
    __weak EDMainWindowController *weak = self;
    NSMutableArray<NSString *> *known = [NSMutableArray arrayWithArray:[NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"] ?: @[]];   // images the editor has opened
    if (_fs.imageURL.path) [known addObject:_fs.imageURL.path];
    NSString *served = ServedImagePath(), *boardID = BoardIDText();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager; NSMutableArray<EDDiskItem *> *found = [NSMutableArray array];
        // disks the Disk Manager helper serves to the sampler: mounted under ~/EMU3 Disks/<image name>
        NSString *mountsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"EMU3 Disks"];
        for (NSString *name in [fm contentsOfDirectoryAtPath:mountsDir error:nil]) {
            if ([name hasPrefix:@"."]) continue;
            NSString *mp = [mountsDir stringByAppendingPathComponent:name], *image = nil;
            for (NSString *k in known) if ([k.lastPathComponent.stringByDeletingPathExtension isEqualToString:name] && [fm fileExistsAtPath:k]) image = k;
            unsigned long long sz = image ? [[fm attributesOfItemAtPath:image error:nil] fileSize] : 0;
            NSString *size = sz ? [NSByteCountFormatter stringFromByteCount:(long long)sz countStyle:NSByteCountFormatterCountStyleFile] : @"size unknown";
            BOOL isServed = served && [served.lastPathComponent.stringByDeletingPathExtension isEqualToString:name];
            EDDiskItem *it = [EDDiskItem new]; it.kind = EDDiskHard; it.title = name; it.subtitle = isServed ? [NSString stringWithFormat:@"served · ID %@", boardID] : @"mounted"; it.url = image ? [NSURL fileURLWithPath:image] : nil;
            it.node = [NSString stringWithFormat:@"%@ — %@, mounted at %@\nImage: %@ · %@%@", name, isServed ? @"served to the sampler" : @"mounted on this Mac, not served", mp, image ?: @"not opened in the editor yet (open it once to see where it sits)", size, isServed ? [NSString stringWithFormat:@" · SCSI ID: %@ (Server setup)", boardID] : @""];
            [found addObject:it];
        }
        for (NSString *vol in [fm contentsOfDirectoryAtPath:@"/Volumes" error:nil]) {
            NSString *vp = [@"/Volumes" stringByAppendingPathComponent:vol];
            if ([[fm destinationOfSymbolicLinkAtPath:vp error:nil] isEqualToString:@"/"]) continue;   // the startup disk alias
            BOOL ini = [fm fileExistsAtPath:[vp stringByAppendingPathComponent:@"bluescsi.ini"]];
            for (NSString *n in [fm contentsOfDirectoryAtPath:vp error:nil]) {
                NSString *ext = n.pathExtension.lowercaseString;
                if ([n hasPrefix:@"."] || !([ext isEqualToString:@"hda"] || [ext isEqualToString:@"img"])) continue;
                NSString *fp = [vp stringByAppendingPathComponent:n]; unsigned long long sz = [[fm attributesOfItemAtPath:fp error:nil] fileSize];
                NSString *base = n.stringByDeletingPathExtension, *idText = @"none";   // BlueSCSI takes the SCSI ID from HD<id><lun>_…
                NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(?:HD|CD|FD)([0-7])[0-7]" options:NSRegularExpressionCaseInsensitive error:nil];
                NSTextCheckingResult *m = [re firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
                if (m) idText = [base substringWithRange:[m rangeAtIndex:1]];
                NSString *size = [NSByteCountFormatter stringFromByteCount:(long long)sz countStyle:NSByteCountFormatterCountStyleFile];
                EDDiskItem *it = [EDDiskItem new]; it.kind = sz <= 4 * 1024 * 1024 ? EDDiskFloppy : EDDiskHard; it.title = base;
                it.subtitle = m ? [NSString stringWithFormat:@"ID %@ · %@", idText, size] : size; it.url = [NSURL fileURLWithPath:fp];
                it.node = [NSString stringWithFormat:@"%@\nOn %@ (%@) · %@ · SCSI ID: %@%@", n, vol, vp, size, idText, ini ? @" · bluescsi.ini on the card" : @" · no bluescsi.ini on the card"];
                [found addObject:it];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ EDMainWindowController *me = weak; if (!me) return; me->_mountsIcons.items = found; me->_mountsIcons.selectedIndex = found.count ? 0 : -1; [me mountsSelectionChanged]; });
    });
}
- (void)showImageOnDisk:(NSURL *)u { [self openImageAtURL:u]; [self selectTabNamed:@"disk"]; _tabPicker.selectedSegment = 1; }
- (void)mountsSelectionChanged { EDDiskItem *it = _mountsIcons.selectedItem; _mountsDetail.stringValue = it ? (NSString *)it.node : @" "; }
- (IBAction)showToolsTab:(id)s { [self selectTabNamed:@"tools"]; }
- (IBAction)writeBlueSCSIIni:(id)s { __weak EDMainWindowController *weak = self; [EDBlueSCSIIni runWithImage:_fs.imageURL status:^(NSString *t) { EDMainWindowController *me = weak; if (me) me->_status.stringValue = t; }]; }
- (NSString *)samplerSignature {
    NSURL *d = [self samplerDiskFolder];
    NSInteger boards = 0; for (NSString *n in [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/dev" error:nil]) if ([n hasPrefix:@"cu.usbmodem"]) boards++;
    return [NSString stringWithFormat:@"%@|%ld", d.path, (long)boards];
}
- (void)startStatusWatch {
    if (_statusTimer) return;
    _statusSig = [self samplerSignature];
    __weak typeof(self) w = self;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) {
        EDMainWindowController *me = w; if (!me) { [t invalidate]; return; }
        if (me->_statusBusy) return;
        me->_statusBusy = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{   // the NFS volume can stall: never touch it on the main thread
            NSString *sig = [me samplerSignature];
            dispatch_async(dispatch_get_main_queue(), ^{
                me->_statusBusy = NO;
                if (![sig isEqualToString:me->_statusSig]) { me->_statusSig = sig; [me refreshSamplerStatus]; }
            });
        });
    }];
}
- (void)refreshSamplerStatus {
    [self startStatusWatch];
    NSURL *d = [self samplerDiskFolder]; NSURL *root = [d.lastPathComponent isEqual:@"Default Folder"] ? d.URLByDeletingLastPathComponent : d;
    NSArray *ports = [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/dev" error:nil];
    NSInteger boards = 0; for (NSString *n in ports) if ([n hasPrefix:@"cu.usbmodem"]) boards++;
    NSFont *f = _samplerStatus.font ?: [NSFont systemFontOfSize:13];
    NSMutableAttributedString *as = [NSMutableAttributedString new];
    void (^line)(BOOL, NSString *) = ^(BOOL on, NSString *t) {
        if (as.length) [as appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: f}]];
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:on ? @"● " : @"○ " attributes:@{NSFontAttributeName: f,
            NSForegroundColorAttributeName: on ? [NSColor systemGreenColor] : NSColor.secondaryLabelColor}]];
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:t attributes:@{NSFontAttributeName: f, NSForegroundColorAttributeName: NSColor.labelColor}]];
    };
    line(root != nil, root ? [NSString stringWithFormat:@"Disk served: %@", root.lastPathComponent] : @"No sampler disk mounted");
    line(boards > 0, boards ? @"SCSI board connected" : @"SCSI board not found");
    _samplerStatus.attributedStringValue = as;
    [_home reloadWithSamplerDisk:d];
    [self refreshDiskIcons];
}
- (IBAction)autoSaveToggled:(NSButton *)b {
    [NSUserDefaults.standardUserDefaults setBool:b.state == NSControlStateValueOn forKey:@"AutoSaveToSampler"]; [self scheduleAutoSave];
}
/// Opt-in: a bank that lives on the sampler's disk is written back 3 s after the last edit, without reloading it.
- (void)scheduleAutoSave {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoSaveNow) object:nil];
    if (_autoSaveBtn.state != NSControlStateValueOn || !_bank.dirty || !_standaloneURL || ![self urlIsOnSamplerDisk:_standaloneURL]) return;
    [self performSelector:@selector(autoSaveNow) withObject:nil afterDelay:3];
}
- (void)autoSaveNow {
    if (!_bank.dirty || !_standaloneURL) return;
    NSError *e = nil; NSData *out = [_bank serializeWithError:&e];
    if (!out) { _status.stringValue = @"Auto-save failed: cannot serialize the bank"; return; }
    if (!_autoBackedUp) { [self backupOriginal]; _autoBackedUp = YES; }
    if (![out ed_writeToURL:_standaloneURL error:&e]) { _status.stringValue = [@"Auto-save failed: " stringByAppendingString:e.localizedDescription ?: @"write error"]; return; }
    [_bank markClean]; [self updateTitle]; [self modelChanged];
    _status.stringValue = [NSString stringWithFormat:@"Auto-saved %@ to the sampler disk (%@) — rescan the SCSI bus on the sampler, then load the bank", _bankTitle, EMU3FormatBytes(out.length)];
}
- (IBAction)showAssignKeys:(id)s { [EDUtils showAssignKeysIn:self.window]; }
- (IBAction)showChannelVolume:(id)s { [EDUtils showChannelVolumeIn:self.window]; }
- (IBAction)showTones:(id)s { [EDUtils showTonesIn:self.window]; }
- (void)showMasterPage:(NSInteger)i {
    [self selectTabNamed:@"master"]; _masterPicker.selectedSegment = i; [self masterPicked:_masterPicker];
}
- (IBAction)masterPicked:(NSSegmentedControl *)s {
    NSInteger i = s.selectedSegment; [self resetStatus]; _masterOverview.hidden = i != 0; _midiEditor.hidden = i == 0; [self refreshLCDVisibility];
    if (i > 0) { [_midiEditor setMenu:@[@"", @"Bank", @"Setup", @"FX", @"MIDI"][i]]; [_midiEditor reload]; }
}
- (IBAction)showMIDITab:(id)s { [self showMasterPage:4]; }
- (IBAction)showSetupTab:(id)s { [self showMasterPage:2]; }
- (IBAction)showFXTab:(id)s { if (self.fxBoardInstalled) [self showMasterPage:3]; }
// The sampler cannot tell the editor whether the effects board is fitted, so the FX page is switched on by View > FX Board Installed.
- (BOOL)fxBoardInstalled { return [NSUserDefaults.standardUserDefaults boolForKey:@"FXBoardInstalled"]; }
- (void)applyFXBoardSetting {
    BOOL on = self.fxBoardInstalled;
    [_masterPicker setEnabled:on forSegment:3];
    [_masterPicker setToolTip:on ? nil : @"FX needs the effects board: turn on View ▸ FX Board Installed"];
    if (!on && _masterPicker.selectedSegment == 3) { _masterPicker.selectedSegment = 0; [self masterPicked:_masterPicker]; }
}
- (IBAction)toggleFXBoard:(id)s { [NSUserDefaults.standardUserDefaults setBool:!self.fxBoardInstalled forKey:@"FXBoardInstalled"]; [self applyFXBoardSetting]; }
- (IBAction)showBankTab:(id)s { [self showMasterPage:1]; }
- (IBAction)clearAllPresets:(id)s { [self masterAction:@"erasePresets"]; }
- (void)masterAction:(NSString *)name {
    if ([name isEqual:@"saveAs"]) { [self saveBankAs:nil]; return; }
    if ([name isEqual:@"eraseAll"] && _bank) {
        if (![EDTheme confirm:[NSString stringWithFormat:@"Erases all Presets and Samples of this bank (%lu presets, %lu samples). Nothing is written until you save; reopen the bank to get it back. Continue?", (unsigned long)_bank.presets.count, (unsigned long)_bank.samples.count] okTitle:@"OK" cancelTitle:@"Cancel"]) return;
        [_player stop]; [_bank eraseAllPresetsAndSamples]; _sample = nil;
        [_sampleTable reloadData]; [self selectSample:nil];
        _presetEditor.bank = _bank; _midiEditor.bank = _bank; [self refreshBankStatus]; [self updateTitle]; [self modelChanged];
        return;
    }
    if ([name isEqual:@"erasePresets"] && _bank) {
        if (![EDTheme confirm:[NSString stringWithFormat:@"Erases all %lu Presets of this bank. The Samples are kept. Continue?", (unsigned long)_bank.presets.count] okTitle:@"OK" cancelTitle:@"Cancel"]) return;
        for (EDPreset *p in [_bank.presets copy]) [_bank removePreset:p];
        _presetEditor.bank = _bank; _midiEditor.bank = _bank; [self refreshBankStatus]; [self updateTitle]; [self modelChanged];
    }
}
/// The disk image the Disk Manager's helper is serving to the sampler (its first command-line argument).
- (nullable NSURL *)servedImageURL {
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/bin/ps"]; t.arguments = @[@"-axww", @"-o", @"args="];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![t launchAndReturnError:nil]) return nil;
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    NSString *out = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        NSRange r = [line rangeOfString:@"emu3nfs "]; if (r.location == NSNotFound) continue;
        NSString *rest = [line substringFromIndex:NSMaxRange(r)];
        NSRange e = [rest rangeOfString:@".hda" options:NSCaseInsensitiveSearch]; if (e.location == NSNotFound) { e = [rest rangeOfString:@".img" options:NSCaseInsensitiveSearch]; if (e.location == NSNotFound) continue; }
        NSString *path = [rest substringToIndex:NSMaxRange(e)];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) return [NSURL fileURLWithPath:path];
    }
    return nil;
}
- (void)openDiskItem:(EDDiskItem *)it {
    if (it.sampler) {
        NSURL *img = [self servedImageURL];
        if (img) { [self openImageAtURL:img]; return; }
        [self selectTabNamed:@"master"]; return;
    }
    if (it.url) [self openImageAtURL:it.url];
}
/// The drives the Disk page shows while no image is open: the disk the sampler sees, and recently opened images.
/// BlueSCSI takes the SCSI ID from the name: HD<id><lun>_… (also CD / FD); nil when the name does not say.
static NSString *ScsiIDFromName(NSString *name) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(?:HD|CD|FD)([0-7])[0-7]" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    return m ? [name substringWithRange:[m rangeAtIndex:1]] : nil;
}
/// The SCSI ID the board's served disk answers at (scsiid.txt, default 7) and the image named in serve.txt.
static NSString *BoardIDText(void) {
    NSString *t = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/EMU3/scsiid.txt"] encoding:NSUTF8StringEncoding error:nil];
    return [NSString stringWithFormat:@"%ld", t.length ? (long)MAX(0, MIN(7, t.integerValue)) : 7L];
}
static NSString *ServedImagePath(void) {
    NSString *t = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/EMU3/serve.txt"] encoding:NSUTF8StringEncoding error:nil];
    NSString *p = [[t componentsSeparatedByString:@"\n"].firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return p.length ? p : nil;
}
static NSString *SizeText(unsigned long long b) { return [NSByteCountFormatter stringFromByteCount:(long long)b countStyle:NSByteCountFormatterCountStyleFile]; }
- (void)refreshDiskIcons {
    NSMutableArray *items = [NSMutableArray array];
    NSURL *d = [self samplerDiskFolder]; NSURL *root = [d.lastPathComponent isEqual:@"Default Folder"] ? d.URLByDeletingLastPathComponent : d;
    if (root) { EDDiskItem *it = [EDDiskItem new]; it.kind = EDDiskHard; it.title = root.lastPathComponent; it.subtitle = [NSString stringWithFormat:@"served · ID %@", BoardIDText()]; it.sampler = YES; it.url = root; [items addObject:it]; }
    for (NSString *path in [NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        EDDiskItem *it = [EDDiskItem new]; NSString *ext = path.pathExtension.lowercaseString;
        unsigned long long sz = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil] fileSize];
        BOOL floppy = sz > 0 && sz <= 4u * 1024 * 1024;
        it.kind = [ext isEqual:@"iso"] ? EDDiskCD : (floppy ? EDDiskFloppy : EDDiskHard); it.title = [@[@"img", @"hda"] containsObject:ext] ? path.lastPathComponent.stringByDeletingPathExtension : path.lastPathComponent; { NSString *sid = ScsiIDFromName(path.lastPathComponent); it.subtitle = [NSString stringWithFormat:@"%@%@", sid ? [NSString stringWithFormat:@"ID %@ · ", sid] : @"", SizeText(sz)]; } it.url = [NSURL fileURLWithPath:path]; [items addObject:it];
    }
    _diskItems = items; [self refreshBrowser];
}
- (IBAction)showSamplerDisk:(id)s {
    NSURL *d = [self samplerDiskFolder];
    if (!d) { [EDTheme notice:@"No sampler disk is mounted. Start the Disk Manager helper and serve a disk image; it appears under ~/EMU3 Disks."]; return; }
    if ([d.lastPathComponent isEqual:@"Default Folder"]) d = d.URLByDeletingLastPathComponent;   // show the disk itself, not a folder inside it
    [NSWorkspace.sharedWorkspace openURL:d];
}

- (void)updateLCD {
    NSString *disk = _fs ? _fs.imageURL.lastPathComponent : nil;
    NSString *l1 = _bank ? [NSString stringWithFormat:@"%@%@%@", disk ? [disk stringByAppendingString:@" ▸ "] : @"", _bankTitle, _bank.dirty ? @"  •" : @""]
                         : (disk ?: @"No disk or bank open");
    NSString *l2;
    if (_sample) l2 = [NSString stringWithFormat:@"S%03u  %@   %u Hz", _sample.number, _sample.name, _sample.sampleRate];
    else if (_bank) l2 = [NSString stringWithFormat:@"%lu samples · %lu presets", (unsigned long)_bank.samples.count, (unsigned long)_bank.presets.count];
    else l2 = @"Open a disk image or bank file to begin";
    _lcd.line1 = l1; _lcd.line2 = l2; [self refreshLCDVisibility];
    for (NSButton *b in _sampleBtns) b.enabled = _sample && !_sample.locked;
    for (NSButton *b in _bankBtns) b.enabled = _bank != nil;
    NSMutableString *m = [NSMutableString string];
    if (disk) [m appendFormat:@"Disk: %@\n", disk];
    if (_bank) [m appendFormat:@"Bank: %@\n%lu samples, %lu presets\n%@", _bankTitle, (unsigned long)_bank.samples.count, (unsigned long)_bank.presets.count, _bank.dirty ? @"Unsaved changes" : @"No unsaved changes"];
    else [m appendString:@"No bank open."];
    _masterSummary.stringValue = m;
    [self applyBrowserVisibility];
    double pBytes = 0, sBytes = 0;
    for (EDPreset *p in _bank.presets) pBytes += p.raw.length;
    for (EDSample *sm in _bank.samples) sBytes += sm.left.length + sm.right.length;
    _memory.presetUsedK = pBytes / 1024; _memory.sampleUsedMB = sBytes / 1048576;
    [self refreshSamplerStatus];
}

// MARK: opening

- (BOOL)openURL:(NSURL *)url {
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext hasPrefix:@"e4b"] || [ext isEqualToString:@"e3b"]) return [self openBankFileAtURL:url];
    if ([ext isEqualToString:@"hda"] || [ext isEqualToString:@"iso"] || [ext isEqualToString:@"img"]) return [self openImageAtURL:url];
    // files on the sampler's disk have no extension: tell a bank from a disk image by its first bytes
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:url error:nil]; NSData *head = [fh readDataOfLength:16]; [fh closeFile];
    if (head.length >= 12) {
        const char *b = head.bytes;
        if ((memcmp(b, "FORM", 4) == 0 && memcmp(b + 8, "E4B", 3) == 0) || memcmp(b, "EMULATOR 3X", 11) == 0 || memcmp(b, "EMU SI-32 v3", 12) == 0) return [self openBankFileAtURL:url];
    }
    return [self openImageAtURL:url];
}

- (IBAction)openDiskImage:(id)sender {
    if (![self confirmDiscard]) return;
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.message = @"Choose an E-mu EOS disk image (.hda / .iso / .img)";
    if ([p runModal] == NSModalResponseOK) [self openImageAtURL:p.URL];
}
/// A blank 1.44 MB floppy volume in the EOS file system: saved where the user chooses, then opened as a disk.
- (IBAction)newFloppyImage:(id)sender {
    if (![self confirmDiscard]) return;
    NSSavePanel *p = [NSSavePanel savePanel]; p.message = @"Name the new 1.44 MB floppy image"; p.title = @"New Floppy Image";
    p.nameFieldLabel = @"Floppy name:"; p.nameFieldStringValue = @"Floppy 1.img"; p.allowsOtherFileTypes = YES; p.canCreateDirectories = YES; p.extensionHidden = NO;
    if ([p runModal] != NSModalResponseOK) return;
    NSError *e = nil;
    if (![EMU3Filesystem createFormattedImageAtURL:p.URL sizeBytes:1474560 error:&e]) { [self alertError:e title:@"Could not create the floppy image"]; return; }
    [self openImageAtURL:p.URL];
}
// MARK: disk tools: rename, new hard disk image, copy to a BlueSCSI card

/// A small "enter a name" dialog (nil when cancelled or empty).
- (NSString *)askText:(NSString *)title message:(NSString *)msg initial:(NSString *)initial {
    EDAlert *a = [EDAlert new]; a.messageText = title; a.informativeText = msg ?: @"";
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)]; f.stringValue = initial ?: @""; a.accessoryView = f;
    [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"]; a.initialFirstResponder = f;
    if ([a runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *t = [f.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]; return t.length ? t : nil;
}
static BOOL PathTo(EDNode *cur, EDNode *target, NSMutableArray<NSString *> *out) {
    if (cur == target) return YES;
    for (EDNode *c in cur.children) if (!c.file) { [out addObject:c.title]; if (PathTo(c, target, out)) return YES; [out removeLastObject]; }
    return NO;
}
/// Re-reads the open image (after a rename changed it) and goes back to the folder that was showing.
- (void)reopenImagePreservingBrowse {
    NSURL *u = _fs.imageURL; NSMutableArray *titles = [NSMutableArray array];
    if (_browseNode && _rootNode) PathTo(_rootNode, _browseNode, titles);
    [self closeBank]; [_fs closeImage]; _fs = nil; _rootNode = nil; _browseNode = nil; _inBank = NO;
    if (![self openImageAtURL:u]) return;
    EDNode *n = _rootNode;
    for (NSString *t in titles) { EDNode *next = nil; for (EDNode *c in n.children) if (!c.file && [c.title isEqual:t]) next = c; if (!next) break; n = next; }
    _browseNode = n; [self refreshBrowser];
}
- (void)renameRecent:(NSString *)old to:(NSString *)new {
    NSMutableArray *r = [([NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"] ?: @[]) mutableCopy];
    NSUInteger i = [r indexOfObject:old]; if (i != NSNotFound) { r[i] = new; [NSUserDefaults.standardUserDefaults setObject:r forKey:@"RecentDisks"]; }
}
/// Utils > Rename…: a disk image file, or a folder / bank inside the open disk.
- (IBAction)browserRename:(id)s {
    EDDiskItem *it = _diskHint.selectedItem; if (!it) return;
    if (it.kind == EDDiskFolder || it.kind == EDDiskBank) {
        EDNode *n = it.node;
        if (_fs.isReadOnly) { [EDTheme notice:@"This disk is read-only."]; return; }
        NSString *name = [self askText:it.kind == EDDiskBank ? @"Rename bank" : @"Rename folder" message:@"New name (up to 15 characters):" initial:n.title]; if (!name) return;
        if (name.length > 15) { [EDTheme notice:@"E-mu names are limited to 15 characters."]; return; }
        if ([name isEqual:n.title]) return;
        if (![self confirmDiscard]) return;
        NSError *e = nil; BOOL ok = n.file ? [_fs renameFile:n.file newName:name inDirectory:_browseNode.directory error:&e] : [_fs renameDirectory:n.directory newName:name error:&e];
        if (!ok) { [self alertError:e title:@"Could not rename"]; return; }
        [_fs synchronizeToDisk:nil]; [self reopenImagePreservingBrowse]; return;
    }
    if (!it.url || it.sampler) { [EDTheme notice:@"The sampler's served disk is named by its folder; rename it in the Finder."]; return; }
    NSString *ext = it.url.pathExtension, *base = it.url.lastPathComponent.stringByDeletingPathExtension;
    NSString *name = [self askText:@"Rename disk image" message:@"New name:" initial:base]; if (!name) return;
    name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    NSURL *dst = [it.url.URLByDeletingLastPathComponent URLByAppendingPathComponent:ext.length ? [name stringByAppendingPathExtension:ext] : name];
    if ([dst.path isEqual:it.url.path]) return;
    if ([NSFileManager.defaultManager fileExistsAtPath:dst.path]) { [EDTheme notice:[NSString stringWithFormat:@"“%@” already exists in that folder.", dst.lastPathComponent]]; return; }
    BOOL wasOpen = _fs && [_fs.imageURL.path isEqual:it.url.path];
    if (wasOpen) { if (![self confirmDiscard]) return; [self closeBank]; [_fs closeImage]; _fs = nil; _rootNode = nil; _currentNode = nil; _browseNode = nil; _inBank = NO; [_outline reloadData]; }
    NSError *e = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:it.url toURL:dst error:&e]) { [self alertError:e title:@"Could not rename"]; if (wasOpen) [self openImageAtURL:it.url]; return; }
    [self renameRecent:it.url.path to:dst.path];
    if (wasOpen) [self openImageAtURL:dst]; else [self refreshDiskIcons];
}

/// New Disk Image: the EMU3 Disk Manager's panel (where, size, SCSI ID and BlueSCSI name, format), see EDNewImage.
- (IBAction)newDiskImage:(id)sender {
    if (![self confirmDiscard]) return;
    __weak EDMainWindowController *weak = self;
    [EDNewImage runWithStatus:^(NSString *t) { EDMainWindowController *me = weak; if (me) me->_status.stringValue = t; } completion:^(NSURL *u) { [weak openImageAtURL:u]; }];
}

/// The settings that made the E6400 see the BlueSCSI as a disk (SCSI-1, no parity, no unit attention).
static NSString *const kMinimalBlueSCSIIni =
    @"; BlueSCSI settings for an E-mu sampler (written by EMU3 Editor)\n[SCSI]\nEnableUSBMassStorage=0\nEnableSCSI2=0\nEnableUnitAttention=0\nEnableParity=0\nEnableSelLatch=1\nQuirks=0\n";

/// Copies a disk image to a BlueSCSI SD card as HD<id>0_<name>.hda and writes a minimal bluescsi.ini if the card has none.
- (IBAction)copyToSDCard:(id)sender {
    NSURL *src = _fs.imageURL;
    EDDiskItem *sel = _browseNode ? nil : _diskHint.selectedItem; if (sel.url && !sel.sampler) src = sel.url;
    if (!src) { [EDTheme notice:@"Open a disk image (or select one on the Disk screen) first."]; return; }
    NSOpenPanel *op = [NSOpenPanel openPanel]; op.canChooseDirectories = YES; op.canChooseFiles = NO; op.canCreateDirectories = NO; op.directoryURL = [NSURL fileURLWithPath:@"/Volumes"];
    op.title = @"Copy to SD Card"; op.message = @"Choose the BlueSCSI SD card (its top folder)"; op.prompt = @"Choose Card";
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 36)];
    NSTextField *lab = [NSTextField labelWithString:@"SCSI ID of the disk:"]; lab.frame = NSMakeRect(8, 8, 130, 18);
    NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(142, 4, 70, 26) pullsDown:NO];
    for (int i = 0; i <= 5; i++) [pop addItemWithTitle:[NSString stringWithFormat:@"%d", i]]; [pop selectItemAtIndex:2];
    [acc addSubview:lab]; [acc addSubview:pop]; op.accessoryView = acc;
    if ([op runModal] != NSModalResponseOK) return;
    NSURL *card = op.URL; NSInteger sid = pop.indexOfSelectedItem;
    NSMutableString *clean = [NSMutableString string];
    for (NSUInteger i = 0; i < src.lastPathComponent.stringByDeletingPathExtension.length; i++) { unichar c = [src.lastPathComponent.stringByDeletingPathExtension characterAtIndex:i]; [clean appendString:(isalnum(c) || c == '-') && c < 128 ? [NSString stringWithCharacters:&c length:1] : @"_"]; }
    NSString *destName = [NSString stringWithFormat:@"HD%ld0_%@.hda", (long)sid, clean];
    NSString *prefix = [NSString stringWithFormat:@"HD%ld0", (long)sid];
    NSMutableArray<NSURL *> *old = [NSMutableArray array];
    for (NSURL *u in [NSFileManager.defaultManager contentsOfDirectoryAtURL:card includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]) if ([u.lastPathComponent hasPrefix:prefix]) [old addObject:u];
    NSNumber *sz = nil, *free = nil; [src getResourceValue:&sz forKey:NSURLFileSizeKey error:nil]; [card getResourceValue:&free forKey:NSURLVolumeAvailableCapacityForImportantUsageKey error:nil];
    if (free && sz && free.unsignedLongLongValue < sz.unsignedLongLongValue) { [EDTheme notice:@"The card does not have enough free space for this image."]; return; }
    NSMutableString *q = [NSMutableString stringWithFormat:@"Copy “%@” (%@) to the card “%@” as %@ (SCSI ID %ld)?", src.lastPathComponent, EMU3FormatBytes(sz.unsignedLongLongValue), card.lastPathComponent, destName, (long)sid];
    if (old.count) { [q appendString:@"\n\nThis replaces:"]; for (NSURL *u in old) [q appendFormat:@"\n  %@", u.lastPathComponent]; }
    if (![EDTheme confirm:q okTitle:@"Copy" cancelTitle:@"Cancel"]) return;
    if (_fs && [_fs.imageURL.path isEqual:src.path]) [_fs synchronizeToDisk:nil];
    _status.stringValue = [NSString stringWithFormat:@"Copying %@ to the card…", src.lastPathComponent];
    NSURL *dst = [card URLByAppendingPathComponent:destName], *ini = [card URLByAppendingPathComponent:@"bluescsi.ini"];
    __weak EDMainWindowController *weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager; NSError *err = nil; BOOL ok = YES; BOOL wroteIni = NO;
        for (NSURL *u in old) [fm removeItemAtURL:u error:nil];
        ok = [fm copyItemAtURL:src toURL:dst error:&err];
        if (ok && ![fm fileExistsAtPath:ini.path]) wroteIni = [kMinimalBlueSCSIIni writeToURL:ini atomically:YES encoding:NSUTF8StringEncoding error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            EDMainWindowController *me = weak; if (!me) return;
            if (!ok) { me->_status.stringValue = @"Copy to the card failed."; [me alertError:err title:@"Could not copy to the card"]; return; }
            me->_status.stringValue = [NSString stringWithFormat:@"Copied to the card as %@.", destName];
            [EDTheme notice:[NSString stringWithFormat:@"Done: %@ is on the card.%@\n\nEject the card in the Finder before taking it out.", destName, wroteIni ? @"\nA minimal bluescsi.ini was added (the card had none)." : @""]];
        });
    });
}
- (IBAction)openBankFile:(id)sender {
    if (![self confirmDiscard]) return;
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.message = @"Choose an E4B bank file";
    if ([p runModal] == NSModalResponseOK) [self openBankFileAtURL:p.URL];
}

- (BOOL)openImageAtURL:(NSURL *)url {
    if (![self confirmDiscard]) return NO;
    NSError *e = nil;
    EMU3Filesystem *fs = [[EMU3Filesystem alloc] initWithURL:url error:&e];
    if (!fs) { [self alertError:e title:@"Could not open the disk image"]; return NO; }
    [_fs closeImage];
    { NSMutableArray *r = [([NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"] ?: @[]) mutableCopy]; [r removeObject:url.path]; [r insertObject:url.path atIndex:0]; while (r.count > 8) [r removeLastObject]; [NSUserDefaults.standardUserDefaults setObject:r forKey:@"RecentDisks"]; }
    _fs = fs; _standaloneURL = nil;
    _rootNode = [self nodeForDirectory:fs.rootDirectory title:url.lastPathComponent path:@[]];
    [self closeBank];
    [_outline reloadData]; [_outline expandItem:_rootNode]; _browseNode = _rootNode; [self refreshBrowser];
    _status.stringValue = [NSString stringWithFormat:@"%@ — %@ free of %@", url.lastPathComponent,
        EMU3FormatBytes((unsigned long long)fs.freeBlocks * 512), EMU3FormatBytes((unsigned long long)fs.totalBlocks * 512)];
    self.window.title = [@"EMU3 Editor — " stringByAppendingString:url.lastPathComponent];
    [self updateLCD]; [self selectTabNamed:@"disk"];
    return YES;
}

- (BOOL)openBankFileAtURL:(NSURL *)url {
    NSError *e = nil;
    NSData *d = [NSData dataWithContentsOfURL:url options:0 error:&e];
    if (!d) { [self alertError:e title:@"Could not read the file"]; return NO; }
    [_fs closeImage]; _fs = nil; _rootNode = nil; _currentNode = nil; _browseNode = nil; _inBank = NO; [_outline reloadData]; [self refreshBrowser];
    _standaloneURL = url;
    BOOL ok = [self loadBankData:d title:url.lastPathComponent];
    if (ok) { [EDHomeList noteRecent:url]; [self selectTabNamed:@"samples"]; }
    return ok;
}

- (EDNode *)nodeForDirectory:(EMU3Directory *)dir title:(NSString *)title path:(NSArray<NSString *> *)path {
    EDNode *n = [EDNode new]; n.title = title; n.directory = dir; n.path = path; n.children = [NSMutableArray array];
    NSArray *sub = [path arrayByAddingObject:title];
    for (EMU3Directory *d in dir.subdirectories) [n.children addObject:[self nodeForDirectory:d title:d.name path:sub]];
    for (EMU3File *f in dir.files) {
        if (f.isDeleted || f.fileType != EMU3FileTypeBank) continue;
        EDNode *c = [EDNode new]; c.title = f.name; c.file = f; c.path = sub; [n.children addObject:c];
    }
    return n;
}

- (BOOL)loadBankData:(NSData *)data title:(NSString *)title {
    NSError *e = nil;
    EDBank *bank = [EDBank bankWithData:data error:&e];
    if (!bank) {
        NSString *msg = e.localizedDescription;
        if ([data length] >= 16 && memcmp(data.bytes, "EMULATOR", 8) == 0) msg = @"This is an Emulator III / 3X format bank. Editing of that format is not implemented yet.";
        [self alertError:[NSError errorWithDomain:EDErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: msg}] title:@"Cannot edit this bank"];
        return NO;
    }
    [_player stop];
    _originalData = data; _autoBackedUp = NO; _bank = bank; _bankTitle = title; _midiEditor.bankTitle = title; _sample = nil;
    [self.window.undoManager removeAllActions];
    [_sampleTable reloadData]; _presetEditor.bank = bank; _midiEditor.bank = bank;
    if (bank.samples.count) {
        [_sampleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        // row 0 may already have been selected in the previous bank, in which case no selection notification fires
        if (_sample != bank.samples.firstObject) [self selectSample:bank.samples.firstObject];
    } else [self selectSample:nil];
    self.window.documentEdited = NO;
    [self updateTitle];
    [self.window makeFirstResponder:_sampleTable];
    _status.stringValue = [NSString stringWithFormat:@"%@ [%@]: %lu samples, %lu presets", title,
        [bank.formType isEqualToString:@"3X"] ? @"Emulator 3X / ESI-32" : @"EOS E4B", (unsigned long)bank.samples.count, (unsigned long)bank.presets.count];
    [self modelChanged];
    return YES;
}

- (void)refreshBankStatus {
    if (!_bank) return;
    _status.stringValue = [NSString stringWithFormat:@"%@ [%@]: %lu samples, %lu presets", _bankTitle,
        [_bank.formType isEqualToString:@"3X"] ? @"Emulator 3X / ESI-32" : @"EOS E4B", (unsigned long)_bank.samples.count, (unsigned long)_bank.presets.count];
}
- (void)closeBank { _inBank = NO; [_player stop]; _midiEditor.bankTitle = nil; _bank = nil; _sample = nil; _originalData = nil; _currentNode = nil; [_sampleTable reloadData]; _presetEditor.bank = nil; _midiEditor.bank = nil; [self selectSample:nil]; [self modelChanged]; }

- (void)updateTitle {
    NSString *base = _fs ? _fs.imageURL.lastPathComponent : @"";
    NSString *t = _bank ? (base.length ? [NSString stringWithFormat:@"%@ ▸ %@", base, _bankTitle] : _bankTitle) : (base.length ? base : @"");
    self.window.title = t.length ? [@"EMU3 Editor — " stringByAppendingString:t] : @"EMU3 Editor";
    self.window.documentEdited = _bank.dirty; [self scheduleAutoSave];
    [self modelChanged];
}

// sample names may have changed: refresh the preset editor's lookups when its tab is shown
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item {
    NSInteger now = [tv indexOfTabViewItem:item];
    if (!_tabHistory) _tabHistory = [NSMutableArray array];
    if (now != _curTab && !_tabBack) { [_tabHistory addObject:@(_curTab)]; if (_tabHistory.count > 30) [_tabHistory removeObjectAtIndex:0]; }
    _curTab = now;
    _tabPicker.selectedSegment = now; [self resetStatus]; [self updateLCD];
    if ([item.identifier isEqual:@"presets"]) [_presetEditor reload];
    if ([item.identifier isEqual:@"master"]) [self refreshSamplerStatus];
    if ([item.identifier isEqual:@"disk"]) [self focusBrowser];
}

// MARK: outline

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(EDNode *)item {
    return item ? (NSInteger)item.children.count : (_rootNode ? 1 : 0);
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(EDNode *)item { return item ? item.children[i] : _rootNode; }
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(EDNode *)item { return item.file == nil; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)c item:(EDNode *)item {
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] init]; cell.identifier = @"cell";
        NSTextField *t = [EDTheme lcdLabel:@""]; t.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:t]; cell.textField = t;
        NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageNamed:NSImageNameFolder]]; iv.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:iv]; cell.imageView = iv;
        [NSLayoutConstraint activateConstraints:@[
            [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor], [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16], [iv.heightAnchor constraintEqualToConstant:16],
            [t.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4], [t.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [t.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    cell.textField.stringValue = item.title;
    cell.imageView.image = [NSImage imageNamed:item.file ? NSImageNameMultipleDocuments : NSImageNameFolder];
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)n {
    EDNode *item = [_outline itemAtRow:_outline.selectedRow];
    if (!item || !item.file || item == _currentNode) return;
    [self loadBankNode:item];
}
/// Reads a bank from the open disk into the editor. NO when it was not loaded (unsaved changes kept, or a read error).
- (BOOL)loadBankNode:(EDNode *)item {
    if (!item.file || item == _currentNode) return item == _currentNode;
    if (![self confirmDiscard]) { [self restoreOutlineSelection]; return NO; }
    NSError *e = nil;
    NSData *d = [_fs dataForFile:item.file error:&e];
    if (!d) { [self alertError:e title:@"Could not read the bank"]; return NO; }
    if ([self loadBankData:d title:item.title]) { _currentNode = item; [self restoreOutlineSelection]; [self refreshBrowser]; return YES; }
    [self restoreOutlineSelection]; return NO;
}

// MARK: icon browser (Disk / Folder / Bank screens)

- (void)applyBrowserVisibility {
    _diskScroll.hidden = _listView; _outlineScroll.hidden = !_listView;
    BOOL hasSel = _diskHint.selectedItem != nil;
    _loadKey.enabled = hasSel; _infoKey.enabled = hasSel; _saveKey.enabled = _bank != nil && (!_inBank || hasSel);
}
/// Shows the disks (no folder chosen), or the folders and banks of the current folder.
- (void)refreshBrowser {
    NSString *label = @"DISK"; NSMutableArray *items = [NSMutableArray array];
    if (_inBank && _bank) {   // inside a bank: its samples, as on the sampler's Bank screen
        for (EDSample *sm in _bank.samples) { EDDiskItem *it = [EDDiskItem new]; it.kind = EDDiskSample; it.title = sm.name.length ? sm.name : [NSString stringWithFormat:@"Sample %u", sm.number]; it.tag = [NSString stringWithFormat:@"S%03u", sm.number]; it.loop = sm.loopEnabled; it.node = sm; [items addObject:it]; }
        label = @"SAMPLE"; _diskHint.emptyText = @"No samples in this bank.";
    } else if (_browseNode) {
        BOOL anyFolder = NO; int nBank = 0, nFolder = 0;
        for (EDNode *c in _browseNode.children) if (!c.file) anyFolder = YES;
        for (int pass = 0; pass < 2; pass++) for (EDNode *c in _browseNode.children) {
            if ((pass == 0) == (c.file == nil)) {
                EDDiskItem *it = [EDDiskItem new]; it.kind = c.file ? EDDiskBank : EDDiskFolder; it.title = c.title; it.node = c; it.tag = [NSString stringWithFormat:@"%c%02d", c.file ? 'B' : 'F', c.file ? nBank++ : nFolder++]; [items addObject:it];
            }
        }
        label = anyFolder ? @"FOLDER" : @"BANK";
        _diskHint.emptyText = @"Nothing here.";
    } else { [items addObjectsFromArray:_diskItems ?: @[]]; _diskHint.emptyText = @"No disks seen.\nOpen a disk image with Open Disk, or start the Disk Manager."; }
    [_diskSideTab setTitleString:label]; _diskHint.listMode = _bankList;
    _diskHint.items = items;
    NSInteger sel = -1;
    if (_browseNode) for (NSInteger i = 0; i < (NSInteger)items.count; i++) if (((EDDiskItem *)items[i]).node == _currentNode && _currentNode) sel = i;
    if (_inBank) { sel = -1; for (NSInteger i = 0; i < (NSInteger)items.count; i++) if (((EDDiskItem *)items[i]).node == _sample && _sample) sel = i; }
    if (sel < 0 && items.count) sel = 0;
    _diskHint.selectedIndex = sel;
    [_saveKey setTitle:_inBank ? @"Audition" : @"Save…"]; _saveKey.action = _inBank ? @selector(browserAudition:) : @selector(saveBank:);
    [self applyBrowserVisibility]; [self focusBrowser]; [self refreshLCDVisibility];
}
/// Keeps the keyboard on the icons (Return opens, Escape backs out) while the Disk page is showing, unless a text field is being edited.
- (void)focusBrowser {
    if (_listView || ![[_tabs.selectedTabViewItem identifier] isEqual:@"disk"] || !self.window.isVisible) return;
    if ([self.window.firstResponder isKindOfClass:NSText.class]) return;
    [self.window makeFirstResponder:_diskHint];
}
- (void)browserSelectionChanged {
    EDDiskItem *it = _diskHint.selectedItem;
    if (_inBank && it.kind == EDDiskSample && it.node != _sample) [self selectSample:it.node];   // keeps the Samples page and Audition on the same sample
    [self applyBrowserVisibility]; [self refreshLCDVisibility];
}
- (IBAction)browserAudition:(id)s { EDDiskItem *it = _diskHint.selectedItem; if (it.kind == EDDiskSample) { if (it.node != _sample) [self selectSample:it.node]; [self togglePlay:nil]; } }
/// Double-click / Return: open a disk, go into a folder, load a bank and show its samples.
- (void)openBrowserItem:(EDDiskItem *)it {
    if (it.kind == EDDiskFolder) { _browseNode = it.node; [self refreshBrowser]; return; }
    if (it.kind == EDDiskBank) { if ([self loadBankNode:it.node]) { _inBank = YES; [self refreshBrowser]; } return; }
    if (it.kind == EDDiskSample) { [self selectSample:it.node]; [self selectTabNamed:@"samples"]; _tabPicker.selectedSegment = 2; return; }
    [self openDiskItem:it];
}
- (IBAction)browserLoad:(id)s { EDDiskItem *it = _diskHint.selectedItem; if (!it) return; if (it.kind == EDDiskBank) { if ([self loadBankNode:it.node]) { _inBank = YES; [self refreshBrowser]; } } else [self openBrowserItem:it]; }
- (void)browserGoUp {
    if (_inBank) { _inBank = NO; [self refreshBrowser]; return; }
    if (!_browseNode) { [self cancelOperation:nil]; return; }   // top of the disk list: back to the previous page
    EDNode *parent = nil;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:_rootNode];
    while (stack.count) { EDNode *n = stack.lastObject; [stack removeLastObject]; if ([n.children containsObject:_browseNode]) { parent = n; break; } [stack addObjectsFromArray:n.children]; }
    _browseNode = parent;     // nil: back to the list of disks
    [self refreshBrowser];
}
- (IBAction)browserToggleView:(id)s {
    _bankList = !_bankList; _diskHint.listMode = _bankList; [self focusBrowser]; return;   // icons <-> list rows, at every level
    _listView = !_listView; [self applyBrowserVisibility]; if (_listView) [self.window makeFirstResponder:_outline]; else [self focusBrowser]; }
/// Info dialog: a heading and a two-column list of facts.
- (void)showInfo:(NSString *)heading rows:(NSArray<NSArray<NSString *> *> *)rows {
    NSMutableArray *grid = [NSMutableArray array];
    for (NSArray *r in rows) {
        NSTextField *k = [NSTextField labelWithString:r[0]]; k.font = [NSFont systemFontOfSize:12]; k.textColor = NSColor.secondaryLabelColor; k.alignment = NSTextAlignmentRight;
        NSTextField *v = [NSTextField labelWithString:r[1]]; v.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightMedium]; v.selectable = YES;
        [grid addObject:@[k, v]];
    }
    NSGridView *g = [NSGridView gridViewWithViews:grid]; g.rowSpacing = 6; g.columnSpacing = 14; [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing; [g columnAtIndex:1].xPlacement = NSGridCellPlacementLeading;
    NSSize fs = g.fittingSize; g.frame = NSMakeRect(0, 0, MAX(360, fs.width), fs.height);
    EDAlert *a = [EDAlert new]; a.messageText = heading; a.accessoryView = g; [a addButtonWithTitle:@"OK"]; [a runModal];
}
static NSString *Dur(double s) { return s < 1 ? [NSString stringWithFormat:@"%.0f ms", s * 1000] : [NSString stringWithFormat:@"%.3f s", s]; }
- (IBAction)browserInfo:(id)s {
    EDDiskItem *it = _diskHint.selectedItem; if (!it) return;
    if (it.kind == EDDiskSample) {
        EDSample *sm = it.node; double rate = sm.sampleRate ?: 1, secs = sm.frameCount / rate; NSUInteger ch = sm.isStereo ? 2 : 1;
        NSMutableArray *rows = [NSMutableArray arrayWithArray:@[
            @[@"Number", [NSString stringWithFormat:@"S%03u", sm.number]], @[@"Name", sm.name ?: @""],
            @[@"Sample rate", [NSString stringWithFormat:@"%u Hz", sm.sampleRate]], @[@"Channels", sm.isStereo ? @"Stereo" : @"Mono"],
            @[@"Length", [NSString stringWithFormat:@"%lu frames · %@", (unsigned long)sm.frameCount, Dur(secs)]],
            @[@"Size in memory", EMU3FormatBytes((unsigned long long)sm.frameCount * 2 * ch)]]];
        if (sm.loopEnabled) [rows addObject:@[@"Loop", [NSString stringWithFormat:@"%lu – %lu (%lu frames, %@)%@", (unsigned long)sm.loopStart, (unsigned long)sm.loopEnd, (unsigned long)(sm.loopEnd - sm.loopStart + 1), Dur((sm.loopEnd - sm.loopStart + 1) / rate), sm.loopInRelease ? @" · plays in release" : @""]]];
        else [rows addObject:@[@"Loop", @"Off"]];
        if (sm.locked) [rows addObject:@[@"Editing", @"Locked (layout not fully understood, saved back unchanged)"]];
        [self showInfo:[NSString stringWithFormat:@"Sample %@", sm.name ?: @""] rows:rows]; return;
    }
    NSString *kind = it.kind == EDDiskBank ? @"Bank" : (it.kind == EDDiskFolder ? @"Folder" : @"Disk");
    NSMutableArray *rows = [NSMutableArray arrayWithObject:@[@"Name", it.title ?: @""]];
    if (it.kind == EDDiskBank && it.node == _currentNode && _bank) {
        [rows addObject:@[@"Samples", [NSString stringWithFormat:@"%lu", (unsigned long)_bank.samples.count]]]; [rows addObject:@[@"Presets", [NSString stringWithFormat:@"%lu", (unsigned long)_bank.presets.count]]];
        unsigned long long sb = 0; for (EDSample *sm in _bank.samples) sb += sm.left.length + sm.right.length; [rows addObject:@[@"Sample data", EMU3FormatBytes(sb)]];
        [rows addObject:@[@"Changes", _bank.dirty ? @"Unsaved" : @"None"]];
    }
    if (it.kind == EDDiskFolder) [rows addObject:@[@"Entries", [NSString stringWithFormat:@"%lu", (unsigned long)((EDNode *)it.node).children.count]]];
    if (it.kind == EDDiskHard || it.kind == EDDiskFloppy || it.kind == EDDiskCD) {
        NSString *img = it.url.path;
        if (it.sampler) {   // the served disk: find the image behind the mount among the images the editor knows
            [rows addObject:@[@"Served to sampler", @"Yes"]]; [rows addObject:@[@"Mounted at", it.url.path ?: @""]]; img = nil;
            for (NSString *k in [NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"]) if ([k.lastPathComponent.stringByDeletingPathExtension isEqualToString:it.title] && [NSFileManager.defaultManager fileExistsAtPath:k]) img = k;
            if (!img && [_fs.imageURL.lastPathComponent.stringByDeletingPathExtension isEqualToString:it.title]) img = _fs.imageURL.path;
        }
        NSString *sid = it.sampler ? nil : ScsiIDFromName(img.lastPathComponent ?: it.title);
        if (it.sampler) [rows addObject:@[@"SCSI ID", [NSString stringWithFormat:@"%@ (set on Tools ▸ Server setup)", BoardIDText()]]];
        else [rows addObject:@[@"SCSI ID", sid ? [NSString stringWithFormat:@"%@ (from the name %@, for a BlueSCSI SD card)", sid, img.lastPathComponent ?: it.title] : @"not in the name (a BlueSCSI SD card wants HD<id>0_name.hda)"]];
        if (img) {
            unsigned long long sz = [[NSFileManager.defaultManager attributesOfItemAtPath:img error:nil] fileSize];
            [rows addObject:@[@"Image file", img]]; [rows addObject:@[@"Folder", img.stringByDeletingLastPathComponent]]; if (sz) [rows addObject:@[@"Image size", EMU3FormatBytes(sz)]];
            [rows addObject:@[@"Type", sz && sz <= 4u * 1024 * 1024 ? @"Floppy image" : ([img.pathExtension.lowercaseString isEqual:@"iso"] ? @"CD-ROM image" : @"Hard disk image")]];
        } else if (it.sampler) [rows addObject:@[@"Image file", @"not known (open the image once in the editor)"]];
    } else if (it.url) {
        [rows addObject:@[@"File", it.url.path]];
    }
    BOOL diskKind = it.kind == EDDiskHard || it.kind == EDDiskFloppy || it.kind == EDDiskCD;
    BOOL isOpen = !diskKind || [it.url.path isEqualToString:_fs.imageURL.path] || (it.sampler && [_fs.imageURL.lastPathComponent.stringByDeletingPathExtension isEqualToString:it.title]);
    if (_fs && isOpen) { [rows addObject:@[@"Free space", EMU3FormatBytes((unsigned long long)_fs.freeBlocks * 512)]]; [rows addObject:@[@"Disk size", EMU3FormatBytes((unsigned long long)_fs.totalBlocks * 512)]]; }
    [self showInfo:kind rows:rows];
}
- (void)popMenu:(NSMenu *)m from:(NSButton *)b { [EDTheme styleLCDMenu:m]; [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(b.bounds)) inView:b]; }
- (IBAction)browserUtilsMenu:(NSButton *)b {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Utils"];
    for (NSArray *a in @[@[@"Open Disk Image…", @"openDiskImage:"], @[@"Open Bank File…", @"openBankFile:"], @[@"Show Sampler Disk", @"showSamplerDisk:"]]) { NSMenuItem *i = [m addItemWithTitle:a[0] action:NSSelectorFromString(a[1]) keyEquivalent:@""]; i.target = self; }
    [self popMenu:m from:b];
}
- (IBAction)browserBrowseMenu:(NSButton *)b {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Browse"];
    NSMenuItem *up = [m addItemWithTitle:@"Up one level" action:@selector(browserUp:) keyEquivalent:@""]; up.target = self; up.enabled = _browseNode != nil;
    NSMenuItem *top = [m addItemWithTitle:@"Disks" action:@selector(browserTop:) keyEquivalent:@""]; top.target = self; top.enabled = _browseNode != nil;
    NSMenuItem *root = [m addItemWithTitle:@"Open disk's root" action:@selector(browserRoot:) keyEquivalent:@""]; root.target = self; root.enabled = _rootNode != nil && _browseNode != _rootNode;
    [self popMenu:m from:b];
}
- (IBAction)browserUp:(id)s { [self browserGoUp]; }
- (IBAction)browserTop:(id)s { _browseNode = nil; _inBank = NO; [self refreshBrowser]; }
- (IBAction)browserRoot:(id)s { _browseNode = _rootNode; [self refreshBrowser]; }
- (void)restoreOutlineSelection {
    NSInteger r = _currentNode ? [_outline rowForItem:_currentNode] : -1;
    if (r >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO]; else [_outline deselectAll:nil];
}
- (void)outlineDoubleClick:(id)s { EDNode *i = [_outline itemAtRow:_outline.clickedRow]; if (i.file && i == _currentNode) { [self selectTabNamed:@"samples"]; return; } if (i && !i.file) { if ([_outline isItemExpanded:i]) [_outline collapseItem:i]; else [_outline expandItem:i]; } }

// MARK: tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t {
    return t == _sampleTable ? (NSInteger)_bank.samples.count : (NSInteger)_bank.presets.count;
}
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r { return [EDTheme lcdRowView]; }
- (NSTableRowView *)outlineView:(NSOutlineView *)ov rowViewForItem:(id)item { return [EDTheme lcdRowView]; }
- (void)tableView:(NSTableView *)t willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    if ([cell isKindOfClass:[NSTextFieldCell class]]) { [(NSTextFieldCell *)cell setFont:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]]; [(NSTextFieldCell *)cell setTextColor:EDTheme.lcdInk]; [(NSTextFieldCell *)cell setDrawsBackground:NO]; [(NSTextFieldCell *)cell setBackgroundColor:NSColor.clearColor]; [(NSTextFieldCell *)cell setBezeled:NO]; [(NSTextFieldCell *)cell setBordered:NO]; }
}
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSString *k = c.identifier;
    if (t == _sampleTable) {
        EDSample *s = _bank.samples[r];
        if ([k isEqual:@"num"]) return [NSString stringWithFormat:@"%u", s.number];
        if ([k isEqual:@"name"]) return s.name;
        if ([k isEqual:@"rate"]) return [NSString stringWithFormat:@"%u", s.sampleRate];
        if ([k isEqual:@"len"]) return [NSString stringWithFormat:@"%lu", (unsigned long)s.frameCount];
        return s.loopEnabled ? @"●" : @"";
    }
    EDPreset *p = _bank.presets[r];
    return [k isEqual:@"num"] ? [NSString stringWithFormat:@"%u", p.number] : p.name;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object != _sampleTable) return;
    NSInteger r = _sampleTable.selectedRow;
    [self selectSample:(r >= 0 && r < (NSInteger)_bank.samples.count) ? _bank.samples[r] : nil];
}

// MARK: selection / inspector

- (void)selectSample:(EDSample *)s {
    [_player stop];
    _sample = s; _wave.sample = s;
    [self refreshAll];
    [self modelChanged];
}
- (void)refreshAll {
    BOOL has = _sample != nil;
    for (NSControl *c in @[_nameField, _rateField, _loopStartField, _loopEndField, _loopCheck, _releaseCheck]) c.enabled = has && !_sample.locked;
    _playButton.enabled = has && !_sample.locked;
    _nameField.stringValue = _sample.name ?: @"";
    _rateField.stringValue = has ? [NSString stringWithFormat:@"%u", _sample.sampleRate] : @"";
    _loopStartField.stringValue = has ? [NSString stringWithFormat:@"%lu", (unsigned long)_sample.loopStart] : @"";
    _loopEndField.stringValue = has ? [NSString stringWithFormat:@"%lu", (unsigned long)_sample.loopEnd] : @"";
    _loopCheck.state = _sample.loopEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _releaseCheck.state = _sample.loopInRelease ? NSControlStateValueOn : NSControlStateValueOff;
    if (has) {
        double dur = _sample.sampleRate ? (double)_sample.frameCount / _sample.sampleRate : 0;
        _info.stringValue = [NSString stringWithFormat:@"%lu frames · %.3f s · %@ · peak %.1f%%", (unsigned long)_sample.frameCount, dur,
            _sample.right ? @"stereo" : @"mono", [_sample peak] * 100];
    } else _info.stringValue = @"";
    [_wave setNeedsDisplay:YES]; [_wave.window invalidateCursorRectsForView:_wave];
    [self updateTitle];
    NSInteger row = _sample ? (NSInteger)[_bank.samples indexOfObject:_sample] : -1;
    if (row >= 0) [_sampleTable reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]];
}

- (void)controlTextDidChange:(NSNotification *)n {
    NSTextField *f = n.object;   // E-mu names are 16 characters: stop at the limit while typing
    if (f == _nameField && f.stringValue.length > 16) {
        NSText *ed = f.currentEditor; NSString *cut = [f.stringValue substringToIndex:16];
        if (ed) { ed.string = cut; ed.selectedRange = NSMakeRange(16, 0); } else f.stringValue = cut;
        NSBeep();
    }
}
- (void)controlTextDidEndEditing:(NSNotification *)n { [self inspectorChanged:n.object]; }
- (IBAction)inspectorChanged:(id)sender {
    if (!_sample) return;
    NSDictionary *snap = [self snapshot:_sample];
    EDSample *s = _sample;
    NSUInteger last = s.frameCount ? s.frameCount - 1 : 0;
    s.name = _nameField.stringValue;
    if (_rateField.integerValue >= 1000 && _rateField.integerValue <= 192000) s.sampleRate = (uint32_t)_rateField.integerValue;
    NSUInteger ls = MIN((NSUInteger)MAX(_loopStartField.integerValue, 0), last), le = MIN((NSUInteger)MAX(_loopEndField.integerValue, 0), last);
    s.loopStart = MIN(ls, le); s.loopEnd = MAX(ls, le);
    s.loopEnabled = _loopCheck.state == NSControlStateValueOn;
    s.loopInRelease = _releaseCheck.state == NSControlStateValueOn;
    [self registerUndo:snap sample:s name:@"Edit Sample Properties"];
    [self refreshAll];
}

- (void)loopDragged:(BOOL)final {
    _loopStartField.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)_sample.loopStart];
    _loopEndField.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)_sample.loopEnd];
    if (final) [self refreshAll];
}

// MARK: undo

- (NSDictionary *)snapshot:(EDSample *)s {
    return @{@"l": s.left, @"r": s.right ?: [NSNull null], @"ls": @(s.loopStart), @"le": @(s.loopEnd), @"f": @(s.flags), @"rate": @(s.sampleRate), @"name": s.name};
}
- (void)restoreSnapshot:(NSDictionary *)d sample:(EDSample *)s {
    NSDictionary *now = [self snapshot:s];
    [s replaceLeft:d[@"l"] right:[d[@"r"] isKindOfClass:NSData.class] ? d[@"r"] : nil];
    s.flags = [d[@"f"] unsignedShortValue]; s.sampleRate = [d[@"rate"] unsignedIntValue]; s.name = d[@"name"];
    s.loopStart = [d[@"ls"] unsignedIntegerValue]; s.loopEnd = [d[@"le"] unsignedIntegerValue];
    [[self.window.undoManager prepareWithInvocationTarget:self] restoreSnapshot:now sample:s];
    if (s == _sample) { _wave.sample = s; [self refreshAll]; }
}
- (void)registerUndo:(NSDictionary *)before sample:(EDSample *)s name:(NSString *)n {
    [[self.window.undoManager prepareWithInvocationTarget:self] restoreSnapshot:before sample:s];
    [self.window.undoManager setActionName:n];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)w { return _undo ?: (_undo = [NSUndoManager new]); }

// MARK: sample operations

- (void)applyOp:(NSString *)name block:(void (^)(EDSample *s))op {
    if (!_sample || _sample.locked) return;
    NSDictionary *snap = [self snapshot:_sample];
    op(_sample);
    [self registerUndo:snap sample:_sample name:name];
    _wave.sample = _sample;     // refit
    [self refreshAll];
}
- (IBAction)normalize:(id)s { [self applyOp:@"Normalize" block:^(EDSample *x) { [x normalizeToPeak:0.98]; }]; }
- (IBAction)reverseSample:(id)s { [self applyOp:@"Reverse" block:^(EDSample *x) { [x reverse]; }]; }
- (IBAction)fadeIn:(id)s { [self applyOp:@"Fade In" block:^(EDSample *x) { [x fadeInFrames:MAX(x.frameCount / 20, 16)]; }]; }
- (IBAction)fadeOut:(id)s { [self applyOp:@"Fade Out" block:^(EDSample *x) { [x fadeOutFrames:MAX(x.frameCount / 20, 16)]; }]; }
- (IBAction)removeDC:(id)s { [self applyOp:@"Remove DC" block:^(EDSample *x) { [x removeDC]; }]; }
- (IBAction)cropToLoop:(id)s { [self applyOp:@"Crop to Loop" block:^(EDSample *x) { [x cropToLoop]; }]; }
- (IBAction)crossfadeLoop:(id)s {
    [self applyOp:@"Crossfade Loop" block:^(EDSample *x) { [x crossfadeLoopFrames:MIN((x.loopEnd - x.loopStart) / 4, (NSUInteger)4410)]; }];
}
- (IBAction)zoomIn:(id)s { [_wave zoomBy:2]; }
- (IBAction)zoomOut:(id)s { [_wave zoomBy:0.5]; }
- (IBAction)zoomFit:(id)s { [_wave zoomToFit]; }
- (IBAction)zoomLoop:(id)s { [_wave zoomToLoop]; }

// MARK: playback

- (IBAction)togglePlay:(id)sender {
    if (_player.playing) { [_player stop]; return; }
    if (!_sample) return;
    [_player playSample:_sample];
    _playButton.title = @"■ Stop";
    _playTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer *t) { self->_wave.playhead = self->_player.currentFrame; }];
}
- (void)playbackStopped {
    [_playTimer invalidate]; _playTimer = nil; _playButton.title = @"▶ Play"; _wave.playhead = -1;
}

// MARK: import / export

- (IBAction)exportWAV:(id)sender {
    if (!_sample) return;
    NSSavePanel *p = [NSSavePanel savePanel]; p.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"wav"]];
    p.nameFieldStringValue = [[_sample.name stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingString:@".wav"];
    if ([p runModal] != NSModalResponseOK) return;
    NSError *e = nil;
    if (![_sample writeWAVToURL:p.URL error:&e]) [self alertError:e title:@"Export failed"];
}
- (IBAction)importWAV:(id)sender {
    if (!_sample) return;
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.message = @"Replace this sample's audio with an audio file";
    if ([p runModal] != NSModalResponseOK) return;
    NSDictionary *snap = [self snapshot:_sample];
    NSError *e = nil;
    if (![_sample replaceAudioFromURL:p.URL error:&e]) { [self restoreSnapshot:snap sample:_sample]; [self.window.undoManager removeAllActions]; [self alertError:e title:@"Import failed"]; return; }
    [self registerUndo:snap sample:_sample name:@"Replace Audio"];
    _wave.sample = _sample; [self refreshAll];
}

// MARK: SCSI route: sample to the sampler's disk

/// The folder to start in: the first volume served by EMU3 Disk Manager (local NFS mount), preferring "Default Folder".
- (NSURL *)samplerDiskFolder {
    struct statfs *fs = NULL; int n = getmntinfo(&fs, MNT_NOWAIT);
    for (int i = 0; i < n; i++) {
        if (strcmp(fs[i].f_fstypename, "nfs") || strncmp(fs[i].f_mntfromname, "localhost:", 10)) continue;
        NSURL *root = [NSURL fileURLWithFileSystemRepresentation:fs[i].f_mntonname isDirectory:YES relativeToURL:nil];
        NSURL *def = [root URLByAppendingPathComponent:@"Default Folder" isDirectory:YES];
        return [NSFileManager.defaultManager fileExistsAtPath:def.path] ? def : root;
    }
    return nil;
}
- (IBAction)sendToSamplerDisk:(id)sender {
    if (!_sample) return;
    NSData *bank = [EDBank singleSampleBankDataForSample:_sample];
    if (!bank) { [self alertError:[NSError errorWithDomain:EDErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Only samples from EOS (E4B) banks can be sent this way."}] title:@"Cannot send"]; return; }
    NSURL *dir = [self samplerDiskFolder];
    if (!dir) {
        if (![EDTheme confirm:[@"No sampler disk is mounted. " stringByAppendingString:@"Mount an image with EMU3 Disk Manager and serve it with Sampler Link. You can still save the one-sample bank as a file and copy it to the disk yourself."] okTitle:@"Save File…" cancelTitle:@"Cancel"]) return;
    }
    NSSavePanel *p = [NSSavePanel savePanel];
    p.message = @"Save this sample as a one-sample bank on the sampler's disk";
    if (dir) p.directoryURL = dir;
    NSString *base = [[_sample.name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    p.nameFieldStringValue = [(base.length ? base : @"Sample") stringByAppendingString:@".e4b"];
    if ([p runModal] != NSModalResponseOK) return;
    NSError *e = nil;
    if (![bank ed_writeToURL:p.URL error:&e]) { [self alertError:e title:@"Could not write the bank"]; return; }
    _status.stringValue = [NSString stringWithFormat:@"Wrote %@ (%@)%@", p.URL.lastPathComponent, EMU3FormatBytes(bank.length),
        [self urlIsOnSamplerDisk:p.URL] ? @" to the sampler's SCSI disk — rescan the SCSI bus on the sampler, then load the bank" : @""];
}

// MARK: preset as bank

- (EDPreset *)selectedPreset {
    NSInteger i = _presetEditor.selectedIndex; return (_bank && i >= 0 && i < (NSInteger)_bank.presets.count) ? _bank.presets[i] : nil;
}
- (NSData *)bankDataForSelectedPreset:(EDPreset **)outPreset {
    EDPreset *p = [self selectedPreset]; if (outPreset) *outPreset = p;
    if (!p) return nil;
    NSArray<NSNumber *> *missing = nil; NSData *bank = [_bank bankDataForPreset:p missingSamples:&missing];
    if (!bank) { [self alertError:[NSError errorWithDomain:EDErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"Only presets from EOS (E4B) banks can be exported this way."}] title:@"Cannot export"]; return nil; }
    if (missing.count) {
        NSMutableArray *names = [NSMutableArray array]; for (NSNumber *n in missing) [names addObject:n.integerValue >= 1000 ? [NSString stringWithFormat:@"ROM %@", n] : [NSString stringWithFormat:@"S%03ld", (long)n.integerValue]];
        if (![EDTheme confirm:[NSString stringWithFormat:@"%@ will not be in the exported bank (ROM samples, or samples this bank does not contain). The preset will still point at them, so load the bank on a sampler that has them. Continue?", [names componentsJoinedByString:@", "]] okTitle:@"Continue" cancelTitle:@"Cancel"]) return nil;
    }
    return bank;
}
- (void)writePresetBank:(NSData *)bank preset:(EDPreset *)p toSampler:(BOOL)toSampler {
    NSURL *dir = toSampler ? [self samplerDiskFolder] : nil;
    if (toSampler && !dir) {
        if (![EDTheme confirm:[@"No sampler disk is mounted. " stringByAppendingString:@"Mount an image with EMU3 Disk Manager and serve it with Sampler Link. You can still save the bank as a file and copy it to the disk yourself."] okTitle:@"Save File…" cancelTitle:@"Cancel"]) return;
    }
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.message = toSampler ? @"Save this preset and its samples as a bank on the sampler's disk" : @"Save this preset and its samples as a bank file";
    if (dir) sp.directoryURL = dir;
    NSString *base = [[p.name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    sp.nameFieldStringValue = [(base.length ? base : @"Preset") stringByAppendingString:@".e4b"];
    if ([sp runModal] != NSModalResponseOK) return;
    NSError *e = nil;
    if (![bank ed_writeToURL:sp.URL error:&e]) { [self alertError:e title:@"Could not write the bank"]; return; }
    _status.stringValue = [NSString stringWithFormat:@"Wrote %@ (%@)%@", sp.URL.lastPathComponent, EMU3FormatBytes(bank.length),
        [self urlIsOnSamplerDisk:sp.URL] ? @" to the sampler's SCSI disk — rescan the SCSI bus on the sampler, then load the bank" : @""];
}
- (IBAction)sendPresetToSamplerDisk:(id)sender { EDPreset *p = nil; NSData *b = [self bankDataForSelectedPreset:&p]; if (b) [self writePresetBank:b preset:p toSampler:YES]; }
- (IBAction)exportPresetBank:(id)sender { EDPreset *p = nil; NSData *b = [self bankDataForSelectedPreset:&p]; if (b) [self writePresetBank:b preset:p toSampler:NO]; }

// MARK: MIDI sample dump

- (IBAction)sdsTransfer:(id)sender {
    if (!_sds) {
        _sds = [EDSDSPanel new];
        __weak EDMainWindowController *w = self;
        _sds.currentSample = ^EDSDSSample *{ EDMainWindowController *c = w; EDSample *x = c ? c->_sample : nil; return (x && !x.locked) ? [x sdsRepresentation] : nil; };
        _sds.received = ^(EDSDSSample *r) {
            EDMainWindowController *s = w; EDSample *x = s->_sample; if (!s || !x || x.locked) return;
            NSDictionary *snap = [s snapshot:x];
            [x applySDSSample:r];
            [s registerUndo:snap sample:x name:@"Receive MIDI Sample"];
            s->_wave.sample = x; [s refreshAll];
        };
    }
    [_sds present];
}

- (IBAction)findSampler:(id)sender { [self smdiTransfer:nil]; [_smdi presentAndFind]; }
- (IBAction)smdiTransfer:(id)sender {
    if (!_smdi) {
        _smdi = [EDSMDIPanel new];
        __weak EDMainWindowController *w = self;
        _smdi.currentSample = ^EDSDSSample *{ EDMainWindowController *c = w; EDSample *x = c ? c->_sample : nil; return (x && !x.locked) ? [x sdsRepresentation] : nil; };
        _smdi.received = ^(EDSDSSample *r, NSString *name) {
            EDMainWindowController *s = w; EDSample *x = s->_sample; if (!s || !x || x.locked) return;
            NSDictionary *snap = [s snapshot:x];
            [x applySDSSample:r];
            [s registerUndo:snap sample:x name:@"Receive SMDI Sample"];
            s->_wave.sample = x; [s refreshAll];
        };
    }
    [_smdi present];
}

// MARK: saving

- (IBAction)saveBank:(id)sender {
    if (!_bank) return;
    NSError *e = nil;
    NSData *out = [_bank serializeWithError:&e];
    if (!out) { [self alertError:e title:@"Cannot save"]; return; }
    [self backupOriginal];
    if (_standaloneURL) {
        if (![out ed_writeToURL:_standaloneURL error:&e]) { [self alertError:e title:@"Save failed"]; return; }
    } else if (_currentNode.file) {
        if (![_fs replaceContentsOfFile:_currentNode.file withData:out error:&e]) { [self alertError:e title:@"Writing to the disk image failed"]; return; }
        [_fs synchronizeToDisk:nil];
    } else return;
    NSInteger keep = _sampleTable.selectedRow;
    [self loadBankData:out title:_bankTitle];
    if (keep >= 0 && keep < (NSInteger)_bank.samples.count) [_sampleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:keep] byExtendingSelection:NO];
    _status.stringValue = [NSString stringWithFormat:@"Saved %@ (%@)", _bankTitle, EMU3FormatBytes(out.length)];
    if ([self urlIsOnSamplerDisk:_standaloneURL])
        _status.stringValue = [_status.stringValue stringByAppendingString:@" — it is on the sampler's SCSI disk: rescan the SCSI bus on the sampler, then load the bank"];
}
/// YES when the file lives on a volume served by EMU3 Disk Manager (its local NFS mount, which the BlueSCSI link exposes to the sampler).
- (BOOL)urlIsOnSamplerDisk:(NSURL *)url {
    struct statfs fs; if (!url || statfs(url.fileSystemRepresentation, &fs) != 0) return NO;
    return strcmp(fs.f_fstypename, "nfs") == 0 && strncmp(fs.f_mntfromname, "localhost:", 10) == 0;
}
- (IBAction)saveBankAs:(id)sender {
    if (!_bank) return;
    NSError *e = nil; NSData *out = [_bank serializeWithError:&e];
    if (!out) { [self alertError:e title:@"Cannot save"]; return; }
    NSSavePanel *p = [NSSavePanel savePanel]; p.nameFieldStringValue = [_bankTitle stringByAppendingString:@".e4b"];
    if ([p runModal] != NSModalResponseOK) return;
    if (![out ed_writeToURL:p.URL error:&e]) [self alertError:e title:@"Save failed"];
}

/// Every save keeps a copy of the bank as it was loaded: ~/Library/Application Support/EMU3 Editor/Backups
- (void)backupOriginal {
    if (!_originalData) return;
    NSURL *dir = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                  URLByAppendingPathComponent:@"EMU3 Editor/Backups" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *safe = [_bankTitle stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    [_originalData writeToURL:[dir URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %@.e4b", safe, [f stringFromDate:NSDate.date]]] atomically:YES];
}

// MARK: housekeeping

- (BOOL)confirmDiscard {
    if (!_bank.dirty) return YES;
    NSInteger r = [EDTheme choose:[NSString stringWithFormat:@"“%@” has unsaved changes. Save them before continuing?", _bankTitle] buttons:@[@"Cancel", @"Discard", @"Save"]];
    if (r == 2) { [self saveBank:nil]; return !_bank.dirty; }
    return r == 1;
}
- (BOOL)confirmQuit { return [self confirmDiscard]; }
- (BOOL)windowShouldClose:(NSWindow *)w { return [self confirmDiscard]; }
- (void)alertError:(NSError *)e title:(NSString *)t {
    [EDTheme notice:[NSString stringWithFormat:@"%@. %@", t, e.localizedDescription ?: @"Unknown error"]];
}
- (BOOL)validateMenuItem:(NSMenuItem *)m {
    SEL a = m.action;
    if (a == @selector(toggleFXBoard:)) { m.state = self.fxBoardInstalled ? NSControlStateValueOn : NSControlStateValueOff; return YES; }
    if (a == @selector(showFXTab:)) return self.fxBoardInstalled;
    if (a == @selector(saveBank:) || a == @selector(saveBankAs:)) return _bank != nil;
    if (a == @selector(sendPresetToSamplerDisk:) || a == @selector(exportPresetBank:)) return [self selectedPreset].kind == EDPresetKindE4 && [_bank.formType hasPrefix:@"E4B"];
    if (a == @selector(exportWAV:) || a == @selector(importWAV:) || a == @selector(sdsTransfer:) || a == @selector(smdiTransfer:) || a == @selector(sendToSamplerDisk:) || a == @selector(togglePlay:) || a == @selector(normalize:) ||
        a == @selector(reverseSample:) || a == @selector(fadeIn:) || a == @selector(fadeOut:) || a == @selector(removeDC:) ||
        a == @selector(cropToLoop:) || a == @selector(crossfadeLoop:) || a == @selector(zoomIn:) || a == @selector(zoomOut:) ||
        a == @selector(zoomFit:) || a == @selector(zoomLoop:)) return _sample != nil && !_sample.locked;
    return YES;
}
@end
