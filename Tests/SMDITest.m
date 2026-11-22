// SMDI client against an in-memory fake sampler that speaks the same SEND/RECEIVE message protocol.
#import <Foundation/Foundation.h>
#import "EDSMDI.h"

static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } } while (0)

static uint32_t rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }
static uint32_t rd24(const uint8_t *p) { return (p[0] << 16) | (p[1] << 8) | p[2]; }
static void w32(NSMutableData *d, uint32_t v) { uint8_t b[4] = {v >> 24, v >> 16, v >> 8, v}; [d appendBytes:b length:4]; }
static void w24(NSMutableData *d, uint32_t v) { uint8_t b[3] = {v >> 16, v >> 8, v}; [d appendBytes:b length:3]; }
static NSData *msg(uint32_t id, NSData *body) { NSMutableData *m = [NSMutableData dataWithBytes:"SMDI" length:4]; w32(m, id); w24(m, (uint32_t)body.length); if (body) [m appendData:body]; return m; }

@interface FakeSampler : NSObject
@property NSMutableDictionary<NSNumber *, NSMutableDictionary *> *samples;
@property NSData *reply; @property int waits; @property NSUInteger packet;
@property NSMutableDictionary *incoming; @property uint32_t incomingNum, incomingLen;
@end
@implementation FakeSampler
- (instancetype)init { if ((self = [super init])) { _samples = [NSMutableDictionary dictionary]; _packet = 512; } return self; }
- (NSData *)rejectNoSample { NSMutableData *b = [NSMutableData data]; w32(b, 0x00200002); return msg(0x00020000, b); }
- (void)handle:(NSData *)m {
    const uint8_t *p = m.bytes; uint32_t id = rd32(p + 4); const uint8_t *b = p + 11;
    if (id == 0x00010000) _reply = msg(0x00010001, nil);
    else if (id == 0x01200000) {
        NSMutableDictionary *s = _samples[@(rd24(b))];
        if (!s) { _reply = [self rejectNoSample]; return; }
        NSMutableData *hb = [NSMutableData data]; w24(hb, rd24(b)); [hb appendData:s[@"header"]];
        _reply = msg(0x01210000, hb);
    } else if (id == 0x01210000) {
        _incomingNum = rd24(b); _incoming = [NSMutableDictionary dictionary];
        _incoming[@"header"] = [NSData dataWithBytes:b + 3 length:m.length - 11 - 3];
        _incoming[@"data"] = [NSMutableData data];
        const uint8_t *h = b + 3; _incomingLen = rd32(h + 5) * 2 * h[1];
        NSMutableData *a = [NSMutableData data]; w24(a, 0); w24(a, 0); // placeholder
        NSMutableData *ack = [NSMutableData data]; w24(ack, _incomingNum); w24(ack, (uint32_t)_packet);
        _reply = msg(0x01220001, ack);
    } else if (id == 0x01220000) {
        uint32_t num = rd24(b);
        if (_incoming) _reply = msg(0x01030000, ({ NSMutableData *x = [NSMutableData data]; w24(x, 0); x; }));
        else { _incomingNum = num; _reply = msg(0x01220001, ({ NSMutableData *x = [NSMutableData data]; w24(x, num); w24(x, (uint32_t)_packet); x; })); }
    } else if (id == 0x01100000) {
        NSMutableData *dat = _incoming[@"data"]; [dat appendBytes:b + 3 length:m.length - 11 - 3];
        if (dat.length >= _incomingLen) { _samples[@(_incomingNum)] = [_incoming mutableCopy]; _incoming = nil; _reply = msg(0x01040000, nil); }
        else _reply = msg(0x01030000, ({ NSMutableData *x = [NSMutableData data]; w24(x, rd24(b) + 1); x; }));
    } else if (id == 0x01030000) {
        NSMutableDictionary *s = _samples[@(_incomingNum)]; NSData *all = s[@"data"]; uint32_t pn = rd24(b);
        NSUInteger off = pn * _packet, n = off < all.length ? MIN(_packet, all.length - off) : 0;
        NSMutableData *body = [NSMutableData data]; w24(body, pn); [body appendData:[all subdataWithRange:NSMakeRange(off, n)]];
        _reply = msg(0x01100000, body);
    } else if (id == 0x01240000) { [_samples removeObjectForKey:@(rd24(b))]; _reply = msg(0x01000000, nil); }
    else if (id == 0x01050000 || id == 0x01040000) _reply = msg(0x01000000, nil);
    else _reply = msg(0x00020000, nil);
}
- (EDSMDIExec)exec {
    return ^EDSMDIResult *(uint8_t target, NSData *cdb, NSData *out, uint32_t inLen, NSError **error) {
        EDSMDIResult *r = [EDSMDIResult new]; r.sense = [NSData data]; r.data = [NSData data];
        const uint8_t *c = cdb.bytes;
        if (c[0] == 0x0A) { [self handle:out]; }
        else if (c[0] == 0x08) {
            if (self.waits-- > 0) { r.data = msg(0x01020000, nil); return r; }
            NSData *d = self.reply ?: [NSData data];
            r.data = d.length > inLen ? [d subdataWithRange:NSMakeRange(0, inLen)] : d;
        }
        return r;
    };
}
@end

