#import "EDPresetPlayer.h"
#import "EDPreset+Params.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMIDI/CoreMIDI.h>
#import <os/lock.h>

#define kMaxVoices 48

// One sounding zone. Everything the audio thread needs is plain data; the main thread rewrites the parameter part under the lock.
typedef struct {
    int active, key, vIndex, rIndex, released, stage, velocity;
    const int16_t *l, *r; NSUInteger frames, loopStart, loopEnd; int loops;
    double pos, step, env, pitch, rateRatio;   // step = pitch × rateRatio: source frames per output frame
    float gain, panL, panR;
    float lvl[6], speed[6];      // envelope: target level per stage (0…127) and how fast it travels (levels per output frame)
} PVoice;

typedef struct { os_unfair_lock lock; PVoice v[kMaxVoices]; double sampleRate; } PState;

// Envelope times are an estimate: a full-scale move (0 → 127) takes 1 ms at rate 0 and doubles every 8 rate steps (about a minute at 127).
static double fullTravelSeconds(NSInteger rate) { return 0.001 * pow(2.0, MAX(0, MIN(127, rate)) / 8.0); }

@implementation EDPresetPlayer {
    PState *_st; AVAudioEngine *_engine; AVAudioSourceNode *_source;
    NSMutableSet<EDSample *> *_keep;        // samples that may be playing: the audio thread reads their data without owning it
    NSMutableDictionary<NSNumber *, NSDictionary<NSString *, EDParam *> *> *_params;
    MIDIClientRef _client; MIDIPortRef _port;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _st = calloc(1, sizeof(PState)); _st->lock = OS_UNFAIR_LOCK_INIT; _st->sampleRate = 44100;
    _keep = [NSMutableSet set]; _params = [NSMutableDictionary dictionary];
    return self;
}
- (void)dealloc { [_engine stop]; if (_port) MIDIPortDispose(_port); if (_client) MIDIClientDispose(_client); free(_st); }

// MARK: audio

- (void)ensureEngine {
    if (_engine) return;
    PState *st = _st;
    AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
    _source = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *silence, const AudioTimeStamp *ts, AVAudioFrameCount n, AudioBufferList *out) {
        float *L = (float *)out->mBuffers[0].mData, *R = out->mNumberBuffers > 1 ? (float *)out->mBuffers[1].mData : L;
        memset(L, 0, n * sizeof(float)); if (R != L) memset(R, 0, n * sizeof(float));
        os_unfair_lock_lock(&st->lock);
        BOOL any = NO;
        for (int i = 0; i < kMaxVoices; i++) {
            PVoice *v = &st->v[i]; if (!v->active) continue; any = YES;
            for (AVAudioFrameCount f = 0; f < n; f++) {
                // envelope: Attack 1, Attack 2, Decay 1, Decay 2, hold, then Release 1, Release 2 once the key is up
                if (v->stage < 6 && !(v->stage >= 4 && !v->released)) {
                    double target = v->lvl[v->stage], sp = v->speed[v->stage];
                    if (v->env < target) { v->env += sp; if (v->env >= target) { v->env = target; v->stage++; } }
                    else if (v->env > target) { v->env -= sp; if (v->env <= target) { v->env = target; v->stage++; } }
                    else v->stage++;
                }
                if (v->stage >= 6) { v->active = 0; break; }
                double amp = MAX(0.0, v->env) / 127.0;
                NSUInteger i0 = (NSUInteger)v->pos; double fr = v->pos - i0; NSUInteger i1 = i0 + 1;
                if (v->loops && i1 > v->loopEnd) i1 = v->loopStart; else if (i1 >= v->frames) i1 = i0;
                float sl = (float)(v->l[i0] + (v->l[i1] - v->l[i0]) * fr) / 32768.0f, sr = sl;
                if (v->r) sr = (float)(v->r[i0] + (v->r[i1] - v->r[i0]) * fr) / 32768.0f;
                float g = v->gain * (float)amp;
                L[f] += sl * g * v->panL; if (R != L) R[f] += sr * g * v->panR;
                v->pos += v->step;
                if (v->loops) { if (v->pos >= v->loopEnd + 1.0) v->pos = v->loopStart + fmod(v->pos - v->loopStart, (double)(v->loopEnd + 1 - v->loopStart)); }
                else if (v->pos >= v->frames - 1) { v->active = 0; break; }
            }
        }
        os_unfair_lock_unlock(&st->lock);
        if (!any) *silence = YES;
        return noErr;
    }];
    _engine = [AVAudioEngine new];
    [_engine attachNode:_source]; [_engine connect:_source to:_engine.mainMixerNode format:fmt];
    NSError *e = nil; if (![_engine startAndReturnError:&e]) { _engine = nil; _source = nil; }
}

