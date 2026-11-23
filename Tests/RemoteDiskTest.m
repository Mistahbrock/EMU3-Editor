// RemoteDiskTest — opens the sampler's internal drive (SCSI ID given, default 0) through the BlueSCSI passthrough, lists the folders and
// banks and reads one bank over SCSI. READ-ONLY. Run with emu3linkd stopped (kill -STOP). Usage: RemoteDiskTest [id]
#import <Foundation/Foundation.h>
#import "EDRemoteDisk.h"
#import "EDBank.h"
#import "EMU3Filesystem.h"
#import "EMU3Directory.h"
#import "EMU3File.h"
static void walk(EMU3Directory *d, int depth, NSMutableArray *banks) {
    static NSCountedSet *types; if (!types) types = [NSCountedSet new];
    for (EMU3File *f in d.files) { [types addObject:@(f.rawType)]; if (!f.isDeleted && f.fileType == EMU3FileTypeBank) [banks addObject:f]; }
    if (depth == 0) { for (NSNumber *t in types) printf("rawType 0x%02X: %lu files\n", t.intValue, (unsigned long)[types countForObject:t]); }
    for (EMU3Directory *s in d.subdirectories) { printf("%*s[%s] %lu files\n", depth * 2, "", s.name.UTF8String, (unsigned long)s.files.count); walk(s, depth + 1, banks); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    int tid = argc > 1 ? atoi(argv[1]) : 0;
    EDSMDIBoard *b = [EDSMDIBoard new]; NSError *e = nil;
    if (![b openPath:EDSMDIBoard.defaultPort error:&e]) { printf("board: %s\n", e.description.UTF8String); return 1; }
    NSURL *cache = [NSURL fileURLWithPath:@"/tmp/emu3-remote-test.hda"];
    EDRemoteDisk *d = [[EDRemoteDisk alloc] initWithExec:b.executor target:tid cacheURL:cache];
    d.onStatus = ^(NSString *t) { printf("\r%s", t.UTF8String); fflush(stdout); };
    NSDate *t0 = [NSDate date];
    if (![d prepareWithError:&e]) { printf("\nprepare failed: %s\n", e.localizedDescription.UTF8String); return 1; }
    printf("\nprepared %s: %lu blocks, metadata in %.1fs\n", d.product.UTF8String, (unsigned long)d.totalBlocks, -[t0 timeIntervalSinceNow]);
    [EMU3Filesystem setRemoteFetcher:^BOOL(NSUInteger f, NSUInteger n) { return [d ensureBlocks:f count:n]; } forImageURL:cache];
    EMU3Filesystem *fs = [[EMU3Filesystem alloc] initWithURL:cache error:&e];
    if (!fs) { printf("fs: %s\n", e.localizedDescription.UTF8String); return 1; }
    printf("file system: %lu blocks, read-only=%d\n", (unsigned long)fs.totalBlocks, fs.isReadOnly);
    NSMutableArray *banks = [NSMutableArray array]; walk(fs.rootDirectory, 0, banks);
    { NSMutableArray *dummy = [NSMutableArray array]; for (EMU3Directory *sd in fs.rootDirectory.subdirectories) for (EMU3File *f in sd.files) if (dummy.count < 4) { [dummy addObject:f]; printf("  %s type=0x%02X size=%lu deleted=%d\n", f.name.UTF8String, f.rawType, (unsigned long)f.fileSize, f.isDeleted); } }
    printf("%lu banks in total\n", (unsigned long)banks.count);
    EMU3File *pick = nil; for (EMU3File *f in banks) if (f.fileSize > 0 && (!pick || f.fileSize < pick.fileSize)) pick = f;
    if (pick) {
        printf("reading the smallest bank: %s (%lu bytes)\n", pick.name.UTF8String, (unsigned long)pick.fileSize);
        t0 = [NSDate date]; NSData *data = [fs dataForFile:pick error:&e];
        printf("\nread %lu bytes in %.1fs: %s\n", (unsigned long)data.length, -[t0 timeIntervalSinceNow], data ? "ok" : e.localizedDescription.UTF8String);
        if (data) { EDBank *bank = [EDBank bankWithData:data error:&e]; printf("parsed as bank: %s (%lu samples, %lu presets)\n", bank ? "yes" : e.localizedDescription.UTF8String, (unsigned long)bank.samples.count, (unsigned long)bank.presets.count); }
    }
    [b close]; [NSFileManager.defaultManager removeItemAtURL:cache error:nil]; return 0; } }
