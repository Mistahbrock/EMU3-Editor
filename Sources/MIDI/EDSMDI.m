#import "EDSMDI.h"
#import <termios.h>
#import <fcntl.h>
#import <poll.h>
#import <unistd.h>
#import <glob.h>
#import <signal.h>
#import <unistd.h>

NSString * const EDSMDIErrorDomain = @"EDSMDI";
static NSError *MErr(NSInteger code, NSString *m) { return [NSError errorWithDomain:EDSMDIErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: m}]; }

// SMDI message IDs (OpenSMDI smdi.h)
enum {
    kMasterIdentify = 0x00010000, kSlaveIdentify = 0x00010001, kReject = 0x00020000,
    kACK = 0x01000000, kNAK = 0x01010000, kWAIT = 0x01020000, kSendNext = 0x01030000, kEndOfProc = 0x01040000, kAbort = 0x01050000,
    kDataPacket = 0x01100000, kHeaderRequest = 0x01200000, kSampleHeader = 0x01210000, kBeginTransfer = 0x01220000,
    kTransferAck = 0x01220001, kSampleName = 0x01230000, kDeleteSample = 0x01240000
};
enum { kSMDIErrNoSample = 0x00200002, kSMDIErrOutOfRange = 0x00200000, kSMDIErrNoMemory = 0x00200004, kSMDIErrBits = 0x00200006 };

@implementation EDSMDIResult
@end

// MARK: - Board link

@implementation EDSMDIBoard {
    int _fd; uint8_t _tag; NSLock *_lock;
}
+ (NSArray<NSString *> *)availablePorts {
    glob_t g; NSMutableArray *a = [NSMutableArray array];
    if (glob("/dev/cu.usbmodem*", 0, NULL, &g) == 0) { for (size_t i = 0; i < g.gl_pathc; i++) [a addObject:@(g.gl_pathv[i])]; }
    globfree(&g); return [a sortedArrayUsingSelector:@selector(compare:)];
}
+ (NSString *)defaultPort {
    NSArray *p = [self availablePorts];
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"SMDIPort"];
    if (saved && [p containsObject:saved]) return saved;
    return p.count >= 2 ? p[1] : p.firstObject;     // the board shows two serial ports; the second carries the passthrough
}
+ (pid_t)suspendLinkHelper {
    NSTask *t = [NSTask new]; t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pgrep"]; t.arguments = @[@"-x", @"-u", @(getuid()).stringValue, @"emu3linkd"];
    NSPipe *p = [NSPipe pipe]; t.standardOutput = p; t.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![t launchAndReturnError:nil]) return 0;
    NSData *d = [p.fileHandleForReading readDataToEndOfFile]; [t waitUntilExit];
    pid_t pid = (pid_t)[[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] intValue];
    if (pid <= 1 || kill(pid, SIGSTOP) != 0) return 0;
    // safety net: if this process disappears while the helper is frozen, thaw it
    NSTask *w = [NSTask new]; w.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    w.arguments = @[@"-c", [NSString stringWithFormat:@"while kill -0 %d 2>/dev/null; do sleep 2; done; kill -CONT %d", getpid(), pid]];
    w.standardOutput = NSFileHandle.fileHandleWithNullDevice; w.standardError = NSFileHandle.fileHandleWithNullDevice;
    [w launchAndReturnError:nil];
    return pid;
}
+ (void)resumeLinkHelper:(pid_t)pid { if (pid > 1) kill(pid, SIGCONT); }
+ (NSString *)consolePortForPassthrough:(NSString *)pt {
    NSString *stem = [pt substringToIndex:pt.length - 1], *best = nil;
    for (NSString *p in [self availablePorts]) if ([p hasPrefix:stem] && p.length == pt.length && [p compare:pt] == NSOrderedAscending) best = p;   // sorted ascending: last lower one wins
    return best;
}
+ (NSString *)switchMode:(char)mode passthroughPort:(NSString *)port {
    NSString *console = [self consolePortForPassthrough:port]; if (!console) return nil;
    NSUInteger before = [self availablePorts].count;
    int fd = open(console.fileSystemRepresentation, O_RDWR | O_NOCTTY | O_NONBLOCK); if (fd < 0) return nil;
    struct termios t; tcgetattr(fd, &t); cfmakeraw(&t); t.c_cflag |= CS8 | CREAD | CLOCAL; tcsetattr(fd, TCSANOW, &t);
    ssize_t w = write(fd, &mode, 1); close(fd); if (w != 1) return nil;
    // the board reboots: its ports vanish, then come back
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:4];
    while ([self availablePorts].count >= before && [end timeIntervalSinceNow] > 0) [NSThread sleepForTimeInterval:0.2];
    end = [NSDate dateWithTimeIntervalSinceNow:15];
    while ([self availablePorts].count < MAX(before, 2) && [end timeIntervalSinceNow] > 0) [NSThread sleepForTimeInterval:0.2];
    [NSThread sleepForTimeInterval:1.0];            // let USB finish enumerating
    NSString *np = [self defaultPort];
    return np;
}
- (instancetype)init { if ((self = [super init])) { _fd = -1; _lock = [NSLock new]; } return self; }
- (void)dealloc { [self close]; }
- (void)close { if (_fd >= 0) { close(_fd); _fd = -1; } _path = nil; }