// MARK: reading the preset

- (NSDictionary<NSString *, EDParam *> *)tableFor:(EDParamScope)scope preset:(EDPreset *)p {
    NSDictionary *t = _params[@(scope)];
    if (!t) { NSMutableDictionary *m = [NSMutableDictionary dictionary]; for (EDParam *q in [p paramsForScope:scope]) m[[q.group stringByAppendingFormat:@"|%@", q.label]] = q; t = m; _params[@(scope)] = t; }
    return t;
}
static float fadeGain(NSInteger x, NSInteger lo, NSInteger flo, NSInteger fhi, NSInteger hi) {
    if (x < lo || x > hi) return 0;
    if (x < flo) return (float)(x - lo + 1) / (float)(flo - lo + 1);
    if (x > fhi) return (float)(hi - x + 1) / (float)(hi - fhi + 1);
    return 1;
}

/// Fills the parameter part of `pv` from the preset for voice v, zone r and the note it plays. NO when the note is outside the windows.
- (BOOL)configure:(PVoice *)pv preset:(EDPreset *)p {
    NSInteger v = pv->vIndex, r = pv->rIndex, key = pv->key, vel = pv->velocity;
    NSDictionary *vt = [self tableFor:EDScopeVoice preset:p], *rt = [self tableFor:EDScopeRef preset:p];
    NSInteger (^V)(NSString *, NSString *) = ^NSInteger(NSString *g, NSString *l) { EDParam *q = vt[[g stringByAppendingFormat:@"|%@", l]]; return q ? [p valueOfParam:q voice:v ref:r] : 0; };
    NSInteger (^Z)(NSString *, NSString *) = ^NSInteger(NSString *g, NSString *l) { EDParam *q = rt[[g stringByAppendingFormat:@"|%@", l]]; return q ? [p valueOfParam:q voice:v ref:r] : 0; };
    float w = fadeGain(key, V(@"Windows", @"Key low"), V(@"Windows", @"Key fade low"), V(@"Windows", @"Key fade high"), V(@"Windows", @"Key high"))
            * fadeGain(vel, V(@"Windows", @"Velocity low"), V(@"Windows", @"Velocity fade low"), V(@"Windows", @"Velocity fade high"), V(@"Windows", @"Velocity high"))
            * fadeGain(key, Z(@"Windows", @"Key low"), Z(@"Windows", @"Key fade low"), Z(@"Windows", @"Key fade high"), Z(@"Windows", @"Key high"))
            * fadeGain(vel, Z(@"Windows", @"Velocity low"), Z(@"Windows", @"Velocity fade low"), Z(@"Windows", @"Velocity fade high"), Z(@"Windows", @"Velocity high"));
    if (w <= 0) return NO;
    double db = V(@"Output", @"Volume dB") + Z(@"Sample", @"Volume dB");
    pv->gain = w * (float)(vel / 127.0) * (float)pow(10.0, db / 20.0) * 0.8f;
    double pan = MAX(-1.0, MIN(1.0, (V(@"Output", @"Pan") + Z(@"Sample", @"Pan")) / 64.0));
    pv->panL = (float)cos((pan + 1) * M_PI / 4); pv->panR = (float)sin((pan + 1) * M_PI / 4);
    NSInteger root = Z(@"Sample", @"Root key");
    double semis = V(@"Tuning", @"Non-transpose") ? 0 : (double)(key - root);
    semis += V(@"Tuning", @"Transpose") + V(@"Tuning", @"Fine tune") / 64.0 + Z(@"Sample", @"Fine tune") / 64.0;
    pv->pitch = pow(2.0, semis / 12.0);
    for (int i = 0; i < 6; i++) {
        NSString *s = @[@"Attack 1", @"Attack 2", @"Decay 1", @"Decay 2", @"Release 1", @"Release 2"][i];
        pv->lvl[i] = (float)MAX(0, MIN(127, V(@"Volume envelope", [s stringByAppendingString:@" level"])));
        pv->speed[i] = (float)(127.0 / (fullTravelSeconds(V(@"Volume envelope", [s stringByAppendingString:@" rate"])) * _st->sampleRate));
    }
    return YES;
}

