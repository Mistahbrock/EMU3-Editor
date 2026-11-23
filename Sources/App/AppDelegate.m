#import "AppDelegate.h"
#import "EDSettings.h"
#import "EDHelp.h"
#import "EDMainWindowController.h"

@implementation AppDelegate { EDMainWindowController *_main; }

static NSMenuItem *item(NSMenu *m, NSString *title, SEL a, NSString *key, id target) {
    NSMenuItem *i = [m addItemWithTitle:title action:a keyEquivalent:key ?: @""]; i.target = target; return i;
}

// The controller must exist before a file passed at launch is delivered (application:openFile: comes before didFinishLaunching).
- (void)applicationWillFinishLaunching:(NSNotification *)n {
    _main = [[EDMainWindowController alloc] init];
    [self buildMenus];
    [_main showWindow:nil];
    if (![NSUserDefaults.standardUserDefaults objectForKey:@"NSWindow Frame EMU3EditorMain"]) [_main.window center];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSApp.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];   // dialogs, panels and menus match the dark UI
    [NSApp activateIgnoringOtherApps:YES];
    if ([NSUserDefaults.standardUserDefaults boolForKey:@"LogInteractions"]) [self startInteractionLog];
}

// Debug aid (launch with -LogInteractions YES): writes mouse clicks, keys, the view under the pointer and the table selections after each click
// to build/interaction.log, so a problem can be reproduced by hand and read back afterwards.
static void collectTables(NSView *v, NSMutableString *out, NSInteger depth) {
    if ([v isKindOfClass:[NSTableView class]] && !v.isHiddenOrHasHiddenAncestor) {
        NSTableView *t = (NSTableView *)v;
        [out appendFormat:@"    %@ selectedRow=%ld rows=%ld\n", NSStringFromClass(t.class), (long)t.selectedRow, (long)t.numberOfRows];
    }
    for (NSView *s in v.subviews) collectTables(s, out, depth + 1);
}
- (void)startInteractionLog {
    NSString *path = [NSString stringWithFormat:@"%@/build/interaction.log", NSFileManager.defaultManager.currentDirectoryPath];
    NSString *override = [NSUserDefaults.standardUserDefaults stringForKey:@"InteractionLogPath"]; if (override.length) path = override;
    [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path]; [fh seekToEndOfFile];
    void (^log)(NSString *) = ^(NSString *s) { NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"HH:mm:ss.SSS";
        [fh writeData:[[NSString stringWithFormat:@"%@ %@\n", [f stringFromDate:NSDate.date], s] dataUsingEncoding:NSUTF8StringEncoding]]; };
    log([NSString stringWithFormat:@"logging started -> %@", path]);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskLeftMouseUp | NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        NSWindow *w = e.window; NSString *what;
        if (e.type == NSEventTypeKeyDown) what = [NSString stringWithFormat:@"key %@ (code %d)", e.charactersIgnoringModifiers, e.keyCode];
        else {
            NSView *hit = [w.contentView hitTest:[w.contentView convertPoint:e.locationInWindow fromView:nil]];
            NSString *kind = e.type == NSEventTypeLeftMouseUp ? @"mouseUp" : (e.type == NSEventTypeRightMouseDown ? @"rightDown" : @"mouseDown");
            NSString *extra = @"";
            if ([hit isKindOfClass:[NSTableView class]]) extra = [NSString stringWithFormat:@" row=%ld", (long)[(NSTableView *)hit rowAtPoint:[hit convertPoint:e.locationInWindow fromView:nil]]];
            else if ([hit.superview isKindOfClass:[NSTableView class]] || [hit.superview.superview isKindOfClass:[NSTableView class]]) extra = @" (inside table cell)";
            what = [NSString stringWithFormat:@"%@ at (%.0f,%.0f) on %@%@%@", kind, e.locationInWindow.x, e.locationInWindow.y, NSStringFromClass(hit.class), extra,
                    [hit respondsToSelector:@selector(title)] && [[hit valueForKey:@"title"] length] ? [NSString stringWithFormat:@" \"%@\"", [hit valueForKey:@"title"]] : @""];
        }
        log([NSString stringWithFormat:@"%@ | window=%@", what, w.title]);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableString *sel = [NSMutableString string]; collectTables(w.contentView, sel, 0);
            log([NSString stringWithFormat:@"  after: firstResponder=%@ tabs/tables:\n%@", NSStringFromClass(w.firstResponder.class), sel]);
        });
        return e;
    }];
}

