// RemoteMultimode — reads the Multimode Map (73h → 72h) and, with "write", does ONE reversible change of a channel's volume
// via MULTIMODE_CHANNEL (246) + MULTIMODE_VOLUME (248), checks it in the map and restores it. Usage: RemoteMultimode "<port>" [write <ch 1-16> [pan]]  (volume by default; "pan" tests MULTIMODE_PAN 249 instead)
#import <Foundation/Foundation.h>
#import "EDMIDIPort.h"
static NSString *hex(NSData *d) { NSMutableString *s = [NSMutableString string]; const uint8_t *b = d.bytes; for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02X ", b[i]]; return s; }
static NSInteger S14(const uint8_t *b) { NSInteger v = b[0] | (b[1] << 7); return (v & 0x2000) ? v - 0x4000 : v; }
int main(int argc, const char **argv) { @autoreleasepool {
    EDMIDIEndpointInfo *o = nil, *i = nil; for (EDMIDIEndpointInfo *e in EDMIDIPort.destinations) if ([e.name isEqual:@(argv[1])]) o = e; for (EDMIDIEndpointInfo *e in EDMIDIPort.sources) if ([e.name isEqual:@(argv[1])]) i = e;
    if (!o || !i) return 1;
    EDMIDIPort *p = [EDMIDIPort new]; [p connectSource:i destination:o error:nil];
    NSMutableArray *got = [NSMutableArray array]; p.onSysex = ^(NSData *m) { @synchronized (got) { [got addObject:m]; } };
    void (^send)(NSData *) = ^(NSData *d) { printf("-> %s\n", hex(d).UTF8String); [p sendSysex:d]; [p flush]; [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]]; };
    NSArray *(^readMap)(void) = ^NSArray *{
        @synchronized (got) { [got removeAllObjects]; }
        const uint8_t q[] = {0xF0, 0x18, 0x21, 0x00, 0x55, 0x73, 0xF7}; send([NSData dataWithBytes:q length:sizeof q]);
        @synchronized (got) { for (NSData *m in got) { const uint8_t *b = m.bytes; if (m.length >= 7 + 128 && b[5] == 0x72) {
            NSMutableArray *a = [NSMutableArray array]; NSInteger n = (m.length - 7) / 8;
            for (NSInteger c = 0; c < n; c++) { const uint8_t *r = b + 6 + c * 8; [a addObject:@[@(S14(r)), @(S14(r + 2)), @(S14(r + 4)), @(S14(r + 6))]]; }
            printf("<- map dump, %lu bytes, %ld channels\n", (unsigned long)m.length, (long)n); return a; } } }
        printf("no map reply\n"); return nil; };
    NSArray *m0 = readMap(); if (!m0) return 2;
    for (NSInteger c = 0; c < (NSInteger)m0.count; c++) printf("ch%2ld  preset %4ld  vol %3ld  pan %3ld  submix %2ld\n", (long)c + 1, (long)[m0[c][0] integerValue], (long)[m0[c][1] integerValue], (long)[m0[c][2] integerValue], (long)[m0[c][3] integerValue]);
    if (argc > 3 && !strcmp(argv[2], "write")) {
        int ch = atoi(argv[3]); BOOL pan = argc > 4 && !strcmp(argv[4], "pan"), pre = argc > 4 && !strcmp(argv[4], "preset"); int col = pre ? 0 : (pan ? 2 : 1); NSInteger v0 = [m0[ch - 1][col] integerValue], v1 = pre ? v0 + 1 : pan ? v0 + 10 : (v0 >= 127 ? v0 - 1 : v0 + 1);
        void (^put)(NSInteger) = ^(NSInteger v) { const uint8_t w[] = {0xF0, 0x18, 0x21, 0x00, 0x55, 0x01, 0x04, 0x76, 0x01, (uint8_t)ch, 0x00, (uint8_t)(pre ? 0x77 : pan ? 0x79 : 0x78), 0x01, (uint8_t)(v & 0x7F), (uint8_t)((v & 0x3FFF) >> 7), 0x7F, 0xF7}; send([NSData dataWithBytes:w length:sizeof w]); };
        put(v1); NSArray *m1 = readMap();
        printf("after write: ch%d %s %ld (wanted %ld)\n", ch, pre ? "preset" : pan ? "pan" : "vol", (long)[m1[ch - 1][col] integerValue], (long)v1);
        for (NSInteger c = 0; c < (NSInteger)m0.count; c++) if (c != ch - 1 && ![m0[c] isEqual:m1[c]]) printf("  !! channel %ld changed too\n", (long)c + 1);
        put(v0); NSArray *m2 = readMap(); printf("restored: ch%d %s %ld (was %ld) %s\n", ch, pre ? "preset" : pan ? "pan" : "vol", (long)[m2[ch - 1][col] integerValue], (long)v0, [m2 isEqual:m0] ? "map identical to start" : "MAP DIFFERS");
    }
    [p disconnect]; return 0; } }