static void put32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v, v >> 8, v >> 16, v >> 24}; [d appendBytes:b length:4]; }

- (BOOL)writeAll:(NSData *)d timeout:(NSTimeInterval)t {
    const uint8_t *p = d.bytes; size_t left = d.length; NSDate *end = [NSDate dateWithTimeIntervalSinceNow:t];
    while (left) {
        struct pollfd pf = {_fd, POLLOUT, 0};
        if (poll(&pf, 1, 200) > 0) { ssize_t n = write(_fd, p, left); if (n > 0) { p += n; left -= n; } }
        if (end.timeIntervalSinceNow < 0) return NO;
    }
    return YES;
}
- (BOOL)readExact:(uint8_t *)p count:(size_t)n deadline:(NSDate *)end {
    while (n) {
        double ms = end.timeIntervalSinceNow * 1000; if (ms <= 0) return NO;
        struct pollfd pf = {_fd, POLLIN, 0};
        if (poll(&pf, 1, (int)MIN(ms, 200)) > 0) { ssize_t r = read(_fd, p, n); if (r > 0) { p += r; n -= r; } else if (r == 0) return NO; }
    }
    return YES;
}
- (void)drain { uint8_t junk[512]; struct pollfd pf = {_fd, POLLIN, 0}; while (poll(&pf, 1, 0) > 0 && read(_fd, junk, sizeof junk) > 0) {} }

/// Reads one 'X' 'S' 1 response frame (skipping stray bytes the CDC link may carry); nil on timeout.
- (EDSMDIResult *)readResponseUntil:(NSDate *)end {
    uint8_t m[3] = {0};
    if (![self readExact:m count:3 deadline:end]) return nil;
    while (!(m[0] == 'X' && m[1] == 'S' && m[2] == 1)) { m[0] = m[1]; m[1] = m[2]; if (![self readExact:m + 2 count:1 deadline:end]) return nil; }
    uint8_t r[13]; if (![self readExact:r count:13 deadline:end]) return nil;
    EDSMDIResult *res = [EDSMDIResult new]; res.result = r[2]; res.status = r[3];
    uint8_t senseLen = r[4]; uint32_t dl = r[5] | (r[6] << 8) | (r[7] << 16) | ((uint32_t)r[8] << 24);
    _ownID = r[9];
    NSMutableData *sense = [NSMutableData dataWithLength:senseLen], *data = [NSMutableData dataWithLength:dl];
    if (senseLen && ![self readExact:sense.mutableBytes count:senseLen deadline:end]) return nil;
    if (dl && ![self readExact:data.mutableBytes count:dl deadline:end]) return nil;
    res.sense = sense; res.data = data; return res;
}

