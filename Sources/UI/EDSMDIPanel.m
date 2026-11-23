#import "EDSMDIPanel.h"
#import "EDTheme.h"

@implementation EDSMDIPanel {
    NSPopUpButton *_portPop;
    NSTextField *_idField, *_numField, *_status;
    NSTableView *_list; NSMutableArray<EDSMDIInfo *> *_rows;
    NSProgressIndicator *_bar;
    NSButton *_sendBtn, *_recvBtn, *_scanBtn, *_cancelBtn, *_delBtn, *_findBtn;
    EDSMDIBoard *_board; EDSMDIClient *_client;
    NSTableView *_devList; NSScrollView *_svSamples, *_svDevs; NSMutableArray<EDSMDIDevice *> *_devs; NSTextField *_head; NSGridView *_grid; NSStackView *_rowRead, *_rowXfer, *_rowDel; BOOL _findMode;
    BOOL _busy, _restoreTarget; pid_t _frozenLink;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 480)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"SMDI Transfer (SCSI)"; w.releasedWhenClosed = NO;
    if ((self = [super initWithWindow:w])) { _rows = [NSMutableArray array]; _devs = [NSMutableArray array]; [self build]; }
    return self;
}
- (NSButton *)button:(NSString *)t action:(SEL)a { return [NSButton buttonWithTitle:t target:self action:a]; }
static NSTextField *Lbl(NSString *t) { NSTextField *l = [NSTextField labelWithString:t]; l.font = [NSFont systemFontOfSize:13]; return l; }

