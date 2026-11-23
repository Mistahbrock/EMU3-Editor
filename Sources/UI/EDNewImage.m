#import "EDAlert.h"
#import "EDNewImage.h"
#import "EDTheme.h"
#import "EMU3Filesystem.h"
#import "EMU3Types.h"
#import <fcntl.h>
#import <unistd.h>

static NSDictionary *RunTool(NSString *path, NSArray<NSString *> *args, int *status) {
    NSTask *t = [[NSTask alloc] init]; t.executableURL = [NSURL fileURLWithPath:path]; t.arguments = args;
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = p;
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) { if (status) *status = -1; return @{@"out": e.localizedDescription ?: @""}; }
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    if (status) *status = t.terminationStatus;
    return @{@"data": d ?: [NSData data], @"out": [[NSString alloc] initWithData:d ?: [NSData data] encoding:NSUTF8StringEncoding] ?: @""};
}
static NSDictionary *DiskInfo(NSString *target) {
    int st = 0; NSDictionary *r = RunTool(@"/usr/sbin/diskutil", @[@"info", @"-plist", target], &st);
    if (st != 0 || ![r[@"data"] length]) return nil;
    return [NSPropertyListSerialization propertyListWithData:r[@"data"] options:0 format:NULL error:nil];
}
// YES when `url` lives on an SD card mounted through the BlueSCSI board's own USB port (USB full speed, about 1 MB/s).
static BOOL IsBoardUSBVolume(NSURL *url) {
    if (!url) return NO;
    NSURL *vol = nil; [url getResourceValue:&vol forKey:NSURLVolumeURLKey error:nil]; if (!vol) vol = url;
    NSDictionary *vi = DiskInfo(vol.path); NSString *whole = vi[@"ParentWholeDisk"];
    NSDictionary *di = whole ? DiskInfo([@"/dev/" stringByAppendingString:whole]) : nil;
    if (di && ![di[@"Internal"] boolValue])
        for (id v in di.allValues) if ([v isKindOfClass:NSString.class] && [(NSString *)v rangeOfString:@"bluescsi" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

@implementation EDNewImage {
    NSPopUpButton *_volume, *_unit, *_scsi; NSTextField *_size, *_name, *_info; NSButton *_format;
    NSArray<NSDictionary *> *_volumes; NSString *_autoName;
}

// Mounted local volumes (system disk and network shares left out).
- (NSArray<NSDictionary *> *)mountedVolumeInfos {
    NSArray *keys = @[NSURLVolumeNameKey, NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey, NSURLVolumeLocalizedFormatDescriptionKey,
                      NSURLVolumeIsInternalKey, NSURLVolumeIsLocalKey, NSURLVolumeIsRootFileSystemKey, NSURLVolumeIsRemovableKey];
    NSMutableArray *out = [NSMutableArray array];
    for (NSURL *u in [NSFileManager.defaultManager mountedVolumeURLsIncludingResourceValuesForKeys:keys options:NSVolumeEnumerationSkipHiddenVolumes]) {
        NSDictionary *v = [u resourceValuesForKeys:keys error:nil];
        if ([v[NSURLVolumeIsRootFileSystemKey] boolValue] || ![v[NSURLVolumeIsLocalKey] boolValue]) continue;
        if ([u.path hasPrefix:@"/System/"] || [u.path hasPrefix:@"/private/"]) continue;
        NSString *fmt = v[NSURLVolumeLocalizedFormatDescriptionKey] ?: @"?", *low = fmt.lowercaseString;
        BOOL fat32 = [low containsString:@"fat"] && ![low containsString:@"exfat"];
        [out addObject:@{@"url": u, @"name": v[NSURLVolumeNameKey] ?: u.lastPathComponent, @"format": fmt, @"fat32": @(fat32),
                         @"total": v[NSURLVolumeTotalCapacityKey] ?: @0, @"free": v[NSURLVolumeAvailableCapacityKey] ?: @0,
                         @"external": @(![v[NSURLVolumeIsInternalKey] boolValue] || [v[NSURLVolumeIsRemovableKey] boolValue])}];
    }
    return out;
}
- (NSString *)describeVolume:(NSDictionary *)v {
    unsigned long long total = [v[@"total"] unsignedLongLongValue], free = [v[@"free"] unsignedLongLongValue];
    NSMutableString *s = [NSMutableString stringWithFormat:@"%@: %@ total, %@ free (host volume: %@).", v[@"name"], EMU3FormatBytes(total), EMU3FormatBytes(free), v[@"format"]];
    if ([v[@"fat32"] boolValue]) [s appendString:@"\nFAT32 cannot hold files of 4 GB or more: erase the card as exFAT to use bigger images."];
    if (total > 0 && total < 1000ULL * 1000 * 1000) [s appendString:@"\nVery small card."];
    return s;
}
// The Disk Manager's work folder: first line of ~/Library/Application Support/EMU3/watch.txt (the login auto-mount agent watches it).
- (NSURL *)imagesFolder {
    NSString *txt = [NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/EMU3/watch.txt"] encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [txt componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (t.length) return [NSURL fileURLWithPath:t.stringByExpandingTildeInPath isDirectory:YES];
    }
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"EMU3 Images"] isDirectory:YES];
}
- (NSDictionary *)selectedVolume { NSInteger i = _volume.indexOfSelectedItem; return i >= 0 && i < (NSInteger)_volumes.count ? _volumes[i] : nil; }
- (double)unitBytes { return _unit.indexOfSelectedItem == 0 ? 1048576.0 : 1073741824.0; }   // MB / GB, binary like the sampler shows
- (NSString *)autoName { return [NSString stringWithFormat:@"HD%ld0_%g%@.hda", (long)_scsi.indexOfSelectedItem, _size.doubleValue, _unit.titleOfSelectedItem]; }
- (void)preset:(NSPopUpButton *)s {
    NSArray *parts = [s.titleOfSelectedItem componentsSeparatedByString:@" "];
    if (parts.count == 2) { _size.stringValue = parts[0]; [_unit selectItemAtIndex:[parts[1] isEqualToString:@"MB"] ? 0 : 1]; }
    [self changed:nil];
}
- (void)changed:(id)sender {
    if (sender == _volume && _volume.indexOfSelectedItem == (NSInteger)_volumes.count) {   // "Other folder…"
        NSOpenPanel *op = [NSOpenPanel openPanel]; op.canChooseDirectories = YES; op.canChooseFiles = NO; op.prompt = @"Choose";
        if ([op runModal] == NSModalResponseOK) {
            NSURL *u = op.URL; NSDictionary *vals = [u resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey, NSURLVolumeLocalizedFormatDescriptionKey] error:nil];
            NSMutableArray *vs = [_volumes mutableCopy];
            [vs addObject:@{@"url": u, @"name": u.lastPathComponent, @"format": vals[NSURLVolumeLocalizedFormatDescriptionKey] ?: @"?", @"fat32": @NO,
                            @"total": vals[NSURLVolumeTotalCapacityKey] ?: @0, @"free": vals[NSURLVolumeAvailableCapacityKey] ?: @0, @"external": @NO}];
            _volumes = vs;
            [_volume insertItemWithTitle:[@"Folder: " stringByAppendingString:u.lastPathComponent] atIndex:_volumes.count - 1];
            [_volume selectItemAtIndex:_volumes.count - 1];
        } else [_volume selectItemAtIndex:0];
    }
    NSDictionary *v = [self selectedVolume]; NSString *info = v ? [self describeVolume:v] : @""; double gb = _size.doubleValue;
    if (v && gb > 0) {
        unsigned long long need = (unsigned long long)(gb * [self unitBytes]), free = [v[@"free"] unsignedLongLongValue];
        info = [info stringByAppendingFormat:@"\nNew image: %@ with an EMU3 (EOS) file system, %@ the free space.", EMU3FormatBytes(need), need <= free ? @"fits in" : @"LARGER than"];
    }
    _info.stringValue = info;
    NSString *an = [self autoName];   // keep the name in step with SCSI ID and size, unless the user typed their own
    if (_name.stringValue.length == 0 || [_name.stringValue isEqualToString:_autoName]) _name.stringValue = an;
    _autoName = an;
}
static void Warn(NSString *title, NSString *text) {
    EDAlert *p = [EDAlert new]; p.alertStyle = NSAlertStyleWarning; p.messageText = title; p.informativeText = text; [p runModal];
}

