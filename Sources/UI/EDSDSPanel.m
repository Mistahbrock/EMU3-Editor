#import "EDSDSPanel.h"
#import "EDMIDIPort.h"
#import "EDTheme.h"

@implementation EDSDSPanel {
    NSPopUpButton *_outPop, *_inPop;
    NSTextField *_devField, *_numField, *_status;
    NSProgressIndicator *_bar;
    NSButton *_fastCheck; NSPopUpButton *_bitsPop;
    NSButton *_sendBtn, *_reqBtn, *_listenBtn, *_cancelBtn;
    NSArray<EDMIDIEndpointInfo *> *_outs, *_ins;
    EDSDSEngine *_engine; EDMIDIPort *_port;
    BOOL _busy;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 300)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    w.title = @"MIDI Sample Dump (SDS)"; w.releasedWhenClosed = NO;
    if ((self = [super initWithWindow:w])) [self build];
    return self;
}

- (NSTextField *)label:(NSString *)s { return [EDTheme lcdLabel:s size:12]; }
- (NSButton *)closeButton {
    NSButton *b = [EDTheme lcdKey:@"Close" target:self.window action:@selector(performClose:)]; b.toolTip = @"Close this window.";
    [b.widthAnchor constraintEqualToConstant:100].active = YES; return b;
}
- (NSButton *)button:(NSString *)t action:(SEL)a { return [EDTheme lcdKey:t target:self action:a]; }