- (void)showSettings:(id)s { [EDSettings show]; }
- (void)showHelp:(id)s { [EDHelp show]; }

- (void)buildMenus {
    NSMenu *bar = [NSMenu new]; NSApp.mainMenu = bar;
    #define SUB(title) ({ NSMenuItem *mi = [bar addItemWithTitle:title action:nil keyEquivalent:@""]; NSMenu *sm = [[NSMenu alloc] initWithTitle:title]; mi.submenu = sm; sm; })
    NSMenu *app = SUB(@"EMU3 Editor");
    item(app, @"Settings…", @selector(showSettings:), @",", self);
    [app addItem:NSMenuItem.separatorItem];
    item(app, @"Hide EMU3 Editor", @selector(hide:), @"h", NSApp);
    [app addItem:NSMenuItem.separatorItem];
    item(app, @"Quit EMU3 Editor", @selector(terminate:), @"q", NSApp);

    NSMenu *file = SUB(@"File");
    item(file, @"Open Disk Image…", @selector(openDiskImage:), @"o", _main);
    item(file, @"New Floppy Image…", @selector(newFloppyImage:), @"", _main);
    item(file, @"New Disk Image…", @selector(newDiskImage:), @"", _main);
    item(file, @"Copy Disk to SD Card…", @selector(copyToSDCard:), @"", _main);
    item(file, @"Write bluescsi.ini…", @selector(writeBlueSCSIIni:), @"", _main);
    item(file, @"Open Bank File…", @selector(openBankFile:), @"O", _main);
    [file addItem:NSMenuItem.separatorItem];
    item(file, @"Save Bank", @selector(saveBank:), @"s", _main);
    item(file, @"Save Bank As…", @selector(saveBankAs:), @"S", _main);
    [file addItem:NSMenuItem.separatorItem];
    item(file, @"Close", @selector(performClose:), @"w", nil);

    NSMenu *edit = SUB(@"Edit");
    item(edit, @"Undo", @selector(undo:), @"z", nil);
    item(edit, @"Redo", @selector(redo:), @"Z", nil);
    [edit addItem:NSMenuItem.separatorItem];
    item(edit, @"Cut", @selector(cut:), @"x", nil); item(edit, @"Copy", @selector(copy:), @"c", nil);
    item(edit, @"Paste", @selector(paste:), @"v", nil); item(edit, @"Select All", @selector(selectAll:), @"a", nil);

    NSMenu *smp = SUB(@"Sample");
    item(smp, @"Play / Stop", @selector(togglePlay:), @" ", _main);
    [smp addItem:NSMenuItem.separatorItem];
    item(smp, @"Normalize", @selector(normalize:), @"", _main);
    item(smp, @"Reverse", @selector(reverseSample:), @"", _main);
    item(smp, @"Fade In", @selector(fadeIn:), @"", _main);
    item(smp, @"Fade Out", @selector(fadeOut:), @"", _main);
    item(smp, @"Remove DC Offset", @selector(removeDC:), @"", _main);
    item(smp, @"Crop to Loop", @selector(cropToLoop:), @"", _main);
    item(smp, @"Crossfade Loop", @selector(crossfadeLoop:), @"", _main);
    [smp addItem:NSMenuItem.separatorItem];
    item(smp, @"Export as WAV…", @selector(exportWAV:), @"e", _main);
    item(smp, @"Replace from Audio…", @selector(importWAV:), @"i", _main);

    NSMenu *xfer = SUB(@"Transfer");
    item(xfer, @"SMDI Transfer (SCSI)…", @selector(smdiTransfer:), @"t", _main);
    item(xfer, @"MIDI Sample Dump…", @selector(sdsTransfer:), @"d", _main);
    [xfer addItem:NSMenuItem.separatorItem];
    item(xfer, @"Send Sample to Sampler Disk…", @selector(sendToSamplerDisk:), @"D", _main);
    item(xfer, @"Send Preset to Sampler Disk…", @selector(sendPresetToSamplerDisk:), @"", _main);
    item(xfer, @"Export Preset as Bank File…", @selector(exportPresetBank:), @"", _main);
    [xfer addItem:NSMenuItem.separatorItem];
    item(xfer, @"Show Sampler Disk in Finder", @selector(showSamplerDisk:), @"", _main);

    [xfer addItem:NSMenuItem.separatorItem];
    item(xfer, @"Utils: Assign Key…", @selector(showAssignKeys:), @"", _main);
    item(xfer, @"Utils: Channel Volume…", @selector(showChannelVolume:), @"", _main);
    item(xfer, @"Utils: Tones…", @selector(showTones:), @"", _main);

    NSMenu *view = SUB(@"View");
    item(view, @"Master", @selector(showMasterTab:), @"1", _main);
    item(view, @"Disk", @selector(showDiskTab:), @"2", _main);
    item(view, @"Samples", @selector(showSamplesTab:), @"3", _main);
    item(view, @"Presets", @selector(showPresetsTab:), @"4", _main);
    item(view, @"Tools", @selector(showToolsTab:), @"9", _main);
    item(view, @"Master ▸ MIDI", @selector(showMIDITab:), @"5", _main);
    item(view, @"Master ▸ Setup", @selector(showSetupTab:), @"6", _main);
    item(view, @"Master ▸ Bank", @selector(showBankTab:), @"7", _main);
    item(view, @"Master ▸ FX", @selector(showFXTab:), @"8", _main);
    item(view, @"FX Board Installed", @selector(toggleFXBoard:), @"", _main);
    [view addItem:NSMenuItem.separatorItem];
    item(view, @"Zoom In", @selector(zoomIn:), @"+", _main);
    item(view, @"Zoom Out", @selector(zoomOut:), @"-", _main);
    item(view, @"Fit Sample", @selector(zoomFit:), @"0", _main);
    item(view, @"Zoom to Loop", @selector(zoomLoop:), @"l", _main);

    NSMenu *win = SUB(@"Window");
    item(win, @"Minimize", @selector(performMiniaturize:), @"m", nil);
    NSApp.windowsMenu = win;
    NSMenu *help = SUB(@"Help"); item(help, @"EMU3 Editor Help", @selector(showHelp:), @"?", self); NSApp.helpMenu = help;
    #undef SUB
}

