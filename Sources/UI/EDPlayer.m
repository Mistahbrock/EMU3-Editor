#import "EDPlayer.h"
#import <AVFoundation/AVFoundation.h>

@implementation EDPlayer {
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_node;
    NSUInteger _headFrames, _loopFrames, _loopStart;
    BOOL _looping;
    NSInteger _generation;
}

- (BOOL)playing { return _node.isPlaying; }

static AVAudioPCMBuffer *makeBuffer(AVAudioFormat *fmt, EDSample *s, NSUInteger from, NSUInteger count) {
    AVAudioPCMBuffer *b = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:(AVAudioFrameCount)MAX(count, 1)];
    b.frameLength = (AVAudioFrameCount)count;
    const int16_t *l = s.leftFrames, *r = s.rightFrames;
    float *dl = b.floatChannelData[0], *dr = fmt.channelCount > 1 ? b.floatChannelData[1] : NULL;
    for (NSUInteger i = 0; i < count; i++) {
        dl[i] = l[from + i] / 32768.0f;
        if (dr) dr[i] = (r ? r[from + i] : l[from + i]) / 32768.0f;
    }
    return b;
}

- (void)playSample:(EDSample *)s { [self playSample:s ratio:1]; }
- (void)playSample:(EDSample *)s ratio:(double)ratio {
    [self stop];
    if (s.frameCount < 2) return;
    double rate = (s.sampleRate ? s.sampleRate : 44100) * MAX(1.0 / 16, MIN(8.0, ratio));   // playing the same data at a different rate shifts the pitch
    AVAudioChannelCount ch = s.right ? 2 : 1;
    AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:ch];
    _engine = [AVAudioEngine new];
    _node = [AVAudioPlayerNode new];
    [_engine attachNode:_node];
    [_engine connect:_node to:_engine.mainMixerNode format:fmt];
    NSError *err = nil;
    if (![_engine startAndReturnError:&err]) { _engine = nil; _node = nil; return; }

    NSInteger gen = ++_generation;
    __weak EDPlayer *weak = self;
    _looping = s.loopEnabled && s.loopEnd > s.loopStart + 1;
    if (_looping) {
        _loopStart = s.loopStart;
        _headFrames = s.loopStart;
        _loopFrames = s.loopEnd - s.loopStart + 1;
        if (_headFrames) [_node scheduleBuffer:makeBuffer(fmt, s, 0, _headFrames) completionHandler:nil];
        [_node scheduleBuffer:makeBuffer(fmt, s, _loopStart, _loopFrames) atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    } else {
        _headFrames = s.frameCount; _loopFrames = 0; _loopStart = 0;
        [_node scheduleBuffer:makeBuffer(fmt, s, 0, s.frameCount) completionCallbackType:AVAudioPlayerNodeCompletionDataPlayedBack
            completionHandler:^(AVAudioPlayerNodeCompletionCallbackType t) {
            dispatch_async(dispatch_get_main_queue(), ^{ EDPlayer *me = weak; if (me && me->_generation == gen) [me stop]; });
        }];
    }
    [_node play];
}

- (NSInteger)currentFrame {
    if (!_node.isPlaying) return -1;
    AVAudioTime *t = [_node playerTimeForNodeTime:_node.lastRenderTime];
    if (!t) return -1;
    NSInteger f = (NSInteger)t.sampleTime;
    if (f < 0) return 0;
    if (!_looping) return MIN(f, (NSInteger)_headFrames);
    if ((NSUInteger)f < _headFrames) return f;
    return (NSInteger)(_loopStart + ((NSUInteger)f - _headFrames) % MAX(_loopFrames, 1));
}

- (void)stop {
    _generation++;
    if (_node) { [_node stop]; }
    if (_engine) { [_engine stop]; }
    BOOL was = _node != nil;
    _node = nil; _engine = nil;
    if (was && _onStop) _onStop();
}
@end
