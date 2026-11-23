#import "EDRemoteDisk.h"
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>

static const NSUInteger kChunk = 32;     // blocks per SCSI READ: the board's passthrough moves at most 16 kB per command

@implementation EDRemoteDisk {
    EDSMDIExec _exec; int _fd; NSMutableData *_have; NSLock *_lock; volatile BOOL _cancelled; dispatch_queue_t _q;
}
- (instancetype)initWithExec:(EDSMDIExec)exec target:(uint8_t)target cacheURL:(NSURL *)cacheURL {
    if ((self = [super init])) { _exec = [exec copy]; _target = target; _cacheURL = cacheURL; _fd = -1; _lock = [NSLock new]; _q = dispatch_queue_create("EDRemoteDisk", DISPATCH_QUEUE_SERIAL); _product = @""; }
    return self;
}
- (void)dealloc { if (_fd >= 0) close(_fd); }
- (void)cancel { _cancelled = YES; }
static NSError *Err(NSString *m) { return [NSError errorWithDomain:@"EDRemoteDisk" code:1 userInfo:@{NSLocalizedDescriptionKey: m}]; }

- (EDSMDIResult *)run:(const uint8_t *)cdb len:(NSUInteger)len inLen:(uint32_t)inLen {
    NSError *e = nil; return _exec(_target, [NSData dataWithBytes:cdb length:len], nil, inLen, &e);
}
- (BOOL)prepareWithError:(NSError **)error {
    _cancelled = NO;
    // INQUIRY
    uint8_t inq[] = {0x12, 0, 0, 0, 36, 0}; EDSMDIResult *r = [self run:inq len:6 inLen:36];
    if (!r || r.result != 0 || r.data.length < 36) { if (error) *error = Err([NSString stringWithFormat:@"Nothing answers at SCSI ID %d.", _target]); return NO; }
    const uint8_t *d = r.data.bytes;
    if ((d[0] & 0x1F) != 0 && (d[0] & 0x1F) != 5) { if (error) *error = Err([NSString stringWithFormat:@"The device at ID %d is not a disk.", _target]); return NO; }
    _product = [[NSString stringWithFormat:@"%@ %@ %@", [[NSString alloc] initWithBytes:d + 8 length:8 encoding:NSASCIIStringEncoding], [[NSString alloc] initWithBytes:d + 16 length:16 encoding:NSASCIIStringEncoding], [[NSString alloc] initWithBytes:d + 32 length:4 encoding:NSASCIIStringEncoding]] stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    // TEST UNIT READY (a unit attention after a bus reset is cleared by the first retry), then READ CAPACITY
    uint8_t tur[6] = {0}; for (int i = 0; i < 3; i++) { r = [self run:tur len:6 inLen:0]; if (r && r.result == 0 && r.status == 0) break; }
    uint8_t cap[10] = {0x25}; r = [self run:cap len:10 inLen:8];
    if (!r || r.result != 0 || r.status != 0 || r.data.length < 8) { if (error) *error = Err(@"READ CAPACITY failed."); return NO; }
    const uint8_t *c = r.data.bytes; uint32_t last = (c[0] << 24) | (c[1] << 16) | (c[2] << 8) | c[3], bs = (c[4] << 24) | (c[5] << 16) | (c[6] << 8) | c[7];
    if (bs != 512) { if (error) *error = Err([NSString stringWithFormat:@"The drive uses %u-byte blocks; only 512 is supported.", bs]); return NO; }
    _totalBlocks = (NSUInteger)last + 1;
    // the sparse cache file: as big as the drive, but only the blocks that were read take up space
    [NSFileManager.defaultManager createDirectoryAtURL:_cacheURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtURL:_cacheURL error:nil];
    _fd = open(_cacheURL.fileSystemRepresentation, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (_fd < 0 || ftruncate(_fd, (off_t)_totalBlocks * 512) != 0) { if (error) *error = Err(@"Could not create the cache file."); return NO; }
    _have = [NSMutableData dataWithLength:(_totalBlocks + kChunk - 1) / kChunk];
    // block 0: the EOS header; everything before the data area (header, allocation table, root directory, folder pool) is the directory structure
    if (![self fetch:0 count:1]) { if (error) *error = Err(@"Could not read block 0."); return NO; }
    uint8_t blk0[512]; pread(_fd, blk0, 512, 0);
    if (memcmp(blk0, "EMU3", 4) != 0) { if (error) *error = Err(@"The drive does not carry an E-MU (EOS) file system."); return NO; }
    uint32_t dataArea; memcpy(&dataArea, blk0 + 0x20, 4); dataArea = CFSwapInt32LittleToHost(dataArea);
    if (dataArea < 8 || dataArea > 200000 || dataArea >= _totalBlocks) { if (error) *error = Err(@"Unexpected EOS header."); return NO; }
    if (![self fetch:0 count:dataArea]) { if (error) *error = Err(_cancelled ? @"Cancelled." : @"Could not read the directory area of the drive."); return NO; }
    return YES;
}
// serial, blocking: reads [first, first+count) that are not in the cache yet
- (BOOL)fetch:(NSUInteger)first count:(NSUInteger)count {
    if (count == 0) return YES; if (first + count > _totalBlocks) count = _totalBlocks - first; if (_fd < 0) return NO;
    [_lock lock]; BOOL ok = YES;
    NSUInteger c0 = first / kChunk, c1 = (first + count - 1) / kChunk, todo = 0;
    uint8_t *have = _have.mutableBytes; for (NSUInteger c = c0; c <= c1; c++) if (!have[c]) todo++;
    NSUInteger done = 0;
    for (NSUInteger c = c0; c <= c1 && ok; c++) {
        if (have[c]) continue;
        if (_cancelled) { ok = NO; break; }
        NSUInteger lba = c * kChunk, n = MIN(kChunk, _totalBlocks - lba); BOOL got = NO;
        for (int attempt = 0; attempt < 4 && !got; attempt++) {
            uint8_t cdb[10] = {0x28, 0, (uint8_t)(lba >> 24), (uint8_t)(lba >> 16), (uint8_t)(lba >> 8), (uint8_t)lba, 0, (uint8_t)(n >> 8), (uint8_t)n, 0};
            EDSMDIResult *r = [self run:cdb len:10 inLen:(uint32_t)(n * 512)];
            if (r && r.result == 0 && r.status == 0 && r.data.length == n * 512) { pwrite(_fd, r.data.bytes, n * 512, (off_t)lba * 512); have[c] = 1; got = YES; }
            else [NSThread sleepForTimeInterval:0.1];
        }
        if (!got) { ok = NO; break; }
        done++;
        if (self.onStatus && (done % 8 == 0 || done == todo)) self.onStatus([NSString stringWithFormat:@"Reading the drive at ID %d: %.1f of %.1f MB…", _target, done * kChunk * 512 / 1048576.0, todo * kChunk * 512 / 1048576.0]);
    }
    [_lock unlock]; return ok;
}
- (BOOL)ensureBlocks:(NSUInteger)first count:(NSUInteger)count {
    if (!NSThread.isMainThread) return [self fetch:first count:count];
    __block BOOL ok = NO, finished = NO;
    dispatch_async(_q, ^{ ok = [self fetch:first count:count]; finished = YES; CFRunLoopWakeUp(CFRunLoopGetMain()); });
    while (!finished) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return ok;
}
@end
