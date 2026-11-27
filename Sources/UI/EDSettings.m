#import "EDSettings.h"
#import "EDTheme.h"
#import "EDAddOns.h"
#import "EDAlert.h"
#import "EDPreset+Params.h"
#import <objc/runtime.h>

// Tool tips on / off: every NSView tool tip is kept aside and only handed to AppKit while tool tips are on.
static char kRealTip;
static BOOL TipsOn(void) { return ![NSUserDefaults.standardUserDefaults boolForKey:@"HideToolTips"]; }
@interface NSView (EDToolTips) @end
@implementation NSView (EDToolTips)
+ (void)load {
    Method a = class_getInstanceMethod(self, @selector(setToolTip:)), b = class_getInstanceMethod(self, @selector(ed_setToolTip:));
    method_exchangeImplementations(a, b);
}
- (void)ed_setToolTip:(NSString *)t { objc_setAssociatedObject(self, &kRealTip, t, OBJC_ASSOCIATION_COPY_NONATOMIC); [self ed_setToolTip:TipsOn() ? t : nil]; }
- (void)ed_applyToolTips {
    NSString *t = objc_getAssociatedObject(self, &kRealTip); if (t) [self ed_setToolTip:t];
    for (NSView *v in self.subviews) [v ed_applyToolTips];
    if ([self isKindOfClass:NSTabView.class]) for (NSTabViewItem *it in ((NSTabView *)self).tabViewItems) [it.view ed_applyToolTips];
}
@end

// folder kinds: title, "last used" key (written by the dialogs), "fixed" key (set here; wins over the last used folder)
static NSArray<NSArray<NSString *> *> *FolderKinds(void) {
    return @[@[@"Converted banks and presets", @"LastFolderConvert", @"FixedFolderConvert"],
             @[@"Banks (open, save as)", @"LastFolderBank", @"FixedFolderBank"],
             @[@"Audio (WAV export, replace)", @"LastFolderAudio", @"FixedFolderAudio"],
             @[@"Disk images", @"LastFolderDisk", @"FixedFolderDisk"]];
}

@interface EDSettings () <NSWindowDelegate>
@end

@implementation EDSettings {
    NSWindow *_win;
    NSMutableArray<NSTextField *> *_pathFields;
    NSButton *_autoSave, *_offerConvert, *_tips; NSTextField *_modelLabel; NSPopUpButton *_auditionKey;
    NSButton *_removeAddOns; NSTextField *_addOnLabel;
}

+ (void)show {
    static EDSettings *s; if (!s) { s = [EDSettings new]; [s build]; }
    [s refresh]; [s->_win makeKeyAndOrderFront:nil];
}

static NSTextField *label(NSString *t, BOOL bold) {
    NSTextField *f = [NSTextField labelWithString:t]; f.font = [NSFont systemFontOfSize:13 weight:bold ? NSFontWeightBold : NSFontWeightRegular];
    if (bold) f.textColor = NSColor.secondaryLabelColor; return f;
}
static NSView *rule(void) {
    NSView *v = [NSView new]; v.wantsLayer = YES; v.layer.backgroundColor = EDTheme.accent.CGColor; v.translatesAutoresizingMaskIntoConstraints = NO;
    [v.heightAnchor constraintEqualToConstant:2].active = YES; return v;
}

