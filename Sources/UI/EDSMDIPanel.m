#import "EDSMDIPanel.h"
#import "EDTheme.h"

@implementation EDSMDIPanel {
    NSPopUpButton *_portPop;
    NSTextField *_idField, *_numField, *_status;
    NSTableView *_list; NSMutableArray<EDSMDIInfo *> *_rows;
    NSProgressIndicator *_bar;
    NSButton *_sendBtn, *_recvBtn, *_scanBtn, *_cancelBtn, *_delBtn;
    EDSMDIBoard *_board; EDSMDIClient *_client;
    BOOL _busy, _restoreTarget;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 480)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"SMDI Transfer (SCSI)"; w.releasedWhenClosed = NO;
    if ((self = [super initWithWindow:w])) { _rows = [NSMutableArray array]; [self build]; }
    return self;
}
- (NSButton *)button:(NSString *)t action:(SEL)a { return [EDTheme lcdKey:t target:self action:a]; }

- (void)build {
    _portPop = [NSPopUpButton new];
    _idField = [NSTextField textFieldWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"SMDITarget"] ?: @"6"];
    _numField = [NSTextField textFieldWithString:@"1"];
    _idField.toolTip = @"The sampler's SCSI ID (Master ▸ Setup ▸ SCSI/Disk). The BlueSCSI board uses ID 7 — set \"Avoid Host on ID\" to 7 on the sampler.";
    _numField.toolTip = @"Sample number on the sampler, 1–999 (the number the sampler's display shows). Sample 0 is the sampler's clipboard and cannot be used over SMDI.";
    _status = [NSTextField wrappingLabelWithString:@"Needs the BlueSCSI board with the SMDI firmware, connected to the sampler's SCSI port. If the board is serving a disk it is switched to SMDI mode automatically (it reboots, a few seconds) and switched back when you close this window."];
    _status.font = [EDTheme lcdFont:11]; _status.textColor = EDTheme.lcdInk; _status.preferredMaxLayoutWidth = 520; _status.maximumNumberOfLines = 6;
    _bar = [NSProgressIndicator new]; _bar.style = NSProgressIndicatorStyleBar; _bar.indeterminate = NO; _bar.maxValue = 1;
    _scanBtn = [self button:@"Read sample list" action:@selector(scan:)];
    _sendBtn = [self button:@"Send selected sample →" action:@selector(send:)];
    _recvBtn = [self button:@"← Receive into selected sample" action:@selector(receive:)];
    _delBtn = [self button:@"Delete on sampler" action:@selector(deleteRemote:)];
    _cancelBtn = [self button:@"Cancel" action:@selector(cancel:)]; _cancelBtn.enabled = NO;
    NSButton *refresh = [self button:@"Refresh ports" action:@selector(refresh:)];
    for (NSTextField *f in @[_idField, _numField]) [EDTheme styleLCDField:f];

    _list = [NSTableView new];
    for (NSArray *c in @[@[@"num", @"#", @50], @[@"name", @"Name", @170], @[@"rate", @"Rate", @70], @[@"len", @"Frames", @80], @[@"loop", @"Loop", @60], @[@"bits", @"Bits", @40]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_list addTableColumn:col];
    }
    _list.dataSource = (id)self; _list.delegate = (id)self; [EDTheme styleLCDTable:_list];
    NSScrollView *sv = [NSScrollView new]; sv.documentView = _list; sv.hasVerticalScroller = YES; sv.borderType = NSNoBorder;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv.widthAnchor constraintEqualToConstant:520].active = YES; [sv.heightAnchor constraintEqualToConstant:170].active = YES;

    NSTextField *note = [NSTextField wrappingLabelWithString:@"1–999, as on the sampler's display (S001…). Sample 0 (S000) is the sampler's clipboard; SMDI refuses it."];
    note.font = [EDTheme lcdFont:10]; note.textColor = EDTheme.lcdInk; note.preferredMaxLayoutWidth = 391;
    NSGridView *g = [NSGridView gridViewWithViews:@[
        @[[EDTheme lcdLabel:@"BlueSCSI serial port" size:12], _portPop],
        @[[EDTheme lcdLabel:@"Sampler SCSI ID" size:12], _idField],
        @[[EDTheme lcdLabel:@"Sample #" size:12], _numField],
        @[[NSGridCell emptyContentView], note]]];
    g.rowSpacing = 8; g.columnSpacing = 10; [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    NSStackView *r1 = [NSStackView stackViewWithViews:@[_scanBtn, _sendBtn, _recvBtn]];
    NSStackView *r2 = [NSStackView stackViewWithViews:@[_delBtn, _cancelBtn, refresh]];
    NSStackView *root = [NSStackView stackViewWithViews:@[g, sv, r1, r2, _bar, _status]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeLeading; root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    _bar.translatesAutoresizingMaskIntoConstraints = NO; [_bar.widthAnchor constraintEqualToConstant:520].active = YES;
    self.window.delegate = (id)self; [EDTheme styleWindow:self.window]; self.window.contentView = [EDTheme lcdScreenAround:root]; [self.window setContentSize:root.fittingSize];
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
    [EDTheme styleLCDPopup:_portPop];
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

- (void)progress:(double)f text:(NSString *)t {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_bar.doubleValue = f; self->_status.stringValue = t; });
}
- (void)finish:(NSString *)msg {
    [self setBusy:NO]; _status.stringValue = msg; _bar.doubleValue = 0;
}
/// Connects to the board (switching it from disk/target mode to initiator mode when needed) and runs `job` on a background queue.
- (void)runJob:(NSString *(^)(EDSMDIClient *))job {
    NSString *port = _portPop.titleOfSelectedItem;
    if (![port hasPrefix:@"/dev/"]) { _status.stringValue = @"No BlueSCSI serial port found. Plug the board in (SMDI firmware)."; return; }
    int sid = _idField.intValue;
    if (sid < 0 || sid > 6) { _status.stringValue = @"The sampler's SCSI ID must be 0–6 (the board itself uses 7)."; return; }
    [NSUserDefaults.standardUserDefaults setObject:@(sid).stringValue forKey:@"SMDITarget"];
    [self setBusy:YES]; _bar.doubleValue = 0; _status.stringValue = @"Connecting to the board…";
    EDSMDIBoard *have = (_board && [_board.path isEqual:port]) ? _board : nil;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        EDSMDIBoard *b = have; NSError *e = nil; BOOL switched = NO;
        if (!b) {
            b = [EDSMDIBoard new];
            if (![b openPath:port error:&e]) {
                // no answer: the board is probably serving a disk (target mode). Reboot it into initiator mode.
                dispatch_async(dispatch_get_main_queue(), ^{ self->_status.stringValue = @"The board is in disk (target) mode — switching it to SMDI mode, a few seconds…"; });
                NSString *np = [EDSMDIBoard switchMode:'i' passthroughPort:port];
                b = [EDSMDIBoard new]; e = nil;
                if (!np || ![b openPath:np error:&e]) {
                    NSString *msg = e.localizedDescription ?: @"The board did not come back after switching modes.";
                    dispatch_async(dispatch_get_main_queue(), ^{ [self finish:msg]; });
                    return;
                }
                switched = YES;
            }
        }
        EDSMDIClient *c = [[EDSMDIClient alloc] initWithExec:b.executor target:(uint8_t)sid];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_board = b; self->_client = c; if (switched) self->_restoreTarget = YES; [self refresh:nil]; });
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
    if (![EDTheme confirm:[NSString stringWithFormat:@"Deletes sample %u from the sampler's memory (not from any disk). Continue?", num] okTitle:@"OK" cancelTitle:@"Cancel"]) return;
    [self runJob:^NSString *(EDSMDIClient *c) {
        NSError *e = nil; return [c deleteSample:num error:&e] ? [NSString stringWithFormat:@"Deleted sample %u.", num] : e.localizedDescription;
    }];
}
- (void)cancel:(id)s { [_client cancel]; }
- (void)windowWillClose:(NSNotification *)n {
    [_client cancel];
    // we took the board out of disk mode for SMDI: put it back so the sampler sees the served disk again
    if (_restoreTarget && _board.path) {
        NSString *port = _board.path; [_board close]; _board = nil; _restoreTarget = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ [EDSMDIBoard switchMode:'t' passthroughPort:port]; });
    }
}

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