// MARK: notes

- (NSString *)noteOn:(int)key velocity:(int)vel preset:(EDPreset *)p bank:(EDBank *)bank {
    if (!p || p.kind != EDPresetKindE4) return @"Keyboard audition works on EOS presets.";
    [self ensureEngine]; if (!_engine) return @"Could not start audio output.";
    vel = MAX(1, MIN(127, vel));
    NSMutableDictionary<NSNumber *, EDSample *> *byNumber = [NSMutableDictionary dictionary]; for (EDSample *s in bank.samples) byNumber[@(s.number)] = s;
    NSDictionary *rt = [self tableFor:EDScopeRef preset:p]; EDParam *sp = rt[@"Sample|Sample number"];
    NSMutableArray<NSString *> *names = [NSMutableArray array]; BOOL rom = NO, missing = NO;
    NSInteger nv = p.voiceCount;
    for (NSInteger v = 0; v < nv; v++) for (NSInteger r = 0; r < [p refCountInVoice:v]; r++) {
        PVoice pv; memset(&pv, 0, sizeof pv); pv.key = key; pv.vIndex = (int)v; pv.rIndex = (int)r; pv.velocity = vel; pv.loops = 0;
        if (![self configure:&pv preset:p]) continue;
        NSInteger sn = sp ? [p valueOfParam:sp voice:v ref:r] : 0; EDSample *s = byNumber[@(sn)];
        if (!s) { if (sn >= 1000) rom = YES; else missing = YES; continue; }
        if (s.frameCount < 2) continue;
        [_keep addObject:s];
        pv.l = s.leftFrames; pv.r = s.isStereo ? s.rightFrames : NULL; pv.frames = s.frameCount;
        pv.loops = s.loopEnabled && s.loopEnd > s.loopStart + 1 && s.loopEnd < s.frameCount; pv.loopStart = s.loopStart; pv.loopEnd = s.loopEnd;
        pv.rateRatio = (s.sampleRate ? s.sampleRate : 44100) / _st->sampleRate; pv.step = pv.pitch * pv.rateRatio;
        pv.active = 1; pv.stage = 0; pv.env = 0; pv.pos = 0;
        os_unfair_lock_lock(&_st->lock);
        int slot = -1; for (int i = 0; i < kMaxVoices; i++) if (!_st->v[i].active) { slot = i; break; }
        if (slot < 0) { for (int i = 0; i < kMaxVoices; i++) if (_st->v[i].released) { slot = i; break; } if (slot < 0) slot = 0; }
        _st->v[slot] = pv;
        os_unfair_lock_unlock(&_st->lock);
        [names addObject:[NSString stringWithFormat:@"#%ld %@", (long)sn, s.name]];
    }
    NSString *nn = [EDParam noteName:key];
    if (names.count) return [NSString stringWithFormat:@"%@  vel %d  →  %@", nn, vel, [names componentsJoinedByString:@", "]];
    if (rom) return [NSString stringWithFormat:@"%@: ROM samples can't be played here", nn];
    if (missing) return [NSString stringWithFormat:@"%@: sample is not in this bank", nn];
    return [NSString stringWithFormat:@"%@: no zone covers this key", nn];
}

