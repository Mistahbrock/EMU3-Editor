#import "EDSamplerRemote.h"
#import "EDMIDIPort.h"

@implementation EDSamplerStatus
- (BOOL)hasFXCard { return _options & 2; }
- (BOOL)hasMIDICard { return _options & 4; }
- (BOOL)has128Voices { return _options & 1; }
@end

static NSString *ModelName(int m) {
    switch (m) { case 0: return @"E4"; case 1: return @"E64"; case 2: return @"E4k"; case 3: return @"E64FX"; case 4: return @"E4XT"; case 5: return @"E4X"; case 6: return @"E6400"; case 7: return @"E4XT Ultra"; case 8: return @"E6400 Ultra"; }
    return [NSString stringWithFormat:@"model %d", m];
}
static NSInteger LE14(const uint8_t *b) { return b[0] | (b[1] << 7); }

@implementation EDSamplerRemote
// sends one request, returns the first reply whose bytes 5... start with `cmd` (E4 messages: F0 18 21 dd 55 cmd ...), or the identity reply when cmd < 0
static NSData *Ask(EDMIDIPort *p, NSData *req, NSInteger cmd, NSTimeInterval wait, NSMutableArray *sink, dispatch_semaphore_t sem) {
    [sink removeAllObjects]; [p sendSysex:req]; [p flush];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)));
    @synchronized (sink) { for (NSData *m in sink) { const uint8_t *b = m.bytes;
        if (cmd < 0 ? (m.length >= 15 && b[1] == 0x7E && b[3] == 0x06 && b[4] == 0x02 && b[5] == 0x18) : (m.length >= 7 && b[1] == 0x18 && b[2] == 0x21 && b[4] == 0x55 && b[5] == cmd)) return m; } }
    return nil;
}
+ (EDSamplerStatus *)probeOut:(EDMIDIEndpointInfo *)o in:(EDMIDIEndpointInfo *)i {
    EDMIDIPort *p = [EDMIDIPort new]; NSMutableArray *sink = [NSMutableArray array]; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    p.onSysex = ^(NSData *m) { @synchronized (sink) { [sink addObject:m]; } dispatch_semaphore_signal(sem); };
    if (![p connectSource:i destination:o error:nil]) return nil;
    static const uint8_t idr[] = {0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7};
    NSData *id = Ask(p, [NSData dataWithBytes:idr length:sizeof idr], -1, 0.7, sink, sem);
    EDSamplerStatus *st = nil;
    if (id) {
        const uint8_t *b = id.bytes;
        if (b[6] == 0x01 && b[7] == 0x04) {   // E-MU family code 01 04
            st = [EDSamplerStatus new]; st.deviceID = b[2]; st.model = ModelName(b[8]); st.outPort = o.name; st.inPort = i.name;
            st.version = [[NSString alloc] initWithBytes:b + 10 length:4 encoding:NSASCIIStringEncoding] ?: @"";
            uint8_t dev = b[2] & 0x7F;
            uint8_t q[7] = {0xF0, 0x18, 0x21, dev, 0x55, 0, 0xF7};
            q[5] = 0x12; NSData *m = Ask(p, [NSData dataWithBytes:q length:7], 0x13, 0.8, sink, sem);
            if (m.length >= 13) { const uint8_t *r = m.bytes; st.sampleTotalMB = LE14(r + 6); st.sampleFreeK = LE14(r + 8) * 10.0; }
            q[5] = 0x10; m = Ask(p, [NSData dataWithBytes:q length:7], 0x11, 0.8, sink, sem);
            if (m.length >= 13) { const uint8_t *r = m.bytes; st.presetTotalK = LE14(r + 6); st.presetFreeK = LE14(r + 8); }
            q[5] = 0x14; m = Ask(p, [NSData dataWithBytes:q length:7], 0x15, 0.8, sink, sem);
            if (m.length >= 10) { const uint8_t *r = m.bytes; st.options = r[6]; st.ramMB = LE14(r + 7); }
        }
    }
    [p disconnect]; return st;
}
+ (void)queryWithCompletion:(void (^)(EDSamplerStatus *))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults; EDSamplerStatus *st = nil;
        NSArray *outs = EDMIDIPort.destinations, *ins = EDMIDIPort.sources;
        NSString *ro = [d stringForKey:@"RemoteOut"], *ri = [d stringForKey:@"RemoteIn"];
        if (ro && ri) {   // the pair that answered last time
            EDMIDIEndpointInfo *o = nil, *i = nil; for (EDMIDIEndpointInfo *e in outs) if ([e.name isEqual:ro]) o = e; for (EDMIDIEndpointInfo *e in ins) if ([e.name isEqual:ri]) i = e;
            if (o && i) st = [self probeOut:o in:i];
        }
        for (EDMIDIEndpointInfo *o in outs) { if (st) break;   // same-named pairs first: a port's input and output belong to one cable
            for (EDMIDIEndpointInfo *i in ins) if ([o.name isEqual:i.name] && ![o.name hasPrefix:@"IAC"]) { st = [self probeOut:o in:i]; if (st) break; } }
        if (st) { [d setObject:st.outPort forKey:@"RemoteOut"]; [d setObject:st.inPort forKey:@"RemoteIn"]; [d setInteger:st.deviceID forKey:@"RemoteDevice"]; }
        dispatch_async(dispatch_get_main_queue(), ^{ done(st); });
    });
}

// MARK: Multimode Map