+ (void)runWithStatus:(void (^)(NSString *))status completion:(void (^)(NSURL *))done { [[EDNewImage new] runWithStatus:status completion:done]; }

- (void)runWithStatus:(void (^)(NSString *))status completion:(void (^)(NSURL *))done {
    NSMutableArray *list = [NSMutableArray array]; NSArray *vols = [self mountedVolumeInfos];
    for (NSDictionary *v in vols) if ([v[@"external"] boolValue]) [list addObject:v];
    for (NSDictionary *v in vols) if (![v[@"external"] boolValue]) [list addObject:v];
    NSURL *imagesDir = [self imagesFolder];
    [NSFileManager.defaultManager createDirectoryAtURL:imagesDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *iv = [imagesDir resourceValuesForKeys:@[NSURLVolumeTotalCapacityKey, NSURLVolumeAvailableCapacityKey, NSURLVolumeLocalizedFormatDescriptionKey] error:nil];
    [list insertObject:@{@"url": imagesDir, @"name": imagesDir.lastPathComponent, @"format": iv[NSURLVolumeLocalizedFormatDescriptionKey] ?: @"?", @"fat32": @NO,
                         @"total": iv[NSURLVolumeTotalCapacityKey] ?: @0, @"free": iv[NSURLVolumeAvailableCapacityKey] ?: @0, @"external": @NO, @"isImagesFolder": @YES} atIndex:0];
    _volumes = list;

    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 232)];
    NSTextField *l1 = [NSTextField labelWithString:@"Create on:"]; l1.frame = NSMakeRect(0, 208, 90, 17);
    _volume = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(95, 204, 305, 26)];
    for (NSDictionary *v in list)
        [_volume addItemWithTitle:[v[@"isImagesFolder"] boolValue] ? [@"Folder: " stringByAppendingString:imagesDir.path.stringByAbbreviatingWithTildeInPath]
                                   : [NSString stringWithFormat:@"%@%@ (%@)", [v[@"external"] boolValue] ? @"" : @"Disk: ", v[@"name"], EMU3FormatBytes([v[@"total"] unsignedLongLongValue])]];
    [_volume addItemWithTitle:@"Other folder…"]; _volume.target = self; _volume.action = @selector(changed:);
    NSTextField *l2 = [NSTextField labelWithString:@"Size:"]; l2.frame = NSMakeRect(0, 172, 90, 17);
    _size = [NSTextField textFieldWithString:@"1"]; _size.frame = NSMakeRect(95, 168, 70, 24); _size.target = self; _size.action = @selector(changed:);
    _unit = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(168, 166, 62, 26)]; [_unit addItemsWithTitles:@[@"MB", @"GB"]]; [_unit selectItemAtIndex:1]; _unit.target = self; _unit.action = @selector(changed:);
    NSPopUpButton *presets = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(238, 166, 110, 26) pullsDown:YES]; [presets addItemWithTitle:@"Presets"];
    // powers of two from 8 MB to 512 GB (the largest disk the E6400 / EOS 4.62 addresses), plus 14 GB
    for (NSString *g in @[@"8 MB", @"16 MB", @"32 MB", @"64 MB", @"128 MB", @"256 MB", @"512 MB", @"1 GB", @"2 GB", @"4 GB", @"8 GB", @"14 GB", @"16 GB", @"32 GB", @"64 GB", @"128 GB", @"256 GB", @"512 GB"]) [presets addItemWithTitle:g];
    presets.target = self; presets.action = @selector(preset:);
    NSTextField *l3 = [NSTextField labelWithString:@"SCSI ID:"]; l3.frame = NSMakeRect(0, 136, 90, 17);
    _scsi = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(95, 132, 70, 26)]; for (int i = 0; i <= 6; i++) [_scsi addItemWithTitle:[NSString stringWithFormat:@"%d", i]];
    [_scsi selectItemAtIndex:2]; _scsi.target = self; _scsi.action = @selector(changed:);
    NSTextField *l4 = [NSTextField labelWithString:@"Name:"]; l4.frame = NSMakeRect(180, 136, 45, 17);
    _name = [NSTextField textFieldWithString:@""]; _name.frame = NSMakeRect(228, 132, 172, 24); _name.placeholderString = @"HD20_1GB.hda";
    _format = [NSButton checkboxWithTitle:@"Format as an empty EOS disk after creating" target:nil action:nil]; _format.state = NSControlStateValueOn; _format.frame = NSMakeRect(0, 104, 400, 20);
    _info = [NSTextField wrappingLabelWithString:@""]; _info.frame = NSMakeRect(0, 0, 400, 96); _info.font = [NSFont systemFontOfSize:11]; _info.textColor = NSColor.secondaryLabelColor;
    for (NSView *v in @[l1, _volume, l2, _size, _unit, presets, l3, _scsi, l4, _name, _format, _info]) [acc addSubview:v];
    [self changed:nil];

    while (YES) {
        EDAlert *a = [EDAlert new]; a.messageText = @"Create a new disk image";
        a.informativeText = @"BlueSCSI takes the SCSI ID from the name: HD<ID>0_… (e.g. HD20_14GB.hda is SCSI ID 2).";
        a.accessoryView = acc; [a addButtonWithTitle:@"Create"]; [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        NSDictionary *v = [self selectedVolume]; NSString *problem = nil;
        if (!v) problem = @"Choose where to create the image.";
        unsigned long long bytes = (unsigned long long)(_size.doubleValue * [self unitBytes]) / 512 * 512;
        if (!problem && (bytes < 8ULL << 20 || bytes > 512ULL << 30)) problem = @"Choose a size between 8 MB and 512 GB (the sampler cannot address more).";
        if (!problem && [v[@"fat32"] boolValue] && bytes >= 4ULL * 1000 * 1000 * 1000)
            problem = [NSString stringWithFormat:@"%@ is formatted as FAT32, which cannot hold a file of %@. Erase the card as exFAT, or choose less than 4 GB.", v[@"name"], EMU3FormatBytes(bytes)];
        if (!problem && bytes > 64ULL * 1024 * 1024 && IsBoardUSBVolume(v[@"url"]))
            problem = @"This card is connected through the BlueSCSI's USB port (about 1 MB/s). Creating an image there would take hours. Eject the card, take it out of the BlueSCSI and use a card reader on the Mac.";
        if (problem) { Warn(@"Cannot create this image", problem); continue; }
        if (bytes > [v[@"free"] unsignedLongLongValue]) {
            EDAlert *p = [EDAlert new]; p.alertStyle = NSAlertStyleWarning; p.messageText = @"Create a sparse image?";
            p.informativeText = [NSString stringWithFormat:@"The image is %@ but only %@ is free on %@. It will be created as a sparse file that only takes space as data is written. The sampler or the app fails with a write error once the volume is full.",
                                 EMU3FormatBytes(bytes), EMU3FormatBytes([v[@"free"] unsignedLongLongValue]), v[@"name"]];
            [p addButtonWithTitle:@"Create Sparse Image"]; [p addButtonWithTitle:@"Cancel"];
            if ([p runModal] != NSAlertFirstButtonReturn) continue;
        }
        NSString *fname = [[_name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        if (fname.length == 0) fname = [self autoName];
        NSString *ext = fname.pathExtension.lowercaseString;
        if (![ext isEqualToString:@"hda"] && ![ext isEqualToString:@"iso"]) fname = [fname stringByAppendingString:@".hda"];
        NSURL *dest = [(NSURL *)v[@"url"] URLByAppendingPathComponent:fname];
        if ([NSFileManager.defaultManager fileExistsAtPath:dest.path]) { Warn(@"A file with this name already exists", [NSString stringWithFormat:@"%@ is already on %@. Choose another name.", fname, v[@"name"]]); continue; }
        [self createAt:dest bytes:bytes format:_format.state == NSControlStateValueOn status:status completion:done];
        return;
    }
}

- (void)createAt:(NSURL *)dest bytes:(unsigned long long)bytes format:(BOOL)doFormat status:(void (^)(NSString *))status completion:(void (^)(NSURL *))done {
    status([NSString stringWithFormat:@"Creating %@ (%@)…", dest.lastPathComponent, EMU3FormatBytes(bytes)]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        if (doFormat) {
            NSError *e = nil;   // creates the sparse file, sizes it and writes the empty EOS file system
            if (![EMU3Filesystem createFormattedImageAtURL:dest sizeBytes:(NSUInteger)bytes error:&e]) err = [NSString stringWithFormat:@"Cannot create or format the image: %@", e.localizedDescription ?: @"unknown error"];
        } else {
            int fd = open(dest.fileSystemRepresentation, O_RDWR | O_CREAT | O_EXCL, 0644);
            if (fd < 0) err = [NSString stringWithFormat:@"Cannot create the file: %s", strerror(errno)];
            else { if (ftruncate(fd, (off_t)bytes) != 0) err = [NSString stringWithFormat:@"Cannot size the file: %s", strerror(errno)]; close(fd); }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err) { if ([err hasPrefix:@"Cannot"]) unlink(dest.fileSystemRepresentation); status(@"Image creation failed."); Warn(@"Image creation failed", err); return; }
            status([NSString stringWithFormat:@"Created %@ (%@).", dest.lastPathComponent, EMU3FormatBytes(bytes)]);
            done(dest);
        });
    });
}
@end
