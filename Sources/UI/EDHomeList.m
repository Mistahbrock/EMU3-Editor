#import "EDHomeList.h"
#import "EDTheme.h"

@implementation EDHomeList { NSMutableArray<NSDictionary *> *_rows; }
@synthesize table = _table;

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _rows = [NSMutableArray array];
    _table = [NSTableView new]; _table.dataSource = self; _table.delegate = self; _table.rowHeight = 40; _table.headerView = nil;
    _table.doubleAction = @selector(openClicked:); _table.target = self;
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:@"c"]; c.resizingMask = NSTableColumnAutoresizingMask; [_table addTableColumn:c];
    _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    [EDTheme styleLCDTable:_table];
    return self;
}
/// A bank is an EOS IFF file ("FORM", a length, "E4B0") or an Emulator 3X / ESI-32 bank ("EMULATOR 3X" header).
+ (BOOL)isBankFile:(NSURL *)u {
    NSFileHandle *h = [NSFileHandle fileHandleForReadingFromURL:u error:nil]; if (!h) return NO;
    NSData *d = [h readDataUpToLength:16 error:nil]; [h closeFile];
    if (d.length < 12) return NO;
    return (!memcmp(d.bytes, "FORM", 4) && !memcmp((const char *)d.bytes + 8, "E4B", 3)) || !memcmp(d.bytes, "EMULATOR 3X", 11);
}
+ (void)noteRecent:(NSURL *)url {
    NSMutableArray *r = [([NSUserDefaults.standardUserDefaults arrayForKey:@"RecentBanks"] ?: @[]) mutableCopy];
    [r removeObject:url.path]; [r insertObject:url.path atIndex:0]; while (r.count > 12) [r removeLastObject];
    [NSUserDefaults.standardUserDefaults setObject:r forKey:@"RecentBanks"];
}
- (void)reloadWithSamplerDisk:(NSURL *)disk {
    [_rows removeAllObjects];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableSet *seen = [NSMutableSet set];
    if (disk) {
        NSMutableArray *dirs = [NSMutableArray arrayWithObject:disk];
        if ([disk.lastPathComponent isEqual:@"Default Folder"]) [dirs addObject:disk.URLByDeletingLastPathComponent];
        for (NSURL *d in dirs) {
            NSArray *items = [fm contentsOfDirectoryAtURL:d includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
            for (NSURL *u in [items sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent]; }]) {
                NSNumber *isDir = nil, *size = nil; [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil]; [u getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                if (isDir.boolValue || size.unsignedLongLongValue < 4096 || ![EDHomeList isBankFile:u]) continue;
                [seen addObject:u.path];
                [_rows addObject:@{@"title": u.lastPathComponent, @"detail": [NSString stringWithFormat:@"On the sampler disk · %@", [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]], @"url": u}];
            }
        }
    }
    for (NSString *p in [NSUserDefaults.standardUserDefaults arrayForKey:@"RecentBanks"]) {
        if ([seen containsObject:p] || ![fm fileExistsAtPath:p]) continue;
        [_rows addObject:@{@"title": p.lastPathComponent, @"detail": [@"Recent · " stringByAppendingString:p.stringByDeletingLastPathComponent.stringByAbbreviatingWithTildeInPath], @"url": [NSURL fileURLWithPath:p]}];
    }
    [_table reloadData];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)_rows.count; }
- (NSTableRowView *)tableView:(NSTableView *)t rowViewForRow:(NSInteger)r { return [EDTheme lcdRowView]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSTableCellView *v = [t makeViewWithIdentifier:@"home" owner:self];
    if (!v) {
        v = [NSTableCellView new]; v.identifier = @"home";
        NSTextField *a = [NSTextField labelWithString:@""], *b = [NSTextField labelWithString:@""];
        [EDTheme styleLCDText:a]; b.font = [NSFont systemFontOfSize:11]; b.textColor = [EDTheme.lcdInk colorWithAlphaComponent:0.7];
        a.lineBreakMode = b.lineBreakMode = NSLineBreakByTruncatingMiddle;
        NSStackView *s = [NSStackView stackViewWithViews:@[a, b]]; s.orientation = NSUserInterfaceLayoutOrientationVertical; s.alignment = NSLayoutAttributeLeading; s.spacing = 2;
        s.translatesAutoresizingMaskIntoConstraints = NO; [v addSubview:s]; v.textField = a; v.objectValue = b;
        [NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:8], [s.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-8], [s.centerYAnchor constraintEqualToAnchor:v.centerYAnchor]]];
    }
    NSDictionary *row = _rows[r]; v.textField.stringValue = row[@"title"]; [(NSTextField *)v.objectValue setStringValue:row[@"detail"]];
    return v;
}
- (void)openClicked:(id)s { NSInteger r = _table.clickedRow; if (r >= 0 && r < (NSInteger)_rows.count && self.onOpen) self.onOpen(_rows[r][@"url"]); }
@end