- (void)noteOff:(int)key {
    os_unfair_lock_lock(&_st->lock);
    for (int i = 0; i < kMaxVoices; i++) { PVoice *v = &_st->v[i]; if (v->active && v->key == key && !v->released) { v->released = 1; if (v->stage < 4) v->stage = 4; } }
    os_unfair_lock_unlock(&_st->lock);
}
- (void)allNotesOff {
    os_unfair_lock_lock(&_st->lock);
    for (int i = 0; i < kMaxVoices; i++) { PVoice *v = &_st->v[i]; if (v->active && !v->released) { v->released = 1; if (v->stage < 4) v->stage = 4; } }
    os_unfair_lock_unlock(&_st->lock);
}

- (void)presetChanged:(EDPreset *)p {
    if (!p || p.kind != EDPresetKindE4 || !_engine) return;
    for (int i = 0; i < kMaxVoices; i++) {
        PVoice cur; os_unfair_lock_lock(&_st->lock); cur = _st->v[i]; os_unfair_lock_unlock(&_st->lock);
        if (!cur.active || cur.vIndex >= p.voiceCount || cur.rIndex >= [p refCountInVoice:cur.vIndex]) continue;
        PVoice n; memset(&n, 0, sizeof n); n.key = cur.key; n.vIndex = cur.vIndex; n.rIndex = cur.rIndex; n.velocity = cur.velocity;
        BOOL ok = [self configure:&n preset:p];
        os_unfair_lock_lock(&_st->lock);
        PVoice *live = &_st->v[i];
        if (live->active && live->key == cur.key && live->vIndex == cur.vIndex && live->rIndex == cur.rIndex) {
            live->gain = ok ? n.gain : 0; live->panL = n.panL; live->panR = n.panR; live->pitch = n.pitch; live->step = n.pitch * live->rateRatio;
            memcpy(live->lvl, n.lvl, sizeof n.lvl); memcpy(live->speed, n.speed, sizeof n.speed);
        }
        os_unfair_lock_unlock(&_st->lock);
    }
}

// MARK: MIDI keyboard

- (void)startMIDIInput {
    if (_client) return;
    __weak EDPresetPlayer *weak = self;
    OSStatus s = MIDIClientCreateWithBlock(CFSTR("EMU3 Editor audition"), &_client, ^(const MIDINotification *m) {
        if (m->messageID == kMIDIMsgSetupChanged) dispatch_async(dispatch_get_main_queue(), ^{ [weak connectSources]; });
    });
    if (s != noErr) { _client = 0; return; }
    MIDIInputPortCreateWithBlock(_client, CFSTR("Audition in"), &_port, ^(const MIDIPacketList *pl, void *ref) {
        const MIDIPacket *pk = &pl->packet[0];
        for (UInt32 i = 0; i < pl->numPackets; i++) {
            UInt16 j = 0;
            while (j < pk->length) {
                UInt8 b = pk->data[j];
                if (b < 0x80 || b >= 0xF0) { j++; continue; }
                UInt8 st = b & 0xF0; UInt16 need = (st == 0xC0 || st == 0xD0) ? 1 : 2;
                if (j + 1 + need > pk->length) break;
                if (st == 0x90 || st == 0x80) {
                    int key = pk->data[j + 1], vel = pk->data[j + 2]; BOOL on = st == 0x90 && vel > 0;
                    dispatch_async(dispatch_get_main_queue(), ^{ EDPresetPlayer *me = weak; if (me && me.midiNote) me.midiNote(key, vel, on); });
                }
                j += 1 + need;
            }
            pk = MIDIPacketNext(pk);
        }
    });
    [self connectSources];
}
- (void)connectSources {
    if (!_port) return;
    for (ItemCount i = 0; i < MIDIGetNumberOfSources(); i++) MIDIPortConnectSource(_port, MIDIGetSource(i), NULL);
}
@end
