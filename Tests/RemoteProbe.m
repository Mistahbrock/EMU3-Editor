// RemoteProbe — read-only SysEx probe of the sampler (EOS remote-editing draft #30). Sends ONLY requests:
// Identity Request, Sample Memory Request (12h), Preset Memory Request (10h), Configuration Request (14h).
// Usage: RemoteProbe "<out port name>" "<in port name>"
#import <Foundation/Foundation.h>
#import "EDMIDIPort.h"
static NSString *hex(NSData *d) { NSMutableString *s = [NSMutableString string]; const uint8_t *b = d.bytes; for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02X ", b[i]]; return s; }
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc < 3) { printf("usage: RemoteProbe out in\n"); return 1; }
    EDMIDIEndpointInfo *o = nil, *i = nil;
    for (EDMIDIEndpointInfo *e in EDMIDIPort.destinations) if ([e.name isEqual:@(argv[1])]) o = e;
    for (EDMIDIEndpointInfo *e in EDMIDIPort.sources) if ([e.name isEqual:@(argv[2])]) i = e;
    if (!o || !i) { printf("port not found\n"); return 1; }
    EDMIDIPort *p = [EDMIDIPort new]; NSError *err = nil;
    if (![p connectSource:i destination:o error:&err]) { printf("connect failed %s\n", err.description.UTF8String); return 1; }
    p.onSysex = ^(NSData *m) { printf("<- %s\n", hex(m).UTF8String); };
    void (^send)(const uint8_t *, NSUInteger, const char *) = ^(const uint8_t *b, NSUInteger n, const char *what) {
        NSData *d = [NSData dataWithBytes:b length:n]; printf("-> %s (%s)\n", hex(d).UTF8String, what); [p sendSysex:d]; [p flush];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]]; };
    const uint8_t idr[] = {0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7}; send(idr, sizeof idr, "identity request, all devices");
    int dev = argc > 3 ? atoi(argv[3]) : 0;
    const uint8_t smr[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x12, 0xF7}; send(smr, sizeof smr, "sample memory request");
    const uint8_t pmr[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x10, 0xF7}; send(pmr, sizeof pmr, "preset memory request");
    const uint8_t cfr[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x14, 0xF7}; send(cfr, sizeof cfr, "configuration request");
    [p disconnect]; return 0; } }