- (void)build {
    _outPop = [NSPopUpButton new]; _inPop = [NSPopUpButton new];
    _devField = [NSTextField textFieldWithString:@"0"]; _numField = [NSTextField textFieldWithString:@"1"];
    _bitsPop = [NSPopUpButton new]; [_bitsPop addItemsWithTitles:@[@"16-bit", @"14-bit (about 30% faster)"]];
    _devField.toolTip = @"SDS device (channel) ID, 0–127. Many samplers answer to 127 (all).";
    _numField.toolTip = @"The sample number sent in the dump header. EOS keeps sample numbers through a dump.";
    _status = [self label:@"Sampler side: Sample Manage ▸ Utils ▸ Dump… starts every transfer. To send from here, set Direction = Receive on the sampler, pick the sample, press OK, then press Send. To receive, set Direction = Transmit, then press \"Wait for dump\" here first and OK on the sampler."];
    _status.font = [EDTheme lcdFont:11]; _status.textColor = EDTheme.lcdInk; _status.maximumNumberOfLines = 6; _status.preferredMaxLayoutWidth = 480; _status.lineBreakMode = NSLineBreakByWordWrapping;
    _bar = [NSProgressIndicator new]; _bar.style = NSProgressIndicatorStyleBar; _bar.indeterminate = NO; _bar.maxValue = 1;
    _sendBtn = [self button:@"Send selected sample" action:@selector(send:)];
    _listenBtn = [self button:@"Wait for dump from sampler" action:@selector(listen:)];
    _cancelBtn = [self button:@"Cancel transfer" action:@selector(cancel:)]; _cancelBtn.enabled = NO;
    _fastCheck = [EDTheme lcdButton:@"Open loop: send without acknowledgements (single cable only)" target:nil action:nil]; [_fastCheck.widthAnchor constraintEqualToConstant:440].active = YES;
    for (NSTextField *f in @[_devField, _numField]) [EDTheme styleLCDField:f];
    NSButton *refresh = [self button:@"Refresh ports" action:@selector(refresh:)];
    _outPop.toolTip = @"The MIDI port that goes to the sampler's MIDI In (your interface's output).";
    _inPop.toolTip = @"The MIDI port that comes from the sampler's MIDI Out (your interface's input).";
    _bitsPop.toolTip = @"16-bit is the standard dump. 14-bit sends fewer bytes per sample and is faster, but not every sampler accepts it.";
    _sendBtn.toolTip = @"Send the sample that is selected in the editor to the sampler. Start Sample Manage ▸ Utils ▸ Dump on the sampler first.";
    _listenBtn.toolTip = @"Wait for the sampler to send a sample (start the dump on the sampler), and bring it into the bank.";
    _cancelBtn.toolTip = @"Stop the transfer that is running.";
    _fastCheck.toolTip = @"Do not wait for the sampler's acknowledge after each packet. Faster, but only safe on a single cable and with a good connection.";
    refresh.toolTip = @"Look for MIDI ports again, for example after plugging in an interface.";

    NSGridView *g = [NSGridView gridViewWithViews:@[
        @[[self label:@"MIDI out (to sampler)"], _outPop],
        @[[self label:@"MIDI in (from sampler)"], _inPop],
        @[[self label:@"Device ID"], _devField],
        @[[self label:@"Sample # to send as"], _numField]]];
    g.rowSpacing = 8; g.columnSpacing = 10; [g columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    NSStackView *row1 = [NSStackView stackViewWithViews:@[_sendBtn, _bitsPop]];
    NSStackView *row2 = [NSStackView stackViewWithViews:@[_listenBtn, _cancelBtn, refresh]];
    NSStackView *root = [NSStackView stackViewWithViews:@[g, row1, row2, _fastCheck, _bar, _status, [self closeButton]]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeLeading; root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    _bar.translatesAutoresizingMaskIntoConstraints = NO;
    [_bar.widthAnchor constraintEqualToConstant:484].active = YES;
    [EDTheme styleWindow:self.window]; self.window.contentView = [EDTheme lcdScreenAround:root]; [self.window setContentSize:root.fittingSize];
    [self refresh:nil];
}

- (void)refresh:(id)s {
    _outs = [EDMIDIPort destinations]; _ins = [EDMIDIPort sources];
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    NSString *po = _outPop.titleOfSelectedItem ?: [ud stringForKey:@"SDSOut"], *pi = _inPop.titleOfSelectedItem ?: [ud stringForKey:@"SDSIn"];
    if (!_devField.stringValue.length || [_devField.stringValue isEqual:@"0"]) { if ([ud objectForKey:@"SDSDevice"]) _devField.stringValue = [ud stringForKey:@"SDSDevice"]; }
    [_outPop removeAllItems]; [_inPop removeAllItems];
    for (EDMIDIEndpointInfo *e in _outs) [_outPop addItemWithTitle:e.name];
    for (EDMIDIEndpointInfo *e in _ins) [_inPop addItemWithTitle:e.name];
    if (po) [_outPop selectItemWithTitle:po]; if (pi) [_inPop selectItemWithTitle:pi];
    if (!_outs.count) { [_outPop addItemWithTitle:@"(no MIDI outputs found)"]; }
    if (!_ins.count) { [_inPop addItemWithTitle:@"(no MIDI inputs found)"]; }
    [EDTheme styleLCDPopup:_outPop]; [EDTheme styleLCDPopup:_inPop]; [EDTheme styleLCDPopup:_bitsPop];
}

- (void)present {
    [self refresh:nil];
    EDSDSSample *cur = _currentSample ? _currentSample() : nil; if (cur) _numField.intValue = cur.number;
    [self.window center]; [self showWindow:nil]; [self.window makeKeyAndOrderFront:nil];
}

- (void)setBusy:(BOOL)b {
    _busy = b; _sendBtn.enabled = _listenBtn.enabled = !b; _cancelBtn.enabled = b;
    _outPop.enabled = _inPop.enabled = _devField.enabled = _bitsPop.enabled = !b;
}

/// Opens the ports and a fresh engine; returns NO with a message in the status line if no ports were chosen.
- (BOOL)prepareNeedIn:(BOOL)needIn needOut:(BOOL)needOut {
    NSInteger oi = _outPop.indexOfSelectedItem, ii = _inPop.indexOfSelectedItem;
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud setObject:_outPop.titleOfSelectedItem forKey:@"SDSOut"]; [ud setObject:_inPop.titleOfSelectedItem forKey:@"SDSIn"]; [ud setObject:_devField.stringValue forKey:@"SDSDevice"];
    EDMIDIEndpointInfo *o = (_outs.count && oi >= 0) ? _outs[oi] : nil, *i = (_ins.count && ii >= 0) ? _ins[ii] : nil;
    if ((needOut && !o) || (needIn && !i)) { _status.stringValue = @"Choose the MIDI ports first (connect the sampler's MIDI cables or USB interface)."; return NO; }
    _port = [EDMIDIPort new]; NSError *e = nil;
    if (![_port connectSource:i destination:o error:&e]) { _status.stringValue = e.localizedDescription; return NO; }
    _engine = [EDSDSEngine new]; _engine.deviceID = (uint8_t)(_devField.intValue & 0x7F); _engine.openLoop = _fastCheck.state == NSControlStateValueOn;
    EDMIDIPort *port = _port;
    _engine.transmit = ^(NSData *m) { [port sendSysex:m]; };
    EDSDSEngine *eng = _engine;
    _port.onSysex = ^(NSData *m) { [eng deliver:m]; };
    return YES;
}

- (void)finish:(NSString *)msg {
    [self setBusy:NO]; _status.stringValue = msg; [_port disconnect]; _port = nil; _engine = nil;
}
- (void)progress:(double)f text:(NSString *)t {
    static NSDate *start; if (f <= 0 || !start) start = [NSDate date];
    NSTimeInterval el = -[start timeIntervalSinceNow];
    NSString *eta = (f > 0.02 && f < 1) ? [NSString stringWithFormat:@" — %.0f s elapsed, about %.0f s left", el, el / f - el] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{ self->_bar.doubleValue = f; self->_status.stringValue = [t stringByAppendingString:eta]; });
}