static EDMIDIPort *ConnectSaved(NSInteger *devOut) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults; NSString *ro = [d stringForKey:@"RemoteOut"], *ri = [d stringForKey:@"RemoteIn"]; if (!ro || !ri) return nil;
    EDMIDIEndpointInfo *o = nil, *i = nil; for (EDMIDIEndpointInfo *e in EDMIDIPort.destinations) if ([e.name isEqual:ro]) o = e; for (EDMIDIEndpointInfo *e in EDMIDIPort.sources) if ([e.name isEqual:ri]) i = e;
    if (!o || !i) return nil;
    EDMIDIPort *p = [EDMIDIPort new]; if (![p connectSource:i destination:o error:nil]) return nil;
    if (devOut) *devOut = [d objectForKey:@"RemoteDevice"] ? [d integerForKey:@"RemoteDevice"] : 0;
    return p;
}
+ (void)readMultimodeWithCompletion:(void (^)(NSArray<NSArray<NSNumber *> *> *))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger dev = 0; EDMIDIPort *p = ConnectSaved(&dev); NSArray *result = nil;
        if (p) {
            NSMutableArray *sink = [NSMutableArray array]; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            p.onSysex = ^(NSData *m) { @synchronized (sink) { [sink addObject:m]; } dispatch_semaphore_signal(sem); };
            uint8_t q[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x73, 0xF7};
            NSData *m = Ask(p, [NSData dataWithBytes:q length:sizeof q], 0x72, 1.5, sink, sem);
            if (m.length >= 7 + 8) {
                const uint8_t *b = m.bytes; NSInteger n = ((NSInteger)m.length - 7) / 8; NSMutableArray *a = [NSMutableArray array];
                for (NSInteger c = 0; c < n; c++) { const uint8_t *r = b + 6 + c * 8; NSMutableArray *row = [NSMutableArray array];
                    for (int k = 0; k < 4; k++) { NSInteger v = r[k * 2] | (r[k * 2 + 1] << 7); if (v & 0x2000) v -= 0x4000; [row addObject:@(v)]; } [a addObject:row]; }
                result = a;
            }
            [p disconnect];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(result); });
    });
}
static dispatch_queue_t sWriteQ; static NSMutableDictionary<NSNumber *, NSNumber *> *sPending; static BOOL sDraining;
// key = channel * 1000 + parameter id (248 volume, 249 pan)
static void QueueWrite(NSInteger channel, NSInteger param, NSInteger value) {
    if (channel < 1 || channel > 32) return;
    static dispatch_once_t once; dispatch_once(&once, ^{ sWriteQ = dispatch_queue_create("EDSamplerRemote.write", DISPATCH_QUEUE_SERIAL); sPending = [NSMutableDictionary dictionary]; });
    @synchronized (sPending) { sPending[@(channel * 1000 + param)] = @(value); if (sDraining) return; sDraining = YES; }
    dispatch_async(sWriteQ, ^{
        NSInteger dev = 0; EDMIDIPort *p = ConnectSaved(&dev);
        for (;;) {
            NSNumber *key = nil, *val = nil;
            @synchronized (sPending) { key = sPending.allKeys.firstObject; if (key) { val = sPending[key]; [sPending removeObjectForKey:key]; } else { sDraining = NO; } }
            if (!key) break;
            if (!p) continue;
            NSInteger ch = key.integerValue / 1000, param = key.integerValue % 1000; uint16_t u = (uint16_t)(val.integerValue & 0x3FFF);
            // 248 = 78h,01h  MULTIMODE_VOLUME;  249 = 79h,01h  MULTIMODE_PAN;  246 = 76h,01h  MULTIMODE_CHANNEL (selects the channel the next parameters apply to)
            uint8_t w[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x01, 0x04, 0x76, 0x01, (uint8_t)ch, 0x00, (uint8_t)(param & 0x7F), (uint8_t)(param >> 7), (uint8_t)(u & 0x7F), (uint8_t)(u >> 7), 0x7F, 0xF7};
            [p sendSysex:[NSData dataWithBytes:w length:sizeof w]]; [p flush]; [NSThread sleepForTimeInterval:0.03];
        }
        [p disconnect];
    });
}
+ (void)setVolume:(NSInteger)volume forChannel:(NSInteger)channel { QueueWrite(channel, 248, MAX(0, MIN(127, volume))); }
+ (void)setPan:(NSInteger)pan forChannel:(NSInteger)channel { QueueWrite(channel, 249, MAX(-64, MIN(63, pan))); }
+ (void)setPreset:(NSInteger)preset forChannel:(NSInteger)channel { QueueWrite(channel, 247, MAX(-1, MIN(999, preset))); }   // 247 = 77h,01h MULTIMODE_PRESET
+ (void)presetNameForNumber:(NSInteger)number completion:(void (^)(NSString *))done {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *name = nil; NSInteger dev = 0; EDMIDIPort *p = number >= 0 && number <= 999 ? ConnectSaved(&dev) : nil;
        if (p) {
            NSMutableArray *sink = [NSMutableArray array]; dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            p.onSysex = ^(NSData *m) { @synchronized (sink) { [sink addObject:m]; } dispatch_semaphore_signal(sem); };
            uint8_t q[] = {0xF0, 0x18, 0x21, (uint8_t)dev, 0x55, 0x06, (uint8_t)(number & 0x7F), (uint8_t)(number >> 7), 0xF7};
            NSData *m = Ask(p, [NSData dataWithBytes:q length:sizeof q], 0x05, 1.0, sink, sem);
            if (m.length > 9) name = [[[NSString alloc] initWithBytes:(const uint8_t *)m.bytes + 8 length:m.length - 9 encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            [p disconnect];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ done(name); });
    });
}
@end
