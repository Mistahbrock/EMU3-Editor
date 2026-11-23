#import "EDAlert.h"
#import "EDBlueSCSIIni.h"
#import "EDTheme.h"

@interface EDLinkButton : NSButton
@end
@implementation EDLinkButton
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end

@interface EDBlueSCSIIni () <NSTextFieldDelegate>
@end

@implementation EDBlueSCSIIni {
    NSPopUpButton *_preset, *_id; NSTextField *_mb, *_preview, *_idLabel, *_mbLabel; NSButton *_noUSB, *_attention;
}
- (NSString *)text {
    BOOL bridge = _preset.indexOfSelectedItem == 1;
    int usb = _noUSB.state == NSControlStateValueOn ? 0 : 1, att = _attention.state == NSControlStateValueOn ? 1 : 0;
    if (bridge) return [NSString stringWithFormat:
        @"# bluescsi.ini for the USB-SCSI bridge firmware (written by EMU3 Editor).\n# Only needed when an SD card is in the board; without a card the Mac configures the board over USB.\n"
        @"[SCSI]\nUSBBlockDriveSCSIID=%ld\nUSBBlockDriveMB=%ld\nEnableUSBMassStorage=%d\nEnableUnitAttention=%d\n%@",
        (long)_id.indexOfSelectedItem, (long)MAX(1, _mb.integerValue), usb, att,
        [NSUserDefaults.standardUserDefaults objectForKey:@"HostID"] && [NSUserDefaults.standardUserDefaults integerForKey:@"HostID"] != 7 ? [NSString stringWithFormat:@"InitiatorID=%ld\n", (long)[NSUserDefaults.standardUserDefaults integerForKey:@"HostID"]] : @""];
    // stock BlueSCSI serving an image to an E-mu sampler: SCSI-1, no parity, early SEL (the settings that worked on the E6400)
    return [NSString stringWithFormat:
        @"; BlueSCSI settings for an E-mu sampler (written by EMU3 Editor)\n[SCSI]\nEnableUSBMassStorage=%d\nEnableSCSI2=0\nEnableUnitAttention=%d\nEnableParity=0\nEnableSelLatch=1\nQuirks=0\n", usb, att];
}
- (void)update:(id)sender {
    BOOL bridge = _preset.indexOfSelectedItem == 1;
    if (sender == _preset) _attention.state = bridge ? NSControlStateValueOn : NSControlStateValueOff;   // the working E-mu setup has it off
    for (NSView *v in @[_id, _mb, _idLabel, _mbLabel]) v.hidden = !bridge;
    _preview.stringValue = [self text];
}
- (void)openDocs:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://bluescsi.com/docs/"]]; }
- (void)controlTextDidChange:(NSNotification *)n { _preview.stringValue = [self text]; }

+ (void)runWithImage:(NSURL *)imageURL status:(void (^)(NSString *))status { [[EDBlueSCSIIni new] runWithImage:imageURL status:status]; }

- (void)runWithImage:(NSURL *)imageURL status:(void (^)(NSString *))status {
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 250)];
    NSTextField *l0 = [NSTextField labelWithString:@"Settings for:"]; l0.frame = NSMakeRect(0, 224, 90, 17);
    _preset = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(95, 220, 345, 26)];
    [_preset addItemsWithTitles:@[@"SD card disk for the sampler (stock BlueSCSI)", @"USB bridge board (Sampler Link)"]]; _preset.target = self; _preset.action = @selector(update:);
    _idLabel = [NSTextField labelWithString:@"SCSI ID of the disk:"]; _idLabel.frame = NSMakeRect(0, 190, 130, 17);
    _id = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(135, 186, 70, 26)]; for (int i = 0; i < 8; i++) [_id addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
    [_id selectItemAtIndex:7]; _id.target = self; _id.action = @selector(update:);
    _mbLabel = [NSTextField labelWithString:@"Disk size in MB:"]; _mbLabel.frame = NSMakeRect(225, 190, 110, 17);
    unsigned long long sz = imageURL ? [[NSFileManager.defaultManager attributesOfItemAtPath:imageURL.path error:nil] fileSize] : 0;
    _mb = [NSTextField textFieldWithString:sz ? [NSString stringWithFormat:@"%llu", sz / (1024 * 1024)] : @"14336"]; _mb.frame = NSMakeRect(338, 187, 100, 24); _mb.delegate = self;
    _noUSB = [NSButton checkboxWithTitle:@"Do not show the SD card as a USB drive (recommended)" target:self action:@selector(update:)]; _noUSB.state = NSControlStateValueOn; _noUSB.frame = NSMakeRect(0, 156, 440, 20);
    _attention = [NSButton checkboxWithTitle:@"Tell the sampler when the disk changed (unit attention)" target:self action:@selector(update:)]; _attention.state = NSControlStateValueOff; _attention.frame = NSMakeRect(0, 132, 440, 20);
    _preview = [NSTextField wrappingLabelWithString:@""]; _preview.frame = NSMakeRect(0, 0, 440, 124); _preview.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular]; _preview.textColor = NSColor.secondaryLabelColor;
    for (NSView *v in @[l0, _preset, _idLabel, _id, _mbLabel, _mb, _noUSB, _attention, _preview]) [acc addSubview:v];
    EDLinkButton *doc = [[EDLinkButton alloc] initWithFrame:NSMakeRect(0, 0, 440, 17)];
    doc.bordered = NO; doc.alignment = NSTextAlignmentLeft; doc.target = self; doc.action = @selector(openDocs:);
    doc.attributedTitle = [[NSAttributedString alloc] initWithString:@"BlueSCSI documentation (all bluescsi.ini settings): bluescsi.com/docs"
        attributes:@{NSForegroundColorAttributeName: NSColor.linkColor, NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle), NSFontAttributeName: [NSFont systemFontOfSize:11]}];
    for (NSView *v in acc.subviews) v.frame = NSOffsetRect(v.frame, 0, 22);
    acc.frame = NSMakeRect(0, 0, 440, 272); [acc addSubview:doc];
    [self update:nil];

    EDAlert *a = [EDAlert new]; a.messageText = @"Write bluescsi.ini"; a.informativeText = @"Makes the settings file for a BlueSCSI SD card. The next step asks where to save it: the top folder of the card.";
    a.accessoryView = acc; [a addButtonWithTitle:@"Save…"]; [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSString *text = [self text];
    NSSavePanel *sp = [NSSavePanel savePanel]; sp.title = @"Write bluescsi.ini"; sp.nameFieldStringValue = @"bluescsi.ini"; sp.message = @"Save bluescsi.ini in the top folder of the BlueSCSI SD card."; sp.allowsOtherFileTypes = YES; sp.extensionHidden = NO;
    for (NSString *v in [NSFileManager.defaultManager contentsOfDirectoryAtPath:@"/Volumes" error:nil]) if ([v.lowercaseString isEqualToString:@"bluescsi"]) sp.directoryURL = [NSURL fileURLWithPath:@"/Volumes/BLUESCSI" isDirectory:YES];
    if (!sp.directoryURL) sp.directoryURL = [NSURL fileURLWithPath:@"/Volumes" isDirectory:YES];
    if ([sp runModal] != NSModalResponseOK) return;
    NSError *err = nil;
    if ([text writeToURL:sp.URL atomically:YES encoding:NSUTF8StringEncoding error:&err]) status([NSString stringWithFormat:@"Saved %@.", sp.URL.path]);
    else { status(@"Could not save bluescsi.ini."); [EDTheme notice:[NSString stringWithFormat:@"Could not save bluescsi.ini: %@", err.localizedDescription ?: @""]]; }
}
@end
