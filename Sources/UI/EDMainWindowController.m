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
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 50); }
- (void)setLine1:(NSString *)l { _line1 = [l copy]; self.needsDisplay = YES; }
- (void)setLine2:(NSString *)l { _line2 = [l copy]; self.needsDisplay = YES; }
- (void)drawRect:(NSRect)r {
    NSRect b = NSInsetRect(self.bounds, EDTheme.lcdFrameWidth, EDTheme.lcdFrameWidth);
    NSBezierPath *bez = [NSBezierPath bezierPathWithRoundedRect:b xRadius:6 yRadius:6];
    [[NSColor blackColor] setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
    [EDTheme.lcdBackground setFill]; [bez fill];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSDictionary *a1 = @{NSFontAttributeName: [EDTheme lcdFont:15], NSForegroundColorAttributeName: EDTheme.lcdInk, NSParagraphStyleAttributeName: ps};
    NSDictionary *a2 = @{NSFontAttributeName: [EDTheme lcdFont:12], NSForegroundColorAttributeName: [EDTheme.lcdInk colorWithAlphaComponent:0.8], NSParagraphStyleAttributeName: ps};
    CGFloat w = NSWidth(b) - 24;
    [_line1 ?: @"" drawInRect:NSMakeRect(12, 4, w, 20) withAttributes:a1];
    [_line2 ?: @"" drawInRect:NSMakeRect(12, 27, w, 18) withAttributes:a2];
}
- (BOOL)isFlipped { return YES; }
@end

@implementation EDMainWindowController {
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

static NSTextField *label(NSString *s) {
    NSTextField *t = [NSTextField labelWithString:s]; t.font = [NSFont systemFontOfSize:12]; t.textColor = NSColor.secondaryLabelColor; return t;
}
- (NSTextField *)field:(CGFloat)width {
    NSTextField *t = [NSTextField textFieldWithString:@""]; t.delegate = self; t.controlSize = NSControlSizeRegular;
    t.font = [NSFont systemFontOfSize:13]; [t.widthAnchor constraintEqualToConstant:width].active = YES; return t;
}
- (NSButton *)button:(NSString *)title action:(SEL)sel {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:sel]; b.controlSize = NSControlSizeRegular; b.bezelStyle = NSBezelStyleRounded; return b;
}
- (NSScrollView *)scroll:(NSView *)v {
    NSScrollView *s = [[NSScrollView alloc] init]; s.documentView = v; s.hasVerticalScroller = YES; s.borderType = NSNoBorder; return s;
}
- (NSTableView *)table:(NSArray<NSArray<NSString *> *> *)cols {
    NSTableView *t = [[EDLCDTableView alloc] init]; t.dataSource = self; t.delegate = self; t.usesAlternatingRowBackgroundColors = YES;
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
    NSTextField *diskNote = [NSTextField labelWithString:@"Click a bank to load it; double-click to edit its samples."];
    diskNote.font = [EDTheme lcdFont:11]; diskNote.textColor = EDTheme.lcdInk;
    NSStackView *diskBar = [NSStackView stackViewWithViews:@[[EDTheme lcdKey:@"Open Disk Image…" target:self action:@selector(openDiskImage:)],
        [EDTheme lcdKey:@"Open Bank File…" target:self action:@selector(openBankFile:)], diskNote]];
    diskBar.spacing = 8;
    NSScrollView *outlineScroll = [self scroll:_outline];
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

    _playButton = [self button:@"▶ Play" action:@selector(togglePlay:)];
    NSButton *zi = [self button:@"＋" action:@selector(zoomIn:)], *zo = [self button:@"－" action:@selector(zoomOut:)];
    NSButton *zf = [self button:@"Fit" action:@selector(zoomFit:)], *zl = [self button:@"Loop" action:@selector(zoomLoop:)];
    _info = label(@"");
    NSStackView *transport = [NSStackView stackViewWithViews:@[_playButton, zo, zi, zf, zl, _info]];
    transport.spacing = 6;

    // inspector
    _nameField = [self field:150]; _rateField = [self field:70]; _loopStartField = [self field:80]; _loopEndField = [self field:80];
    _loopCheck = [NSButton checkboxWithTitle:@"Loop" target:self action:@selector(inspectorChanged:)];
    _releaseCheck = [NSButton checkboxWithTitle:@"Loop in release" target:self action:@selector(inspectorChanged:)];
    NSStackView *insp = [NSStackView stackViewWithViews:@[label(@"Name"), _nameField, label(@"Rate Hz"), _rateField,
        label(@"Loop start"), _loopStartField, label(@"Loop end"), _loopEndField, _loopCheck, _releaseCheck]];
    insp.spacing = 6;


    NSStackView *editor = [NSStackView stackViewWithViews:@[_wave, transport, insp]];
    editor.orientation = NSUserInterfaceLayoutOrientationVertical; editor.alignment = NSLayoutAttributeLeading; editor.spacing = 8;
    editor.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    [_wave.widthAnchor constraintEqualToAnchor:editor.widthAnchor constant:-16].active = YES;

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
    EDLCDSideTab *diskTab = [[EDLCDSideTab alloc] initWithTitle:@"DISK"];
    left.translatesAutoresizingMaskIntoConstraints = NO; [diskView addSubview:left];
    diskTab.translatesAutoresizingMaskIntoConstraints = NO; [left addSubview:diskTab];   // the DISK strip lives inside the green screen, above the keys
    for (NSLayoutConstraint *c in left.constraints) if (c.firstItem == outlineScroll && c.firstAttribute == NSLayoutAttributeLeading) c.constant = 60;
    _diskHint = [[EDDiskIcons alloc] initWithFrame:NSZeroRect];
    _diskHint.translatesAutoresizingMaskIntoConstraints = NO; [diskView addSubview:_diskHint];
    [NSLayoutConstraint activateConstraints:@[[_diskHint.topAnchor constraintEqualToAnchor:left.topAnchor constant:26], [_diskHint.bottomAnchor constraintEqualToAnchor:left.bottomAnchor constant:-44],
        [_diskHint.leadingAnchor constraintEqualToAnchor:left.leadingAnchor constant:60], [_diskHint.trailingAnchor constraintEqualToAnchor:left.trailingAnchor]]];
    __weak EDMainWindowController *weakSelf = self;
    _diskHint.onOpen = ^(EDDiskItem *it) { [weakSelf openDiskItem:it]; };
    [NSLayoutConstraint activateConstraints:@[
        [left.topAnchor constraintEqualToAnchor:diskView.topAnchor constant:10], [left.leadingAnchor constraintEqualToAnchor:diskView.leadingAnchor constant:10],
        [diskTab.topAnchor constraintEqualToAnchor:left.topAnchor constant:8], [diskTab.bottomAnchor constraintEqualToAnchor:diskBar.topAnchor constant:-8],
        [diskTab.leadingAnchor constraintEqualToAnchor:left.leadingAnchor constant:8], [diskTab.widthAnchor constraintEqualToConstant:46],
        [left.trailingAnchor constraintEqualToAnchor:diskView.trailingAnchor constant:-10], [left.bottomAnchor constraintEqualToAnchor:diskView.bottomAnchor constant:-10]]];

    // Master tab: sampler status and shortcuts | banks to open (sampler disk + recent) | current bank
    _samplerStatus = [NSTextField wrappingLabelWithString:@""]; _samplerStatus.font = [NSFont systemFontOfSize:14]; _samplerStatus.textColor = EDTheme.labelWhite;
    _masterSummary = [NSTextField wrappingLabelWithString:@""]; _masterSummary.font = [NSFont systemFontOfSize:15]; _masterSummary.textColor = EDTheme.labelWhite;
    NSStackView *gSampler = [self group:@"Sampler" views:@[_samplerStatus,
        [self wideButton:@"Show Sampler Disk" action:@selector(showSamplerDisk:)],
        [self wideButton:@"SMDI Transfer (SCSI)…" action:@selector(smdiTransfer:)],
        [self wideButton:@"MIDI Sample Dump…" action:@selector(sdsTransfer:)],
        [self wideButton:@"Open Disk Image…" action:@selector(openDiskImage:)]]];
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
    ramRow.toolTip = @"Information only: the sampler's sample RAM is physical (SIMMs) and cannot be changed by software. The Memory box uses this size for its percentages.";
    _autoSaveBtn = [NSButton checkboxWithTitle:@"Save to sampler automatically" target:self action:@selector(autoSaveToggled:)];
    _autoSaveBtn.state = [NSUserDefaults.standardUserDefaults boolForKey:@"AutoSaveToSampler"] ? NSControlStateValueOn : NSControlStateValueOff;
    _autoSaveBtn.toolTip = @"When the open bank is on the sampler's disk, writes it back a few seconds after you stop editing. The sampler still needs a SCSI rescan and a bank reload to see the change. The original is backed up once per opened bank.";
    NSStackView *gBank = [self group:@"Current bank" views:@[_masterSummary, _memory, ramRow, _autoSaveBtn,
        [self wideButton:@"Save Bank" action:@selector(saveBank:)], [self wideButton:@"Save Bank As…" action:@selector(saveBankAs:)],
        [self wideButton:@"Open Bank File…" action:@selector(openBankFile:)],
        [self wideButton:@"Send Sample to Sampler Disk…" action:@selector(sendToSamplerDisk:)]]];
    NSView *masterView = [NSView new];
    for (NSView *v in @[leftCol, gOpen, gBank]) { v.translatesAutoresizingMaskIntoConstraints = NO; [masterView addSubview:v]; [v.topAnchor constraintEqualToAnchor:masterView.topAnchor constant:30].active = YES; }
    [NSLayoutConstraint activateConstraints:@[
        [leftCol.leadingAnchor constraintEqualToAnchor:masterView.leadingAnchor constant:40], [leftCol.widthAnchor constraintEqualToConstant:270],
        [gOpen.leadingAnchor constraintEqualToAnchor:leftCol.trailingAnchor constant:40], [gOpen.bottomAnchor constraintEqualToAnchor:masterView.bottomAnchor constant:-30],
        [gBank.leadingAnchor constraintEqualToAnchor:gOpen.trailingAnchor constant:40], [gBank.trailingAnchor constraintEqualToAnchor:masterView.trailingAnchor constant:-40],
        [gBank.widthAnchor constraintEqualToConstant:420]]];

    // Master tab = overview | MIDI | Setup (the sampler's Master menus), switched by a small picker on top
    NSView *masterRoot = [NSView new];
    NSSegmentedControl *mp = [NSSegmentedControl segmentedControlWithLabels:@[@"Overview", @"MIDI", @"Setup", @"Bank"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(masterPicked:)];
    mp.selectedSegment = 0; _masterPicker = mp;
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
    NSArray *defs = @[@[@"master", @"Master", masterRoot], @[@"disk", @"Disk", diskView], @[@"samples", @"Samples", samplesSplit], @[@"presets", @"Presets", _presetEditor]];
    for (NSArray *d in defs) { NSTabViewItem *t = [[NSTabViewItem alloc] initWithIdentifier:d[0]]; t.label = d[1]; t.view = d[2]; [_tabs addTabViewItem:t]; }
    _tabPicker = [NSSegmentedControl segmentedControlWithLabels:@[@"Master", @"Disk", @"Samples", @"Presets"] trackingMode:NSSegmentSwitchTrackingSelectOne
        target:self action:@selector(tabPicked:)];
    _tabPicker.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold]; _tabPicker.selectedSegment = 0;
    for (NSInteger i = 0; i < 4; i++) [_tabPicker setWidth:80 forSegment:i];

    // header: wordmark, tab picker, LCD readout, red rule
    _lcd = [EDLCDStrip new];
    EDLogoView *logo = [EDLogoView new];
    NSView *head = [NSView new]; head.wantsLayer = YES; head.layer.backgroundColor = EDTheme.bodyDark.CGColor;
    for (NSView *v in @[logo, _tabPicker, _lcd]) { v.translatesAutoresizingMaskIntoConstraints = NO; [head addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [head.heightAnchor constraintEqualToConstant:72],
        [logo.leadingAnchor constraintEqualToAnchor:head.leadingAnchor constant:18], [logo.centerYAnchor constraintEqualToAnchor:head.centerYAnchor],
        [_tabPicker.leadingAnchor constraintEqualToAnchor:logo.trailingAnchor constant:24], [_tabPicker.centerYAnchor constraintEqualToAnchor:head.centerYAnchor],
        [_lcd.trailingAnchor constraintEqualToAnchor:head.trailingAnchor constant:-18], [_lcd.centerYAnchor constraintEqualToAnchor:head.centerYAnchor],
        [_lcd.leadingAnchor constraintEqualToAnchor:_tabPicker.trailingAnchor constant:24], [_lcd.heightAnchor constraintEqualToConstant:50]]];
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
    bar.spacing = 22; bar.alignment = NSLayoutAttributeTop;
    { NSArray *gs = bar.arrangedSubviews; for (NSView *v in gs) [bar removeArrangedSubview:v]; [bar setViews:gs inGravity:NSStackViewGravityCenter]; } bar.edgeInsets = NSEdgeInsetsMake(12, 18, 0, 18);
    bar.wantsLayer = YES; bar.layer.backgroundColor = EDTheme.bodyDark.CGColor;
    [bar.heightAnchor constraintEqualToConstant:74].active = YES;
    NSView *rule2 = [NSView new]; rule2.wantsLayer = YES; rule2.layer.backgroundColor = [EDTheme.accent colorWithAlphaComponent:0.55].CGColor;
    [rule2.heightAnchor constraintEqualToConstant:1].active = YES;

    _status = label(@"Open a disk image (File ▸ Open Disk Image…) or a bank file.");
    _presetNote = label(@"Pages follow the sampler's Preset Edit menus. Changes go straight into the preset (Edit ▸ Undo works).");
    NSStackView *foot = [NSStackView stackViewWithViews:@[_status]]; _presetNote.hidden = YES; foot.edgeInsets = NSEdgeInsetsMake(2, 14, 0, 14);
    NSStackView *root = [NSStackView stackViewWithViews:@[head, rule, bar, rule2, _tabs, foot]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.spacing = 0; root.alignment = NSLayoutAttributeLeading;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor], [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor], [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-4],
        [head.widthAnchor constraintEqualToAnchor:root.widthAnchor], [bar.widthAnchor constraintEqualToAnchor:root.widthAnchor], [rule2.widthAnchor constraintEqualToAnchor:root.widthAnchor], [rule.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [_tabs.widthAnchor constraintEqualToAnchor:root.widthAnchor]]];
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
        NSButton *b = [NSButton buttonWithTitle:k[0] target:self action:NSSelectorFromString(k[1])];
        b.bordered = NO; b.wantsLayer = YES; b.layer.cornerRadius = 5; b.layer.backgroundColor = EDTheme.body.CGColor;
        b.layer.borderWidth = 1; b.layer.borderColor = [NSColor colorWithCalibratedWhite:0.34 alpha:1].CGColor;
        b.attributedTitle = [[NSAttributedString alloc] initWithString:k[0] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: EDTheme.labelWhite}];
        b.attributedAlternateTitle = [[NSAttributedString alloc] initWithString:k[0] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: EDTheme.logoBlue}];
        [b.heightAnchor constraintEqualToConstant:28].active = YES;
        [b.widthAnchor constraintGreaterThanOrEqualToConstant:[k[0] length] < 3 ? 32 : 58].active = YES;
        if ([k[2] intValue] == 1) [_sampleBtns addObject:b]; else if ([k[2] intValue] == 2) [_bankBtns addObject:b];
        [btns addObject:b];
    }
    NSStackView *row = [NSStackView stackViewWithViews:btns]; row.spacing = 4;
    NSTextField *cap = [NSTextField labelWithString:title.uppercaseString];
    cap.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold]; cap.textColor = EDTheme.labelWhite;
    NSView *line = [NSView new]; line.wantsLayer = YES; line.layer.backgroundColor = EDTheme.accent.CGColor;
    [line.heightAnchor constraintEqualToConstant:2].active = YES;
    NSStackView *g = [NSStackView stackViewWithViews:@[cap, line, row]];
    g.orientation = NSUserInterfaceLayoutOrientationVertical; g.alignment = NSLayoutAttributeLeading; g.spacing = 4;
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
}
- (void)showPresetNote:(BOOL)show {
    _presetNote.hidden = !show;
    // the note lines up with the LCD screen's left edge; that view only joins the hierarchy once its tab is shown
    if (show && !_presetNoteLeading) { _presetNoteLeading = [_presetNote.leadingAnchor constraintEqualToAnchor:_presetEditor.lcdView.leadingAnchor]; _presetNoteLeading.active = YES; }
}
- (IBAction)tabPicked:(id)sender { [_tabs selectTabViewItemAtIndex:_tabPicker.selectedSegment]; [self showPresetNote:_tabPicker.selectedSegment == 3]; }
- (IBAction)showMasterTab:(id)s { [self selectTabNamed:@"master"]; }
- (IBAction)showDiskTab:(id)s { [self selectTabNamed:@"disk"]; }
- (IBAction)showSamplesTab:(id)s { [self selectTabNamed:@"samples"]; }
- (IBAction)showPresetsTab:(id)s { [self selectTabNamed:@"presets"]; }
- (void)refreshSamplerStatus {
    NSURL *d = [self samplerDiskFolder]; NSURL *root = [d.lastPathComponent isEqual:@"Default Folder"] ? d.URLByDeletingLastPathComponent : d;
    NSArray *ports = [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/dev" error:nil];
    NSInteger boards = 0; for (NSString *n in ports) if ([n hasPrefix:@"cu.usbmodem"]) boards++;
    _samplerStatus.stringValue = [NSString stringWithFormat:@"%@\n%@", root ? [NSString stringWithFormat:@"● Disk served: %@", root.lastPathComponent] : @"○ No sampler disk mounted",
        boards ? @"● SCSI board connected" : @"○ SCSI board not found"];
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
    if (![out writeToURL:_standaloneURL options:NSDataWritingAtomic error:&e]) { _status.stringValue = [@"Auto-save failed: " stringByAppendingString:e.localizedDescription ?: @"write error"]; return; }
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
    NSInteger i = s.selectedSegment; _masterOverview.hidden = i != 0; _midiEditor.hidden = i == 0;
    if (i > 0) { [_midiEditor setMenu:i == 1 ? @"MIDI" : (i == 2 ? @"Setup" : @"Bank")]; [_midiEditor reload]; }
}
- (IBAction)showMIDITab:(id)s { [self showMasterPage:1]; }
- (IBAction)showSetupTab:(id)s { [self showMasterPage:2]; }
- (IBAction)showBankTab:(id)s { [self showMasterPage:3]; }
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
- (void)openDiskItem:(EDDiskItem *)it {
    if (it.sampler) { [self selectTabNamed:@"master"]; return; }
    if (it.url) [self openImageAtURL:it.url];
}
/// The drives the Disk page shows while no image is open: the disk the sampler sees, and recently opened images.
- (void)refreshDiskIcons {
    NSMutableArray *items = [NSMutableArray array];
    NSURL *d = [self samplerDiskFolder]; NSURL *root = [d.lastPathComponent isEqual:@"Default Folder"] ? d.URLByDeletingLastPathComponent : d;
    if (root) { EDDiskItem *it = [EDDiskItem new]; it.kind = EDDiskHard; it.title = root.lastPathComponent; it.subtitle = @"sampler disk · served"; it.sampler = YES; it.url = root; [items addObject:it]; }
    for (NSString *path in [NSUserDefaults.standardUserDefaults arrayForKey:@"RecentDisks"]) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        EDDiskItem *it = [EDDiskItem new]; NSString *ext = path.pathExtension.lowercaseString;
        it.kind = [ext isEqual:@"iso"] ? EDDiskCD : EDDiskHard; it.title = path.lastPathComponent; it.subtitle = @"disk image · double-click to open"; it.url = [NSURL fileURLWithPath:path]; [items addObject:it];
    }
    _diskHint.items = items;
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
    _lcd.line1 = l1; _lcd.line2 = l2;
    for (NSButton *b in _sampleBtns) b.enabled = _sample && !_sample.locked;
    for (NSButton *b in _bankBtns) b.enabled = _bank != nil;
    NSMutableString *m = [NSMutableString string];
    if (disk) [m appendFormat:@"Disk: %@\n", disk];
    if (_bank) [m appendFormat:@"Bank: %@\n%lu samples, %lu presets\n%@", _bankTitle, (unsigned long)_bank.samples.count, (unsigned long)_bank.presets.count, _bank.dirty ? @"Unsaved changes" : @"No unsaved changes"];
    else [m appendString:@"No bank open."];
    _masterSummary.stringValue = m;
    _diskHint.hidden = _rootNode != nil;
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
    [_outline reloadData]; [_outline expandItem:_rootNode];
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
    [_fs closeImage]; _fs = nil; _rootNode = nil; _currentNode = nil; [_outline reloadData];
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
- (void)closeBank { [_player stop]; _midiEditor.bankTitle = nil; _bank = nil; _sample = nil; _originalData = nil; _currentNode = nil; [_sampleTable reloadData]; _presetEditor.bank = nil; _midiEditor.bank = nil; [self selectSample:nil]; [self modelChanged]; }

- (void)updateTitle {
    NSString *base = _fs ? _fs.imageURL.lastPathComponent : @"";
    NSString *t = _bank ? (base.length ? [NSString stringWithFormat:@"%@ ▸ %@", base, _bankTitle] : _bankTitle) : (base.length ? base : @"");
    self.window.title = t.length ? [@"EMU3 Editor — " stringByAppendingString:t] : @"EMU3 Editor";
    self.window.documentEdited = _bank.dirty; [self scheduleAutoSave];
    [self modelChanged];
}

// sample names may have changed: refresh the preset editor's lookups when its tab is shown
- (void)tabView:(NSTabView *)tv didSelectTabViewItem:(NSTabViewItem *)item {
    _tabPicker.selectedSegment = [tv indexOfTabViewItem:item];
    if ([item.identifier isEqual:@"presets"]) [_presetEditor reload];
    if ([item.identifier isEqual:@"master"]) [self refreshSamplerStatus];
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
    if (![self confirmDiscard]) { [self restoreOutlineSelection]; return; }
    NSError *e = nil;
    NSData *d = [_fs dataForFile:item.file error:&e];
    if (!d) { [self alertError:e title:@"Could not read the bank"]; return; }
    if ([self loadBankData:d title:item.title]) _currentNode = item; else [self restoreOutlineSelection];
}
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
    if (![bank writeToURL:p.URL options:NSDataWritingAtomic error:&e]) { [self alertError:e title:@"Could not write the bank"]; return; }
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
    if (![bank writeToURL:sp.URL options:NSDataWritingAtomic error:&e]) { [self alertError:e title:@"Could not write the bank"]; return; }
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
        if (![out writeToURL:_standaloneURL options:NSDataWritingAtomic error:&e]) { [self alertError:e title:@"Save failed"]; return; }
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
    if (![out writeToURL:p.URL options:NSDataWritingAtomic error:&e]) [self alertError:e title:@"Save failed"];
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
    if (a == @selector(saveBank:) || a == @selector(saveBankAs:)) return _bank != nil;
    if (a == @selector(sendPresetToSamplerDisk:) || a == @selector(exportPresetBank:)) return [self selectedPreset].kind == EDPresetKindE4 && [_bank.formType hasPrefix:@"E4B"];
    if (a == @selector(exportWAV:) || a == @selector(importWAV:) || a == @selector(sdsTransfer:) || a == @selector(smdiTransfer:) || a == @selector(sendToSamplerDisk:) || a == @selector(togglePlay:) || a == @selector(normalize:) ||
        a == @selector(reverseSample:) || a == @selector(fadeIn:) || a == @selector(fadeOut:) || a == @selector(removeDC:) ||
        a == @selector(cropToLoop:) || a == @selector(crossfadeLoop:) || a == @selector(zoomIn:) || a == @selector(zoomOut:) ||
        a == @selector(zoomFit:) || a == @selector(zoomLoop:)) return _sample != nil && !_sample.locked;
    return YES;
}
@end