int main(void) { @autoreleasepool {
    FakeSampler *fs = [FakeSampler new];
    EDSMDIClient *c = [[EDSMDIClient alloc] initWithExec:[fs exec] target:6];
    NSError *e = nil;
    CHECK([c masterIdentify:&e], "master identify");

    NSUInteger n = 3001;
    NSMutableData *d = [NSMutableData dataWithLength:n * 2]; int16_t *p = d.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) p[i] = (int16_t)(((int)i * 977) % 65536 - 32768);
    EDSDSSample *s = [EDSDSSample new]; s.number = 5; s.sampleRate = 44100; s.frames = d; s.loopEnabled = NO;

    fs.waits = 2;                                              // WAIT replies must be retried
    CHECK([c sendSample:s number:7 name:@"TEST TONE" progress:nil error:&e], e.localizedDescription.UTF8String ?: "send");
    EDSMDIInfo *i = [c infoForSample:7 error:&e];
    CHECK(i && i.length == n && i.bits == 16 && i.channels == 1 && llabs((long long)i.sampleRate - 44100) <= 1, "info after send");
    CHECK([i.name isEqual:@"TEST TONE"], "name");
    CHECK(i.loopControl == 127 && i.loopEnd == n - 1 && i.loopStart == 0, "no-loop header carries loop end = length-1");

    EDSMDIInfo *got = nil; EDSDSSample *r = [c receiveSample:7 info:&got progress:nil error:&e];
    CHECK(r && [r.frames isEqual:d], "round trip data");
    CHECK(r.sampleRate >= 44099 && r.sampleRate <= 44101, "round trip rate");

    CHECK([c infoForSample:8 error:&e] == nil && e.code == EDSMDIErrorNoSample, "empty slot reports NoSample");
    CHECK([c deleteSample:7 error:&e], "delete");
    CHECK([c infoForSample:7 error:&e] == nil, "deleted");

    s.loopEnabled = YES; s.loopStart = 100; s.loopEnd = 2000;
    CHECK([c sendSample:s number:9 name:@"LOOPED" progress:nil error:&e], "send looped");
    i = [c infoForSample:9 error:&e];
    CHECK(i && i.loopControl == 0 && i.loopStart == 100 && i.loopEnd == 2000, "loop points");
    CHECK(![c sendSample:s number:0 name:@"X" progress:nil error:&e], "sample 0 refused");
    printf(fails ? "SMDI tests FAILED (%d)\n" : "SMDI tests passed\n", fails);
    return fails ? 1 : 0;
}}