/// One frame exchange. op 1 = SCSI command, op 2 = board info.
- (EDSMDIResult *)call:(uint8_t)op target:(uint8_t)target cdb:(NSData *)cdb out:(NSData *)out inLen:(uint32_t)inLen flags:(uint8_t)flags
               timeout:(NSTimeInterval)timeout error:(NSError **)error {
    [_lock lock];
    @try {
        if (_fd < 0) { if (error) *error = MErr(EDSMDIErrorTransport, @"The BlueSCSI board is not connected."); return nil; }
        [self drain];
        uint8_t tag = ++_tag;
        NSMutableData *f = [NSMutableData data];
        uint8_t h[8] = {'S', 'X', 1, op, tag, target, (uint8_t)cdb.length, flags};
        [f appendBytes:h length:8]; put32(f, (uint32_t)out.length); put32(f, inLen); put32(f, 10000);
        [f appendData:cdb]; if (out) [f appendData:out];
        if (![self writeAll:f timeout:5]) { if (error) *error = MErr(EDSMDIErrorTransport, @"Writing to the BlueSCSI board timed out."); return nil; }
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];
        EDSMDIResult *res = [self readResponseUntil:end];
        if (!res && error) *error = MErr(EDSMDIErrorTransport, @"The BlueSCSI board did not answer. Is it in initiator mode with the SMDI firmware, and is Disk Manager's link closed?");
        return res;
    } @finally { [_lock unlock]; }
}

- (BOOL)openPath:(NSString *)path error:(NSError **)error {
    [self close];
    int fd = open(path.fileSystemRepresentation, O_RDWR | O_NOCTTY | O_NONBLOCK);   // never block on a macOS serial open
    if (fd < 0) { if (error) *error = MErr(EDSMDIErrorTransport, [NSString stringWithFormat:@"Cannot open %@ (in use by another program?)", path]); return NO; }
    struct termios t; tcgetattr(fd, &t); cfmakeraw(&t); t.c_cflag |= CS8 | CREAD | CLOCAL; tcsetattr(fd, TCSANOW, &t);
    _fd = fd; _path = [path copy];
    for (int i = 0; i < 6; i++) {                    // the first frame after opening can be lost
        NSError *e = nil;
        EDSMDIResult *r = [self call:2 target:0 cdb:[NSData data] out:nil inLen:0 flags:0 timeout:1.5 error:&e];
        if (r) { [NSUserDefaults.standardUserDefaults setObject:path forKey:@"SMDIPort"]; return YES; }
    }
    [self close];
    if (error) *error = MErr(EDSMDIErrorTransport, @"The BlueSCSI board did not answer on that port. It must run the SMDI firmware in initiator mode. Quit EMU3 Disk Manager's sampler link if it holds the port.");
    return NO;
}
- (EDSMDIExec)executor {
    __weak EDSMDIBoard *w = self;
    return ^EDSMDIResult *(uint8_t target, NSData *cdb, NSData *out, uint32_t inLen, NSError **error) {
        EDSMDIBoard *b = w; if (!b) return nil;
        // flags: 1 = REQUEST SENSE on check condition, 8 = tolerate the EOS sampler's phase-line glitches
        return [b call:1 target:target cdb:cdb out:out inLen:inLen flags:9 timeout:20 error:error];
    };
}
@end

// MARK: - SMDI client

@implementation EDSMDIInfo
- (uint32_t)sampleRate { return _periodNs ? (uint32_t)llround(1e9 / _periodNs) : 0; }
@end

static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static uint32_t be24(const uint8_t *p) { return (p[0] << 16) | (p[1] << 8) | p[2]; }
static void putBE24(NSMutableData *d, uint32_t v) { uint8_t b[3] = {v >> 16, v >> 8, v}; [d appendBytes:b length:3]; }
static void putBE32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; [d appendBytes:b length:4]; }

@implementation EDSMDIClient {
    volatile BOOL _cancel; NSString *_timing; NSTimeInterval _msgTime; NSUInteger _msgCount;
}
- (instancetype)initWithExec:(EDSMDIExec)exec target:(uint8_t)target {
    if ((self = [super init])) { _exec = [exec copy]; _target = target; _timing = @""; }
    return self;
}
- (NSString *)timingSummary { return _timing; }
- (void)cancel { _cancel = YES; }

static uint32_t msgID(NSData *d) { return d.length >= 8 ? be32((const uint8_t *)d.bytes + 4) : 0; }
static NSData *Msg(uint32_t mid, NSData *body) {
    NSMutableData *m = [NSMutableData dataWithBytes:"SMDI" length:4];
    putBE32(m, mid); putBE24(m, (uint32_t)body.length); if (body) [m appendData:body];
    return m;
}