- (void)send:(id)s {
    EDSDSSample *smp = _currentSample ? _currentSample() : nil;
    if (smp) { smp.number = (uint16_t)MAX(_numField.intValue, 0); smp.bits = _bitsPop.indexOfSelectedItem == 1 ? 14 : 16; }
    if (!smp || !smp.frames.length) { _status.stringValue = @"Select a sample in the Samples tab first."; return; }
    if (![self prepareNeedIn:NO needOut:YES]) return;
    [self setBusy:YES]; _bar.doubleValue = 0;
    EDSDSEngine *eng = _engine; EDMIDIPort *port = _port;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *e = nil;
        BOOL ok = [eng sendSample:smp progress:^(double f, NSString *t) { [self progress:f text:t]; } error:&e];
        [port flush];
        dispatch_async(dispatch_get_main_queue(), ^{ [self finish:ok ? [@"Sent. Check the sampler for the new sample. " stringByAppendingString:eng.timingSummary] : (e.localizedDescription ?: @"Send failed")]; });
    });
}

- (void)receiveWithRequest:(int)req timeout:(NSTimeInterval)t {
    if (![self prepareNeedIn:YES needOut:req >= 0]) return;
    [self setBusy:YES]; _bar.doubleValue = 0;
    EDSDSEngine *eng = _engine;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *e = nil;
        EDSDSSample *got = [eng receiveWithRequest:req headerTimeout:t progress:^(double f, NSString *tx) { [self progress:f text:tx]; } error:&e];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (got && self->_received) self->_received(got);
            [self finish:got ? [NSString stringWithFormat:@"Received %lu frames at %u Hz into the selected sample (undo with Edit ▸ Undo). %@",
                                (unsigned long)got.frames.length / 2, got.sampleRate, eng.timingSummary] : (e.localizedDescription ?: @"Receive failed")];
        });
    });
}
- (void)listen:(id)s { [self receiveWithRequest:-1 timeout:120]; }
- (void)cancel:(id)s { [_engine cancel]; }
- (void)windowWillClose:(NSNotification *)n { [_engine cancel]; }
@end
