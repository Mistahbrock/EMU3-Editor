#import "EDMIDIPort.h"

@implementation EDMIDIEndpointInfo @end

static NSString *EndpointName(MIDIEndpointRef e) {
    CFStringRef n = NULL;
    MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &n);
    return n ? (__bridge_transfer NSString *)n : @"(unnamed)";
}
static NSArray *Endpoints(BOOL dest) {
    NSMutableArray *a = [NSMutableArray array];
    ItemCount c = dest ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources();
    for (ItemCount i = 0; i < c; i++) {
        EDMIDIEndpointInfo *e = [EDMIDIEndpointInfo new];
        e.ref = dest ? MIDIGetDestination(i) : MIDIGetSource(i);
        e.name = EndpointName(e.ref); [a addObject:e];
    }
    return a;
}

@implementation EDMIDIPort {
    MIDIClientRef _client; MIDIPortRef _in, _out;
    MIDIEndpointRef _src, _dst;
    NSMutableData *_acc; BOOL _inSysex;
}
+ (NSArray *)destinations { return Endpoints(YES); }
+ (NSArray *)sources { return Endpoints(NO); }

- (BOOL)connectSource:(EDMIDIEndpointInfo *)source destination:(EDMIDIEndpointInfo *)dest error:(NSError **)error {
    [self disconnect];
    // one CoreMIDI client for the whole run; creating and disposing one per transfer was unreliable
    static MIDIClientRef shared = 0; static OSStatus st;
    if (!shared) st = MIDIClientCreate(CFSTR("EMU3 Editor"), NULL, NULL, &shared);
    _client = shared;
    if (!shared) { if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:st userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Could not open CoreMIDI (error %d). The MIDI service was not ready when the app started: quit and reopen EMU3 Editor.", (int)st]}]; return NO; }
    _dst = dest.ref; _src = source.ref; _acc = [NSMutableData data]; _inSysex = NO;
    if (dest) MIDIOutputPortCreate(_client, CFSTR("Out"), &_out);
    if (source) {
        __weak EDMIDIPort *w = self;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        st = MIDIInputPortCreateWithBlock(_client, CFSTR("In"), &_in, ^(const MIDIPacketList *list, void *ref) {
            const MIDIPacket *p = &list->packet[0];
            for (UInt32 i = 0; i < list->numPackets; i++) { [w feed:p->data length:p->length]; p = MIDIPacketNext(p); }
        });
#pragma clang diagnostic pop
        if (st == noErr) MIDIPortConnectSource(_in, _src, NULL);
    }
    return YES;
}
- (void)feed:(const UInt8 *)d length:(UInt16)n {
    for (UInt16 i = 0; i < n; i++) {
        UInt8 b = d[i];
        if (b == 0xF0) { _inSysex = YES; _acc.length = 0; [_acc appendBytes:&b length:1]; }
        else if (b >= 0xF8) continue;                          // realtime bytes can interleave
        else if (b == 0xF7) {
            if (_inSysex) { [_acc appendBytes:&b length:1]; NSData *m = [_acc copy]; _inSysex = NO; _acc.length = 0; if (_onSysex) _onSysex(m); }
        } else if (b & 0x80) { _inSysex = NO; _acc.length = 0; }   // any other status ends the sysex
        else if (_inSysex) [_acc appendBytes:&b length:1];
    }
}
- (void)disconnect {
    if (_out) [self flush];
    if (_in) { MIDIPortDisconnectSource(_in, _src); MIDIPortDispose(_in); _in = 0; }
    if (_out) { MIDIPortDispose(_out); _out = 0; }
    _client = 0;
}
- (void)dealloc { [self disconnect]; }

// Up to 4 sysex requests are queued with CoreMIDI at once so the interface never idles between packets.
typedef struct { MIDISysexSendRequest req; void *data; void *sem; } EDSendCtx;
static void sysexDone(MIDISysexSendRequest *r) {
    EDSendCtx *c = (EDSendCtx *)r;
    dispatch_semaphore_t sem = (__bridge_transfer dispatch_semaphore_t)c->sem;
    free(c->data); free(c);
    dispatch_semaphore_signal(sem);
}
static dispatch_semaphore_t Slots(void) {
    static dispatch_semaphore_t s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = dispatch_semaphore_create(4); });
    return s;
}
- (void)sendSysex:(NSData *)message {
    if (!_out || !_dst) return;
    if (dispatch_semaphore_wait(Slots(), dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0) return;
    EDSendCtx *c = calloc(1, sizeof *c);
    c->data = malloc(message.length); memcpy(c->data, message.bytes, message.length);
    c->sem = (__bridge_retained void *)Slots();
    c->req.destination = _dst; c->req.data = c->data; c->req.bytesToSend = (UInt32)message.length;
    c->req.complete = false; c->req.completionProc = sysexDone; c->req.completionRefCon = NULL;
    if (MIDISendSysex(&c->req) != noErr) { dispatch_semaphore_t sem = (__bridge_transfer dispatch_semaphore_t)c->sem; free(c->data); free(c); dispatch_semaphore_signal(sem); }
}
/// Waits until everything queued has left the interface.
- (void)flush {
    for (int i = 0; i < 4; i++) dispatch_semaphore_wait(Slots(), dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    for (int i = 0; i < 4; i++) dispatch_semaphore_signal(Slots());
}
@end