/// SEND one message, then RECEIVE the reply (retrying while the sampler is not ready, and while it answers WAIT).
- (NSData *)exchange:(uint32_t)mid body:(NSData *)body replyMax:(uint32_t)max error:(NSError **)error {
    NSDate *t0 = NSDate.date;
    NSData *m = Msg(mid, body);
    uint8_t len = (uint8_t)m.length; (void)len;
    uint8_t sc[6] = {0x0A, 0, (uint8_t)(m.length >> 16), (uint8_t)(m.length >> 8), (uint8_t)m.length, 0};
    EDSMDIResult *r = _exec(_target, [NSData dataWithBytes:sc length:6], m, 0, error);
    if (!r) return nil;
    if (r.result != 0 || r.status != 0) { if (error) *error = MErr(EDSMDIErrorTransport, r.result == 1 ? @"The sampler did not answer on that SCSI ID." : @"The sampler refused the SMDI message (SCSI error)."); return nil; }
    uint32_t cap = MAX(max, 64u);
    uint8_t rc[6] = {0x08, 0, (uint8_t)(cap >> 16), (uint8_t)(cap >> 8), (uint8_t)cap, 0};
    for (int tries = 0; tries < 600; tries++) {
        if (_cancel) { if (error) *error = MErr(EDSMDIErrorCancelled, @"Cancelled."); return nil; }
        r = _exec(_target, [NSData dataWithBytes:rc length:6], nil, cap, error);
        if (!r) return nil;
        if (r.result == 0 && r.status == 0 && r.data.length >= 11) {
            if (msgID(r.data) == kWAIT) { [NSThread sleepForTimeInterval:0.1]; continue; }
            _msgTime += -t0.timeIntervalSinceNow; _msgCount++;
            return r.data;
        }
        [NSThread sleepForTimeInterval:0.02];
    }
    if (error) *error = MErr(EDSMDIErrorTransport, @"The sampler sent no SMDI reply (timeout).");
    return nil;
}

static NSString *rejectText(NSData *d) {
    uint32_t code = d.length >= 15 ? be32((const uint8_t *)d.bytes + 11) : 0;
    switch (code) {
        case kSMDIErrNoSample: return @"There is no sample with that number on the sampler.";
        case kSMDIErrOutOfRange: return @"That sample number is out of range (SMDI cannot use sample 0).";
        case kSMDIErrNoMemory: return @"The sampler is out of sample memory.";
        case kSMDIErrBits: return @"The sampler does not support that bit depth.";
        default: return [NSString stringWithFormat:@"The sampler rejected the request (code %08X).", code];
    }
}

- (BOOL)masterIdentify:(NSError **)error {
    NSData *d = [self exchange:kMasterIdentify body:nil replyMax:64 error:error];
    if (!d) return NO;
    if (msgID(d) != kSlaveIdentify) { if (error) *error = MErr(EDSMDIErrorProtocol, @"The device answered, but not with an SMDI slave identification."); return NO; }
    return YES;
}

- (EDSMDIInfo *)infoForSample:(uint32_t)number error:(NSError **)error {
    NSMutableData *b = [NSMutableData data]; putBE24(b, number);
    NSData *d = [self exchange:kHeaderRequest body:b replyMax:256 error:error];
    if (!d) return nil;
    if (msgID(d) == kReject) {
        uint32_t code = d.length >= 15 ? be32((const uint8_t *)d.bytes + 11) : 0;
        if (error) *error = MErr(code == kSMDIErrNoSample ? EDSMDIErrorNoSample : EDSMDIErrorRejected, rejectText(d));
        return nil;
    }
    const uint8_t *p = d.bytes;
    if (msgID(d) != kSampleHeader || d.length < 37) { if (error) *error = MErr(EDSMDIErrorProtocol, @"Unexpected reply to a sample header request."); return nil; }
    EDSMDIInfo *i = [EDSMDIInfo new];
    i.number = number; i.bits = p[14]; i.channels = p[15]; i.periodNs = be24(p + 16); i.length = be32(p + 19);
    i.loopStart = be32(p + 23); i.loopEnd = be32(p + 27); i.loopControl = p[31]; i.pitch = (p[32] << 8) | p[33];
    NSUInteger nl = MIN((NSUInteger)p[36], d.length - 37);
    i.name = [[NSString alloc] initWithBytes:p + 37 length:nl encoding:NSISOLatin1StringEncoding] ?: @"";
    return i;
}