- (BOOL)application:(NSApplication *)a openFile:(NSString *)f {
    BOOL ok = [_main openURL:[NSURL fileURLWithPath:f]];
    if (ok && ![_main.window isVisible]) [_main showEditorTab:nil];
    return ok;
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)a { return [_main confirmQuit] ? NSTerminateNow : NSTerminateCancel; }
- (void)applicationWillTerminate:(NSNotification *)n { [_main closeRemoteDiskAndWait:YES]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)a { return YES; }
// MARK: About

static NSView *aboutLine(NSString *text, CGFloat size, NSColor *color, NSArray *links) {   // links: @[@[word, url], ...]
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new]; ps.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:size], NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: ps}];
    for (NSArray *l in links) { NSRange r = [text rangeOfString:l[0]]; if (r.location != NSNotFound) [as addAttributes:@{NSLinkAttributeName: l[1], NSForegroundColorAttributeName: NSColor.linkColor} range:r]; }
    // NSTextView gives the pointing-hand cursor over links (a text field does not)
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 320, 20)];
    tv.drawsBackground = NO; tv.editable = NO; tv.selectable = YES; tv.textContainerInset = NSZeroSize; tv.textContainer.lineFragmentPadding = 0;
    tv.verticallyResizable = NO; tv.horizontallyResizable = NO;
    tv.linkTextAttributes = @{NSForegroundColorAttributeName: NSColor.linkColor, NSCursorAttributeName: NSCursor.pointingHandCursor};
    [tv.textStorage setAttributedString:as];
    tv.textContainer.containerSize = NSMakeSize(320, CGFLOAT_MAX);
    [tv.layoutManager ensureLayoutForTextContainer:tv.textContainer];
    CGFloat h = ceil([tv.layoutManager usedRectForTextContainer:tv.textContainer].size.height) + 2;
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [tv.widthAnchor constraintEqualToConstant:320].active = YES; [tv.heightAnchor constraintEqualToConstant:h].active = YES;
    return tv;
}
static NSPanel *sAbout;
- (void)showAbout:(id)sender {
    if (sAbout) return;     // already showing (modal)
    NSString *ver = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0.1";
    NSString *bld = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"1";
    NSColor *dim = NSColor.secondaryLabelColor;
    NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
    [iv.widthAnchor constraintEqualToConstant:90].active = YES; [iv.heightAnchor constraintEqualToConstant:90].active = YES;
    NSTextField *title = [NSTextField labelWithString:@"EMU3 Editor"]; title.font = [NSFont boldSystemFontOfSize:17];
    NSButton *ok = [NSButton buttonWithTitle:@"OK" target:self action:@selector(closeAbout:)]; ok.keyEquivalent = @"\r";
    NSStackView *st = [NSStackView stackViewWithViews:@[
        aboutLine([NSString stringWithFormat:@"version %@ build %@ (work in progress)", ver, bld], 9, dim, @[]),
        iv,
        aboutLine(@"Rhyno Audio", 12, dim, @[@[@"Rhyno Audio", @"https://www.rhyno-audio.net"]]),
        title,
        aboutLine(@"Built with Claude", 11, dim, @[@[@"Claude", @"https://claude.ai"]]),
        aboutLine(@"Edit the samples, presets and master settings of E-mu Emulator IV / EOS and Emulator 3X / ESI-32 sampler banks and disk images.", 11, dim, @[]),
        aboutLine(@"Free and open source. If it saved you time:\nBuy me a coffee ☕", 10, dim, @[@[@"Buy me a coffee ☕", @"https://www.paypal.com/donate/?hosted_button_id=92QGBZBYGBBXY"]]),
        aboutLine(@"Source code: github.com/Mistahbrock/EMU3-Editor (GPLv3)", 10, dim, @[@[@"github.com/Mistahbrock/EMU3-Editor", @"https://github.com/Mistahbrock/EMU3-Editor"]]),
        aboutLine(@"Format knowledge based on dagargo/emu3fs · dagargo/emu3bm (GPLv3)", 10, dim, @[@[@"dagargo/emu3fs", @"https://github.com/dagargo/emu3fs"], @[@"dagargo/emu3bm", @"https://github.com/dagargo/emu3bm"]]),
        ok]];
    st.orientation = NSUserInterfaceLayoutOrientationVertical; st.alignment = NSLayoutAttributeCenterX; st.spacing = 8;
    [st setCustomSpacing:14 afterView:st.views.lastObject == ok ? st.views[st.views.count - 2] : ok];
    st.edgeInsets = NSEdgeInsetsMake(14, 20, 18, 20);
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 380, 200) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    p.title = @"About EMU3 Editor"; p.releasedWhenClosed = NO; p.contentView = st;
    [p setContentSize:st.fittingSize]; [p center]; sAbout = p;
    // modal: stays in front of the main window until OK or the close button
    __block id tok = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:p queue:nil usingBlock:^(NSNotification *n) {
        [NSNotificationCenter.defaultCenter removeObserver:tok]; sAbout = nil; [NSApp stopModal]; }];
    [NSApp runModalForWindow:p];
}
- (void)closeAbout:(id)s { [sAbout close]; }

@end
