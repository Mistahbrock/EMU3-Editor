#import "EDSMDIPanel.h"

@implementation EDSMDIPanel {
    NSPopUpButton *_portPop;
    NSTextField *_idField, *_numField, *_status;
    NSTableView *_list; NSMutableArray<EDSMDIInfo *> *_rows;
    NSProgressIndicator *_bar;
    NSButton *_sendBtn, *_recvBtn, *_scanBtn, *_cancelBtn, *_delBtn;
    EDSMDIBoard *_board; EDSMDIClient *_client;
    BOOL _busy;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 480)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"SMDI Transfer (SCSI)"; w.releasedWhenClosed = NO;
    if ((self = [super initWithWindow:w])) { _rows = [NSMutableArray array]; [self build]; }
    return self;
}
- (NSButton *)button:(NSString *)t action:(SEL)a { return [NSButton buttonWithTitle:t target:self action:a]; }

- (void)build {
    _portPop = [NSPopUpButton new];
    _idField = [NSTextField textFieldWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"SMDITarget"] ?: @"6"];
    _numField = [NSTextField textFieldWithString:@"1"];
    _idField.toolTip = @"The sampler's SCSI ID (Master ▸ Setup ▸ SCSI/Disk). The BlueSCSI board uses ID 7 — set \"Avoid Host on ID\" to 7 on the sampler.";
    _numField.toolTip = @"Sample number on the sampler, 1–999 (the number the sampler's display shows). Sample 0 is the sampler's clipboard and cannot be used over SMDI.";
    _status = [NSTextField wrappingLabelWithString:@"Needs the BlueSCSI board in initiator mode with the SMDI firmware (both initiator jumpers set), connected to the sampler's SCSI port. Quit EMU3 Disk Manager's sampler link first — it uses the same USB serial port."];
    _status.preferredMaxLayoutWidth = 520; _status.maximumNumberOfLines = 6;
    _bar = [NSProgressIndicator new]; _bar.style = NSProgressIndicatorStyleBar; _bar.indeterminate = NO; _bar.maxValue = 1;
    _scanBtn = [self button:@"Read sample list" action:@selector(scan:)];
    _sendBtn = [self button:@"Send selected sample →" action:@selector(send:)];
    _recvBtn = [self button:@"← Receive into selected sample" action:@selector(receive:)];
    _delBtn = [self button:@"Delete on sampler" action:@selector(deleteRemote:)];
    _cancelBtn = [self button:@"Cancel" action:@selector(cancel:)]; _cancelBtn.enabled = NO;
    NSButton *refresh = [self button:@"Refresh ports" action:@selector(refresh:)];

    _list = [NSTableView new];
    for (NSArray *c in @[@[@"num", @"#", @50], @[@"name", @"Name", @170], @[@"rate", @"Rate", @70], @[@"len", @"Frames", @80], @[@"loop", @"Loop", @60], @[@"bits", @"Bits", @40]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_list addTableColumn:col];
    }
    _list.dataSource = (id)self; _list.delegate = (id)self; _list.usesAlternatingRowBackgroundColors = YES;
    NSScrollView *sv = [NSScrollView new]; sv.documentView = _list; sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv.widthAnchor constraintEqualToConstant:520].active = YES; [sv.heightAnchor constraintEqualToConstant:170].active = YES;

    NSTextField *note = [NSTextField wrappingLabelWithString:@"1–999, as on the sampler's display (S001…). Sample 0 (S000) is the sampler's clipboard; SMDI refuses it."];
    note.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize]; note.textColor = NSColor.secondaryLabelColor; note.preferredMaxLayoutWidth = 391;
    NSGridView *g = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"BlueSCSI serial port"], _portPop],
        @[[NSTextField labelWithString:@"Sampler SCSI ID"], _idField],
        @[[NSTextField labelWithString:@"Sample #"], _numField],
        @[[NSGridCell emptyContentView], note]]];
    g.rowSpacing = 8; g.columnSpacing = 10; [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    NSStackView *r1 = [NSStackView stackViewWithViews:@[_scanBtn, _sendBtn, _recvBtn]];
    NSStackView *r2 = [NSStackView stackViewWithViews:@[_delBtn, _cancelBtn, refresh]];
    NSStackView *root = [NSStackView stackViewWithViews:@[g, sv, r1, r2, _bar, _status]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeLeading; root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    _bar.translatesAutoresizingMaskIntoConstraints = NO; [_bar.widthAnchor constraintEqualToConstant:520].active = YES;
    self.window.contentView = root; [self.window setContentSize:root.fittingSize];
    [self refresh:nil];
}

- (void)refresh:(id)s {
    NSString *keep = _portPop.titleOfSelectedItem;
    [_portPop removeAllItems];
    NSArray *ports = [EDSMDIBoard availablePorts];
    [_portPop addItemsWithTitles:ports];
    NSString *def = keep && [ports containsObject:keep] ? keep : [EDSMDIBoard defaultPort];
    if (def) [_portPop selectItemWithTitle:def];
    if (!ports.count) [_portPop addItemWithTitle:@"(no BlueSCSI serial port found)"];
}
- (void)present {
    [self refresh:nil];
    if (_numField.intValue < 1) _numField.intValue = 1;      // always start at S001; the bank's own sample number is not the sampler's slot
    [self.window center]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}
- (void)setBusy:(BOOL)b {
    _busy = b; _scanBtn.enabled = _sendBtn.enabled = _recvBtn.enabled = _delBtn.enabled = !b; _cancelBtn.enabled = b;
    _portPop.enabled = _idField.enabled = !b;
}

/// Connects the board and builds a client; the status line explains any failure.
- (BOOL)prepare {
    NSString *port = _portPop.titleOfSelectedItem;
    if (![port hasPrefix:@"/dev/"]) { _status.stringValue = @"No BlueSCSI serial port found. Plug the board in (initiator mode, SMDI firmware)."; return NO; }
    if (!_board || ![_board.path isEqual:port]) {
        _board = [EDSMDIBoard new]; NSError *e = nil;
        if (![_board openPath:port error:&e]) { _status.stringValue = e.localizedDescription; _board = nil; return NO; }
    }
    int sid = _idField.intValue;
    if (sid < 0 || sid > 6) { _status.stringValue = @"The sampler's SCSI ID must be 0–6 (the board itself uses 7)."; return NO; }
    [NSUserDefaults.standardUserDefaults setObject:@(sid).stringValue forKey:@"SMDITarget"];
    _client = [[EDSMDIClient alloc] initWithExec:_board.executor target:(uint8_t)sid];
    return YES;
}
- (void)progress:(double)f text:(NSString *)t {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_bar.doubleValue = f; self->_status.stringValue = t; });
}
- (void)finish:(NSString *)msg {
    [self setBusy:NO]; _status.stringValue = msg; _bar.doubleValue = 0;
}
- (void)runJob:(NSString *(^)(EDSMDIClient *))job {
    if (![self prepare]) return;
    [self setBusy:YES]; _bar.doubleValue = 0;
    EDSMDIClient *c = _client;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *m = job(c);
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:m]; });
    });
}