- (BOOL)deleteSample:(uint32_t)number error:(NSError **)error {
    NSMutableData *b = [NSMutableData data]; putBE24(b, number);
    NSData *d = [self exchange:kDeleteSample body:b replyMax:64 error:error];
    if (!d) return NO;
    if (msgID(d) == kReject) { if (error) *error = MErr(EDSMDIErrorRejected, rejectText(d)); return NO; }
    return YES;
}

- (void)abortQuietly { _cancel = NO; [self exchange:kAbort body:nil replyMax:64 error:nil]; }

- (BOOL)sendSample:(EDSDSSample *)s number:(uint32_t)number name:(NSString *)name
          progress:(void (^)(double, NSString *))progress error:(NSError **)error {
    _cancel = NO; _msgTime = 0; _msgCount = 0; NSDate *start = NSDate.date;
    uint32_t frames = (uint32_t)(s.frames.length / 2);
    if (!frames) { if (error) *error = MErr(EDSMDIErrorProtocol, @"The sample is empty."); return NO; }
    if (number < 1 || number > 999) { if (error) *error = MErr(EDSMDIErrorProtocol, (number == 0 ? @"Sample 0 (S000) is the sampler's clipboard and can't be used over SMDI. Pick a sample number from 1 to 999." : @"Pick a sample number from 1 to 999.")); return NO; }
    NSData *nm = [[name dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES] subdataWithRange:NSMakeRange(0, MIN(name.length, (NSUInteger)16))];
    NSMutableData *b = [NSMutableData data];
    putBE24(b, number);
    uint8_t bc[2] = {16, 1}; [b appendBytes:bc length:2];
    putBE24(b, (uint32_t)llround(1e9 / MAX(s.sampleRate, 1u)));
    uint32_t ls = s.loopEnabled ? s.loopStart : 0, le = s.loopEnabled ? s.loopEnd : frames - 1;   // the sampler hangs for a while on a loop end of 0
    putBE32(b, frames); putBE32(b, ls); putBE32(b, le);
    uint8_t lc = s.loopEnabled ? 0 : 127; [b appendBytes:&lc length:1];
    uint8_t pitch[4] = {0, 60, 0, 0}; [b appendBytes:pitch length:4];
    uint8_t nl = (uint8_t)nm.length; [b appendBytes:&nl length:1]; [b appendData:nm];
    if (progress) progress(0, @"Sending the sample header…");
    NSData *d = [self exchange:kSampleHeader body:b replyMax:64 error:error];
    if (!d) return NO;
    if (msgID(d) == kReject) { if (error) *error = MErr(EDSMDIErrorRejected, rejectText(d)); return NO; }
    if (msgID(d) != kTransferAck || d.length < 17) { if (error) *error = MErr(EDSMDIErrorProtocol, @"The sampler did not accept the sample header."); return NO; }
    uint32_t plen = be24((const uint8_t *)d.bytes + 14);
    if (plen < 2 || plen > 12000) plen = 512;
    plen &= ~1u;
    NSMutableData *bb = [NSMutableData data]; putBE24(bb, number); putBE24(bb, plen);
    d = [self exchange:kBeginTransfer body:bb replyMax:64 error:error];
    if (!d) return NO;
    if (msgID(d) == kReject) { if (error) *error = MErr(EDSMDIErrorRejected, rejectText(d)); return NO; }
    // sample data goes out as big-endian 16-bit words
    const int16_t *src = s.frames.bytes; NSUInteger total = frames * 2, pos = 0; uint32_t pn = 0;
    NSMutableData *pk = [NSMutableData dataWithCapacity:plen + 3];
    while (pos < total) {
        if (_cancel) { [self abortQuietly]; if (error) *error = MErr(EDSMDIErrorCancelled, @"Cancelled."); return NO; }
        NSUInteger n = MIN((NSUInteger)plen, total - pos);
        pk.length = 0; putBE24(pk, pn);
        for (NSUInteger i = 0; i < n; i += 2) { uint16_t w = (uint16_t)src[(pos + i) / 2]; uint8_t be[2] = {w >> 8, w}; [pk appendBytes:be length:2]; }
        d = [self exchange:kDataPacket body:pk replyMax:64 error:error];
        if (!d) { [self abortQuietly]; return NO; }
        uint32_t id = msgID(d);
        if (id == kReject || id == kNAK || id == kAbort) { if (error) *error = MErr(EDSMDIErrorRejected, id == kReject ? rejectText(d) : @"The sampler refused a data packet."); return NO; }
        pos += n; pn++;
        if (progress) progress((double)pos / total, [NSString stringWithFormat:@"Sending… packet %u (%u bytes each)", pn, plen]);
        if (id == kEndOfProc) break;
    }
    NSTimeInterval el = -start.timeIntervalSinceNow;
    _timing = [NSString stringWithFormat:@"%.1f s, %.1f KB/s, %.0f ms per SMDI message", el, total / 1024.0 / MAX(el, 0.001), _msgCount ? 1000 * _msgTime / _msgCount : 0];
    return YES;
}