- (void)build {
    _win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 100) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _win.title = @"Settings"; _win.releasedWhenClosed = NO; _win.delegate = self; [EDTheme styleWindow:_win];
    NSStackView *col = [NSStackView stackViewWithViews:@[]]; col.orientation = NSUserInterfaceLayoutOrientationVertical; col.alignment = NSLayoutAttributeLeading; col.spacing = 8;
    col.edgeInsets = NSEdgeInsetsMake(20, 24, 22, 24);
    void (^section)(NSString *) = ^(NSString *t) {
        if (col.arrangedSubviews.count) [col setCustomSpacing:20 afterView:col.arrangedSubviews.lastObject];
        [col addArrangedSubview:label(t.uppercaseString, YES)]; NSView *r = rule(); [col addArrangedSubview:r];
        [r.widthAnchor constraintEqualToAnchor:col.widthAnchor constant:-48].active = YES; [col setCustomSpacing:12 afterView:r];
    };

    section(@"Folders for file dialogs");
    NSTextField *hint = label(@"Each dialog opens in the folder you used last. Choose a folder to always start there instead.", NO); hint.textColor = NSColor.secondaryLabelColor; hint.font = [NSFont systemFontOfSize:12];
    [col addArrangedSubview:hint];
    _pathFields = [NSMutableArray array];
    NSInteger i = 0;
    for (NSArray<NSString *> *k in FolderKinds()) {
        NSTextField *name = label(k[0], NO); [name.widthAnchor constraintEqualToConstant:180].active = YES;
        NSTextField *path = [NSTextField labelWithString:@""]; path.lineBreakMode = NSLineBreakByTruncatingMiddle; path.font = [NSFont systemFontOfSize:12];
        [path.widthAnchor constraintEqualToConstant:200].active = YES; [_pathFields addObject:path];
        NSButton *choose = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(chooseFolder:)]; choose.tag = i; choose.toolTip = @"Pick a folder that this kind of dialog always opens in.";
        NSButton *reset = [NSButton buttonWithTitle:@"Last Used" target:self action:@selector(resetFolder:)]; reset.tag = i; reset.toolTip = @"Follow the folder you used last again.";
        NSStackView *row = [NSStackView stackViewWithViews:@[name, path, choose, reset]]; row.spacing = 8; [col addArrangedSubview:row]; i++;
    }

    section(@"Sampler");
    _modelLabel = label(@"", NO);
    _autoSave = [NSButton checkboxWithTitle:@"Save to the sampler's disk automatically (a few seconds after you stop editing)" target:self action:@selector(autoChanged:)];
    [col addArrangedSubview:_modelLabel]; [col addArrangedSubview:_autoSave];

    section(@"Banks");
    _offerConvert = [NSButton checkboxWithTitle:@"Offer to convert older Emulator 3X / ESI-32 banks when one is opened" target:self action:@selector(offerChanged:)];
    [col addArrangedSubview:_offerConvert];
    section(@"Audition");
    NSTextField *ah = label(@"On the Presets page, Space plays this key on the selected preset (hold it to sustain).", NO); ah.textColor = NSColor.secondaryLabelColor; ah.font = [NSFont systemFontOfSize:12];
    _auditionKey = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger n = 0; n < 128; n++) { [_auditionKey addItemWithTitle:[NSString stringWithFormat:@"%@   (%ld)", [EDParam noteName:n], (long)n]]; _auditionKey.lastItem.tag = n; }
    _auditionKey.target = self; _auditionKey.action = @selector(auditionChanged:); _auditionKey.toolTip = @"The key that Space plays on the Presets page.";
    NSStackView *arow = [NSStackView stackViewWithViews:@[label(@"Audition key", NO), _auditionKey]]; arow.spacing = 12;
    [col addArrangedSubview:ah]; [col addArrangedSubview:arow];
    section(@"Add Ons");
    _addOnLabel = label(@"", NO); _addOnLabel.textColor = NSColor.secondaryLabelColor; _addOnLabel.font = [NSFont systemFontOfSize:12];
    _addOnLabel.lineBreakMode = NSLineBreakByTruncatingTail; [_addOnLabel.widthAnchor constraintEqualToConstant:590].active = YES;
    _removeAddOns = [NSButton buttonWithTitle:@"Remove Add Ons…" target:self action:@selector(removeAddOns:)];
    _removeAddOns.toolTip = @"Moves the installed Add Ons to the Trash. Emu_Imager stays.";
    [col addArrangedSubview:_addOnLabel]; [col addArrangedSubview:_removeAddOns];
    section(@"Help");
    _autoSave.toolTip = @"When the open bank is on the sampler's disk, write it back a few seconds after you stop editing.";
    _offerConvert.toolTip = @"When you open a 3X / ESI-32 bank, ask whether to make an EOS copy.";
    _tips = [NSButton checkboxWithTitle:@"Show tool tips (hints when the pointer rests on a control)" target:self action:@selector(tipsChanged:)];
    [col addArrangedSubview:_tips];
    NSButton *done = [NSButton buttonWithTitle:@"Done" target:self action:@selector(done:)]; done.keyEquivalent = @"\r";
    [done.widthAnchor constraintEqualToConstant:100].active = YES;
    done.toolTip = @"Close Settings. Changes are already saved.";
    NSButton *defs = [NSButton buttonWithTitle:@"Set Defaults" target:self action:@selector(setDefaults:)]; defs.toolTip = @"Puts every setting on this page back to how it was when the app was new.";
    [col setCustomSpacing:22 afterView:_tips]; [col addArrangedSubview:defs];
    [col setCustomSpacing:12 afterView:defs]; [col addArrangedSubview:done];
    [done.centerXAnchor constraintEqualToAnchor:col.centerXAnchor].active = YES;

    NSView *content = [NSView new]; col.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:col];
    [NSLayoutConstraint activateConstraints:@[[col.topAnchor constraintEqualToAnchor:content.topAnchor], [col.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [col.trailingAnchor constraintEqualToAnchor:content.trailingAnchor], [col.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]]];
    _win.contentView = content; NSSize fit = content.fittingSize; [_win setContentSize:NSMakeSize(MAX(fit.width, 660), fit.height)]; [_win center];
}