- (void)scan:(id)s {
    [_rows removeAllObjects]; [_list reloadData];
    [self runJob:^NSString *(EDSMDIClient *c) {
        NSError *e = nil;
        if (![c masterIdentify:&e]) return [@"The sampler did not answer SMDI: " stringByAppendingString:e.localizedDescription];
        int missing = 0;
        for (uint32_t n = 1; n <= 999 && missing < 40; n++) {         // stop after a long run of empty slots
            EDSMDIInfo *i = [c infoForSample:n error:&e];
            [self progress:n / 999.0 text:[NSString stringWithFormat:@"Reading sample %u…", n]];
            if (i) { missing = 0; dispatch_async(dispatch_get_main_queue(), ^{ [self->_rows addObject:i]; [self->_list reloadData]; }); }
            else if (e.code == EDSMDIErrorNoSample) missing++;
            else return e.localizedDescription;
            if (self->_client != c) break;
        }
        return [NSString stringWithFormat:@"%lu sample(s) on the sampler.", (unsigned long)self->_rows.count];
    }];
}
- (void)send:(id)s {
    EDSDSSample *smp = _currentSample ? _currentSample() : nil;
    if (!smp || !smp.frames.length) { _status.stringValue = @"Select a sample in the Samples tab first."; return; }
    uint32_t num = (uint32_t)MAX(_numField.intValue, 0);
    [self runJob:^NSString *(EDSMDIClient *c) {
        NSError *e = nil;
        if (![c masterIdentify:&e]) return [@"The sampler did not answer SMDI: " stringByAppendingString:e.localizedDescription];
        BOOL ok = [c sendSample:smp number:num name:smp.name.length ? smp.name : @"EDITOR" progress:^(double f, NSString *t) { [self progress:f text:t]; } error:&e];
        return ok ? [NSString stringWithFormat:@"Sent as sample %u. %@ The sampler's panel may be busy for a few seconds.", num, c.timingSummary] : (e.localizedDescription ?: @"Send failed");
    }];
}
- (void)receive:(id)s {
    uint32_t num = (uint32_t)MAX(_numField.intValue, 0);
    [self runJob:^NSString *(EDSMDIClient *c) {
        NSError *e = nil; EDSMDIInfo *info = nil;
        if (![c masterIdentify:&e]) return [@"The sampler did not answer SMDI: " stringByAppendingString:e.localizedDescription];
        EDSDSSample *got = [c receiveSample:num info:&info progress:^(double f, NSString *t) { [self progress:f text:t]; } error:&e];
        if (!got) return e.localizedDescription ?: @"Receive failed";
        dispatch_async(dispatch_get_main_queue(), ^{ if (self->_received) self->_received(got, info.name); });
        return [NSString stringWithFormat:@"Received sample %u “%@”: %lu frames at %u Hz into the selected sample (undo with Edit ▸ Undo). %@", num, info.name, (unsigned long)got.frames.length / 2, got.sampleRate, c.timingSummary];
    }];
}
- (void)deleteRemote:(id)s {
    uint32_t num = (uint32_t)MAX(_numField.intValue, 0);
    NSAlert *a = [NSAlert new]; a.messageText = [NSString stringWithFormat:@"Delete sample %u on the sampler?", num];
    a.informativeText = @"This removes it from the sampler's memory (not from any disk)."; [a addButtonWithTitle:@"Delete"]; [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    [self runJob:^NSString *(EDSMDIClient *c) {
        NSError *e = nil; return [c deleteSample:num error:&e] ? [NSString stringWithFormat:@"Deleted sample %u.", num] : e.localizedDescription;
    }];
}
- (void)cancel:(id)s { [_client cancel]; }
- (void)windowWillClose:(NSNotification *)n { [_client cancel]; }

// MARK: list
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)_rows.count; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    EDSMDIInfo *i = _rows[r]; NSString *k = c.identifier;
    if ([k isEqual:@"num"]) return @(i.number);
    if ([k isEqual:@"name"]) return i.name;
    if ([k isEqual:@"rate"]) return [NSString stringWithFormat:@"%u", i.sampleRate];
    if ([k isEqual:@"len"]) return @(i.length);
    if ([k isEqual:@"loop"]) return i.loopControl == 127 ? @"off" : @"on";
    return @(i.bits);
}
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger r = _list.selectedRow; if (r >= 0 && r < (NSInteger)_rows.count) _numField.intValue = _rows[r].number;
}
@end
