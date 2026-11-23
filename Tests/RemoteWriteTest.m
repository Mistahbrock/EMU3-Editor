// RemoteWriteTest — one reversible write to the sampler (EOS remote-editing draft #30): reads MASTER_TRANSPOSE (id 184), changes it by one
// semitone, reads it back, restores it and reads again. Usage: RemoteWriteTest "<port>" [deviceID]
#import <Foundation/Foundation.h>
#import "EDMIDIPort.h"
static NSString *hex(NSData *d) { NSMutableString *s = [NSMutableString string]; const uint8_t *b = d.bytes; for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02X ", b[i]]; return s; }
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc < 2) return 1;
    EDMIDIEndpointInfo *o = nil, *i = nil; for (EDMIDIEndpointInfo *e in EDMIDIPort.destinations) if ([e.name isEqual:@(argv[1])]) o = e; for (EDMIDIEndpointInfo *e in EDMIDIPort.sources) if ([e.name isEqual:@(argv[1])]) i = e;
    if (!o || !i) { printf("port not found\n"); return 1; }
    uint8_t dev = argc > 2 ? atoi(argv[2]) : 0;
    EDMIDIPort *p = [EDMIDIPort new]; if (![p connectSource:i destination:o error:nil]) { printf("connect failed\n"); return 1; }
    NSMutableArray *got = [NSMutableArray array]; p.onSysex = ^(NSData *m) { @synchronized (got) { [got addObject:m]; } printf("<- %s\n", hex(m).UTF8String); };
    void (^send)(NSData *, const char *) = ^(NSData *d, const char *w) { printf("-> %s(%s)\n", hex(d).UTF8String, w); [p sendSysex:d]; [p flush]; [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]]; };
    NSInteger (^readParam)(void) = ^NSInteger {
        @synchronized (got) { [got removeAllObjects]; }
        const uint8_t q[] = {0xF0, 0x18, 0x21, dev, 0x55, 0x02, 0x01, 0x38, 0x01, 0x7F, 0xF7}; send([NSData dataWithBytes:q length:sizeof q], "request MASTER_TRANSPOSE");
        @synchronized (got) { for (NSData *m in got) { const uint8_t *b = m.bytes; if (m.length >= 13 && b[5] == 0x01 && b[7] == 0x38 && b[8] == 0x01) { NSInteger v = b[9] | (b[10] << 7); if (v & 0x2000) v -= 0x4000; return v; } } }
        return -999; };
    void (^write)(NSInteger) = ^(NSInteger v) { uint16_t u = (uint16_t)(v & 0x3FFF);
        const uint8_t w[] = {0xF0, 0x18, 0x21, dev, 0x55, 0x01, 0x02, 0x38, 0x01, (uint8_t)(u & 0x7F), (uint8_t)(u >> 7), 0x7F, 0xF7}; send([NSData dataWithBytes:w length:sizeof w], "write MASTER_TRANSPOSE"); };
    NSInteger v0 = readParam(); printf("current transpose: %ld\n", (long)v0);
    if (v0 == -999) { printf("no reply, nothing written\n"); [p disconnect]; return 2; }
    NSInteger v1 = v0 >= 12 ? v0 - 1 : v0 + 1; write(v1); NSInteger r1 = readParam(); printf("after write (%ld): %ld  %s\n", (long)v1, (long)r1, r1 == v1 ? "OK" : "MISMATCH");
    write(v0); NSInteger r2 = readParam(); printf("restored (%ld): %ld  %s\n", (long)v0, (long)r2, r2 == v0 ? "OK" : "MISMATCH");
    [p disconnect]; return 0; } }