- (EDSDSSample *)receiveSample:(uint32_t)number info:(EDSMDIInfo **)infoOut
                      progress:(void (^)(double, NSString *))progress error:(NSError **)error {
    _cancel = NO; _msgTime = 0; _msgCount = 0; NSDate *start = NSDate.date;
    if (progress) progress(0, @"Reading the sample header…");
    EDSMDIInfo *i = [self infoForSample:number error:error];
    if (!i) return nil;
    if (infoOut) *infoOut = i;
    if (i.bits != 16 || i.channels != 1) {
        if (error) *error = MErr(EDSMDIErrorProtocol, [NSString stringWithFormat:@"Sample %u is %u-bit with %u channel(s); only mono 16-bit samples can be received so far.", number, i.bits, i.channels]);
        return nil;
    }
    uint32_t plen = 4096;
    NSMutableData *bb = [NSMutableData data]; putBE24(bb, number); putBE24(bb, plen);
    NSData *d = [self exchange:kBeginTransfer body:bb replyMax:64 error:error];
    if (!d) return nil;
    if (msgID(d) == kReject) { if (error) *error = MErr(EDSMDIErrorRejected, rejectText(d)); return nil; }
    if (msgID(d) == kTransferAck && d.length >= 17) { uint32_t g = be24((const uint8_t *)d.bytes + 14); if (g >= 2 && g <= 12000) plen = g & ~1u; }
    NSUInteger total = (NSUInteger)i.length * 2, pos = 0; uint32_t pn = 0;
    NSMutableData *pcm = [NSMutableData dataWithLength:total];
    int16_t *dst = pcm.mutableBytes;
    while (pos < total) {
        if (_cancel) { [self abortQuietly]; if (error) *error = MErr(EDSMDIErrorCancelled, @"Cancelled."); return nil; }
        NSMutableData *rq = [NSMutableData data]; putBE24(rq, pn);
        d = [self exchange:kSendNext body:rq replyMax:plen + 14 error:error];
        if (!d) { [self abortQuietly]; return nil; }
        if (msgID(d) == kReject) { if (error) *error = MErr(EDSMDIErrorRejected, rejectText(d)); return nil; }
        if (msgID(d) != kDataPacket || d.length < 14) { if (error) *error = MErr(EDSMDIErrorProtocol, @"The sampler sent something other than a data packet."); [self abortQuietly]; return nil; }
        const uint8_t *p = d.bytes; NSUInteger n = MIN((NSUInteger)plen, total - pos); n = MIN(n, d.length - 14);
        for (NSUInteger k = 0; k + 2 <= n; k += 2) dst[(pos + k) / 2] = (int16_t)((p[14 + k] << 8) | p[14 + k + 1]);
        pos += n; pn++;
        if (n == 0) break;
        if (progress) progress((double)pos / total, [NSString stringWithFormat:@"Receiving… packet %u", pn]);
    }
    [self exchange:kEndOfProc body:nil replyMax:64 error:nil];
    EDSDSSample *s = [EDSDSSample new];
    s.number = (uint16_t)number; s.sampleRate = i.sampleRate; s.frames = pcm; s.bits = 16;
    s.loopEnabled = i.loopControl != 127 && i.loopEnd > i.loopStart; s.loopStart = i.loopStart; s.loopEnd = i.loopEnd;
    NSTimeInterval el = -start.timeIntervalSinceNow;
    _timing = [NSString stringWithFormat:@"%.1f s, %.1f KB/s", el, total / 1024.0 / MAX(el, 0.001)];
    return s;
}
@end