- (void)build {
    _portPop = [NSPopUpButton new];
    _idField = [NSTextField textFieldWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"SMDITarget"] ?: @"6"];
    _numField = [NSTextField textFieldWithString:@"1"];
    _idField.toolTip = @"The sampler's SCSI ID (Master ▸ Setup ▸ SCSI/Disk). The BlueSCSI board uses ID 7 — set \"Avoid Host on ID\" to 7 on the sampler.";
    _numField.toolTip = @"Sample number on the sampler, 1–999 (the number the sampler's display shows). Sample 0 is the sampler's clipboard and cannot be used over SMDI.";
    _status = [NSTextField wrappingLabelWithString:@"Needs the BlueSCSI board with the SMDI firmware, connected to the sampler's SCSI port. If the board is serving a disk it is switched to SMDI mode automatically (it reboots, a few seconds) and switched back when you close this window."];
    _status.font = [NSFont systemFontOfSize:11]; _status.textColor = NSColor.secondaryLabelColor; _status.preferredMaxLayoutWidth = 520; _status.alignment = NSTextAlignmentCenter; _status.maximumNumberOfLines = 12;
    _bar = [NSProgressIndicator new]; _bar.style = NSProgressIndicatorStyleBar; _bar.indeterminate = NO; _bar.maxValue = 1;
    _scanBtn = [self button:@"Read sample list" action:@selector(scan:)];
    _findBtn = [self button:@"Find sampler (scan IDs)" action:@selector(findSampler:)];
    _sendBtn = [self button:@"Send selected sample →" action:@selector(send:)];
    _recvBtn = [self button:@"← Receive into selected sample" action:@selector(receive:)];
    _delBtn = [self button:@"Delete on sampler" action:@selector(deleteRemote:)];
    _cancelBtn = [self button:@"Cancel" action:@selector(cancel:)]; _cancelBtn.enabled = NO;
    NSButton *refresh = [self button:@"Refresh ports" action:@selector(refresh:)];
    for (NSTextField *f in @[_idField, _numField]) [f.widthAnchor constraintEqualToConstant:80].active = YES;

    _list = [NSTableView new];
    for (NSArray *c in @[@[@"num", @"#", @50], @[@"name", @"Name", @170], @[@"rate", @"Rate", @70], @[@"len", @"Frames", @80], @[@"loop", @"Loop", @60], @[@"bits", @"Bits", @40]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; [_list addTableColumn:col];
    }
    _list.dataSource = (id)self; _list.delegate = (id)self;
    NSScrollView *sv = [NSScrollView new]; sv.documentView = _list; sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder;
    sv.translatesAutoresizingMaskIntoConstraints = NO;
    [sv.widthAnchor constraintEqualToConstant:520].active = YES; [sv.heightAnchor constraintEqualToConstant:170].active = YES;

    _devList = [NSTableView new];
    for (NSArray *c in @[@[@"id", @"ID", @40], @[@"type", @"Type", @90], @[@"dev", @"Device", @270], @[@"rev", @"Rev", @70]]) {
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:c[0]]; col.title = c[1]; col.width = [c[2] doubleValue]; col.editable = NO; [_devList addTableColumn:col];
    }
    _devList.dataSource = (id)self; _devList.delegate = (id)self;
    NSScrollView *dv = [NSScrollView new]; dv.documentView = _devList; dv.hasVerticalScroller = YES; dv.borderType = NSBezelBorder; dv.translatesAutoresizingMaskIntoConstraints = NO;
    [dv.widthAnchor constraintEqualToConstant:520].active = YES; [dv.heightAnchor constraintEqualToConstant:120].active = YES;
    _svSamples = sv; _svDevs = dv;
    NSTextField *note = [NSTextField wrappingLabelWithString:@"1–999, as on the sampler's display (S001…). Sample 0 (S000) is the sampler's clipboard; SMDI refuses it."];
    note.font = [NSFont systemFontOfSize:11]; note.textColor = NSColor.secondaryLabelColor; note.preferredMaxLayoutWidth = 391;
    NSGridView *g = [NSGridView gridViewWithViews:@[
        @[Lbl(@"BlueSCSI serial port"), _portPop],
        @[Lbl(@"Sampler SCSI ID"), _idField],
        @[Lbl(@"Sample #"), _numField],
        @[[NSGridCell emptyContentView], note]]];
    g.rowSpacing = 8; g.columnSpacing = 10; [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    NSStackView *r0 = [NSStackView stackViewWithViews:@[_findBtn, _scanBtn]];
    NSStackView *r1 = [NSStackView stackViewWithViews:@[_sendBtn, _recvBtn]];
    NSStackView *r2 = [NSStackView stackViewWithViews:@[_delBtn, _cancelBtn, refresh]];
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
    [icon.widthAnchor constraintEqualToConstant:64].active = YES; [icon.heightAnchor constraintEqualToConstant:64].active = YES;
    NSTextField *head = [NSTextField labelWithString:@"SMDI Transfer (SCSI)"]; head.font = [NSFont boldSystemFontOfSize:15];
    NSStackView *root = [NSStackView stackViewWithViews:@[icon, head, g, sv, dv, r0, r1, r2, _bar, _status]];
    _head = head; _grid = g; _rowRead = r0; _rowXfer = r1; _rowDel = r2;
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeCenterX; root.spacing = 12;
    [icon.centerXAnchor constraintEqualToAnchor:root.centerXAnchor].active = YES; [head.centerXAnchor constraintEqualToAnchor:root.centerXAnchor].active = YES;
    root.edgeInsets = NSEdgeInsetsMake(20, 24, 20, 24);
    _bar.translatesAutoresizingMaskIntoConstraints = NO; [_bar.widthAnchor constraintEqualToConstant:520].active = YES;
    self.window.delegate = (id)self; [EDTheme styleWindow:self.window]; self.window.contentView = root; { NSSize fs = root.fittingSize; [self.window setContentSize:NSMakeSize(fs.width, fs.height)]; }
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
- (void)setFindMode:(BOOL)f {
    _findMode = f;
    self.window.title = f ? @"Find Sampler" : @"SMDI Transfer (SCSI)"; _head.stringValue = self.window.title;
    _svSamples.hidden = f; _svDevs.hidden = !f; _rowXfer.hidden = _rowDel.hidden = f;
    _scanBtn.hidden = f; _findBtn.hidden = !f;
    [_grid rowAtIndex:2].hidden = f; [_grid rowAtIndex:3].hidden = f;   // sample #, its note
    NSSize fs = self.window.contentView.fittingSize; [self.window setContentSize:NSMakeSize(fs.width, fs.height)];
}
- (void)present {
    [self setFindMode:NO];
    [self refresh:nil];
    if (_numField.intValue < 1) _numField.intValue = 1;      // always start at S001; the bank's own sample number is not the sampler's slot
    [self.window center]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}
- (void)setBusy:(BOOL)b {
    _busy = b; _findBtn.enabled = _scanBtn.enabled = _sendBtn.enabled = _recvBtn.enabled = _delBtn.enabled = !b; _cancelBtn.enabled = b;
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
        if (!b && !self->_frozenLink) {
            pid_t fp = [EDSMDIBoard suspendLinkHelper];       // the Disk Manager helper would otherwise eat the board's replies
            if (fp) dispatch_sync(dispatch_get_main_queue(), ^{ self->_frozenLink = fp; });
        }
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

static NSString *Hex(NSData *d, NSUInteger from) {
    NSMutableString *h = [NSMutableString string]; const uint8_t *p = d.bytes;
    for (NSUInteger i = from; i < d.length; i++) [h appendFormat:@"%02X ", p[i]];
    return h;
}
- (void)findSampler:(id)s {
    [self runJob:^NSString *(EDSMDIClient *c) {
        [self progress:0.1 text:@"Scanning SCSI IDs 0–6…"];
        NSArray<EDSMDIDevice *> *devs = [EDSMDIClient scanBus:c.exec skipping:7 cancelled:nil];
        if (!devs.count) return @"No device answered on SCSI IDs 0–6. Check the cable, termination and that the sampler is on.";
        NSMutableString *out = [NSMutableString string]; EDSMDIDevice *found = nil;
        for (EDSMDIDevice *d in devs) if (!found && d.looksLikeSampler) found = d;
        dispatch_async(dispatch_get_main_queue(), ^{ [self->_devs setArray:devs]; [self->_devList reloadData]; });
        if (found) {
            c.target = found.scsiID;
            NSError *e = nil;
            if ([c masterIdentify:&e]) [out appendFormat:@"%@ %@ (software %@) answered SMDI at ID %u.\n", found.vendor, found.product, found.revision, found.scsiID];
            else [out appendFormat:@"ID %u did not answer SMDI: %@\n", found.scsiID, e.localizedDescription];
            dispatch_async(dispatch_get_main_queue(), ^{ self->_idField.intValue = found.scsiID; [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"%@ %@ %@", found.vendor, found.product, found.revision] forKey:@"SamplerModel"]; if (self->_foundSampler) self->_foundSampler(); [NSUserDefaults.standardUserDefaults setObject:@(found.scsiID).stringValue forKey:@"SMDITarget"]; });
            [out appendFormat:@"Sampler set to SCSI ID %u.", found.scsiID];
        } else [out appendString:@"None of them looks like a sampler. Pick the ID by hand."];
        return out;
    }];
}
- (void)presentAndFind { [self present]; [self setFindMode:YES]; [self findSampler:nil]; }
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
        return ok ? [NSString stringWithFormat:@"Sent as sample %u. %@ The sampler's display does not refresh by itself: press INC or DEC on the sampler to see the new sample.", num, c.timingSummary] : (e.localizedDescription ?: @"Send failed");
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
    NSString *port = _board.path; BOOL restore = _restoreTarget && port; pid_t fp = _frozenLink;
    [_board close]; _board = nil; _restoreTarget = NO; _frozenLink = 0;
    if (restore || fp) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (restore) [EDSMDIBoard switchMode:'t' passthroughPort:port];
        [EDSMDIBoard resumeLinkHelper:fp];                     // let the Disk Manager helper have the board again
    });
}