- (void)done:(id)s { [_win close]; }

- (void)refresh {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSInteger i = 0;
    for (NSArray<NSString *> *k in FolderKinds()) {
        NSString *fixed = [d stringForKey:k[2]], *last = [d stringForKey:k[1]];
        _pathFields[i].stringValue = fixed.length ? fixed.stringByAbbreviatingWithTildeInPath : (last.length ? [@"Last used: " stringByAppendingString:last.stringByAbbreviatingWithTildeInPath] : @"Last used (none yet)");
        _pathFields[i].textColor = fixed.length ? NSColor.labelColor : NSColor.secondaryLabelColor; i++;
    }
    NSString *model = [d stringForKey:@"SamplerModel"]; _modelLabel.stringValue = model.length ? [@"Sampler found on the SCSI bus: " stringByAppendingString:model] : @"Sampler not scanned yet (Tools ▸ Find Sampler)";
    _autoSave.state = [d boolForKey:@"AutoSaveToSampler"] ? NSControlStateValueOn : NSControlStateValueOff;
    { NSInteger ak = [d objectForKey:@"AuditionKey"] ? [d integerForKey:@"AuditionKey"] : 60; [_auditionKey selectItemWithTag:MAX(0, MIN(127, ak))]; }
    _tips.state = TipsOn() ? NSControlStateValueOn : NSControlStateValueOff;
    _offerConvert.state = [d boolForKey:@"SkipConvertOffer"] ? NSControlStateValueOff : NSControlStateValueOn;
    NSArray<NSString *> *extra = [self addOnNames:[self removableAddOns]];
    _addOnLabel.stringValue = extra.count ? [@"Emu_Imager comes with the editor and stays. Also installed: " stringByAppendingString:[extra componentsJoinedByString:@", "]]
                                          : @"Emu_Imager comes with the editor and stays. No other Add Ons are installed.";
    _removeAddOns.enabled = extra.count > 0;
}
- (void)windowDidBecomeKey:(NSNotification *)n { [self refresh]; }   // an Add On may have been installed meanwhile