// MARK: list
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)(t == _devList ? _devs.count : _rows.count); }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    if (t == _devList) {
        EDSMDIDevice *d = _devs[r]; NSString *k = c.identifier;
        if ([k isEqual:@"id"]) return @(d.scsiID);
        if ([k isEqual:@"type"]) return d.typeName;
        if ([k isEqual:@"dev"]) return [NSString stringWithFormat:@"%@ %@", d.vendor, d.product];
        return d.revision;
    }
    EDSMDIInfo *i = _rows[r]; NSString *k = c.identifier;
    if ([k isEqual:@"num"]) return @(i.number);
    if ([k isEqual:@"name"]) return i.name;
    if ([k isEqual:@"rate"]) return [NSString stringWithFormat:@"%u", i.sampleRate];
    if ([k isEqual:@"len"]) return @(i.length);
    if ([k isEqual:@"loop"]) return i.loopControl == 127 ? @"off" : @"on";
    return @(i.bits);
}
- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (n.object == _devList) { NSInteger q = _devList.selectedRow; if (q >= 0 && q < (NSInteger)_devs.count) { _idField.intValue = _devs[q].scsiID; [NSUserDefaults.standardUserDefaults setObject:@(_devs[q].scsiID).stringValue forKey:@"SMDITarget"]; } return; }
    NSInteger r = _list.selectedRow; if (r >= 0 && r < (NSInteger)_rows.count) _numField.intValue = _rows[r].number;
}
@end