// MARK: Add Ons
- (NSArray<NSURL *> *)removableAddOns { return [EDAddOns removableApps:[EDAddOns appsInFolder:EDAddOns.folder]]; }
- (NSArray<NSString *> *)addOnNames:(NSArray<NSURL *> *)apps {
    NSMutableArray<NSString *> *names = [NSMutableArray array]; for (NSURL *u in apps) [names addObject:[EDAddOns titleFor:u]]; return names;
}
- (BOOL)isRunning:(NSURL *)app {
    NSString *path = app.path.stringByResolvingSymlinksInPath;
    for (NSRunningApplication *r in NSWorkspace.sharedWorkspace.runningApplications) if ([r.bundleURL.path.stringByResolvingSymlinksInPath isEqualToString:path]) return YES;
    return NO;
}
- (void)removeAddOns:(id)sender {
    NSArray<NSURL *> *apps = [self removableAddOns]; NSArray<NSString *> *names = [self addOnNames:apps];
    if (!apps.count) { [self refresh]; return; }
    EDAlert *a = [EDAlert new];
    a.messageText = apps.count == 1 ? @"Remove this Add On?" : [NSString stringWithFormat:@"Remove %lu Add Ons?", (unsigned long)apps.count];
    a.informativeText = [NSString stringWithFormat:@"%@\n\nMoved to the Trash. Emu_Imager stays.", [names componentsJoinedByString:@"\n"]];
    [a addButtonWithTitle:@"Remove"]; [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    for (NSURL *u in apps) {
        NSError *e = nil;
        if ([self isRunning:u]) [failed addObject:[NSString stringWithFormat:@"%@ is running. Quit it first.", [EDAddOns titleFor:u]]];
        else if (![NSFileManager.defaultManager trashItemAtURL:u resultingItemURL:nil error:&e]) [failed addObject:[NSString stringWithFormat:@"%@: %@", [EDAddOns titleFor:u], e.localizedDescription]];
    }
    [self refresh];
    if (failed.count) [EDTheme notice:[@"Not removed:\n" stringByAppendingString:[failed componentsJoinedByString:@"\n"]]];
}

- (void)chooseFolder:(NSButton *)b {
    NSArray<NSString *> *k = FolderKinds()[b.tag];
    NSOpenPanel *p = [NSOpenPanel openPanel]; p.canChooseFiles = NO; p.canChooseDirectories = YES; p.canCreateDirectories = YES; p.prompt = @"Choose";
    p.message = [NSString stringWithFormat:@"Folder where the dialogs for %@ should start", k[0].lowercaseString];
    NSString *cur = [NSUserDefaults.standardUserDefaults stringForKey:k[2]] ?: [NSUserDefaults.standardUserDefaults stringForKey:k[1]];
    if (cur.length) p.directoryURL = [NSURL fileURLWithPath:cur isDirectory:YES];
    if ([p runModal] != NSModalResponseOK) return;
    [NSUserDefaults.standardUserDefaults setObject:p.URL.path forKey:k[2]]; [self refresh];
}
- (void)resetFolder:(NSButton *)b { [NSUserDefaults.standardUserDefaults removeObjectForKey:FolderKinds()[b.tag][2]]; [self refresh]; }
- (void)auditionChanged:(NSPopUpButton *)b { [NSUserDefaults.standardUserDefaults setInteger:b.selectedItem.tag forKey:@"AuditionKey"]; }
- (void)autoChanged:(NSButton *)b { [NSUserDefaults.standardUserDefaults setBool:b.state == NSControlStateValueOn forKey:@"AutoSaveToSampler"]; }
- (void)setDefaults:(id)sender {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    for (NSArray *k in FolderKinds()) { [d removeObjectForKey:k[1]]; [d removeObjectForKey:k[2]]; }
    for (NSString *k in @[@"AutoSaveToSampler", @"SkipConvertOffer", @"HideToolTips", @"AuditionKey"]) [d removeObjectForKey:k];
    [EDTheme setLcdHue:0];
    for (NSWindow *w in NSApp.windows) [w.contentView ed_applyToolTips];
    [self refresh];
}
- (void)tipsChanged:(NSButton *)b {
    [NSUserDefaults.standardUserDefaults setBool:b.state != NSControlStateValueOn forKey:@"HideToolTips"];
    for (NSWindow *w in NSApp.windows) [w.contentView ed_applyToolTips];
}
- (void)offerChanged:(NSButton *)b { [NSUserDefaults.standardUserDefaults setBool:b.state != NSControlStateValueOn forKey:@"SkipConvertOffer"]; }
@end
