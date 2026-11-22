#import "EDSample+Ops.h"

static inline int16_t clip16(double v) { return (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : lrint(v))); }

@implementation EDSample (Ops)

- (NSMutableData *)mutableChannel:(NSData *)d { return d ? [d mutableCopy] : nil; }

/// Runs a per-channel in-place transform and stores the result, keeping loop points.
- (void)transform:(void (^)(int16_t *d, NSUInteger n))fn {
    NSMutableData *l = [self.left mutableCopy], *r = [self.right mutableCopy];
    NSUInteger n = self.frameCount;
    fn(l.mutableBytes, n);
    if (r) fn(r.mutableBytes, n);
    [self replaceLeft:l right:r];
}

- (double)peak {
    double p = 0; NSUInteger n = self.frameCount;
    for (int c = 0; c < 2; c++) {
        const int16_t *d = c == 0 ? self.leftFrames : self.rightFrames;
        if (!d) continue;
        for (NSUInteger i = 0; i < n; i++) p = MAX(p, fabs((double)d[i]));
    }
    return p / 32768.0;
}

- (void)applyGainDB:(double)db {
    double g = pow(10, db / 20);
    [self transform:^(int16_t *d, NSUInteger n) { for (NSUInteger i = 0; i < n; i++) d[i] = clip16(d[i] * g); }];
}

- (void)normalizeToPeak:(double)target {
    double p = [self peak];
    if (p <= 0) return;
    double g = target / p;
    [self transform:^(int16_t *d, NSUInteger n) { for (NSUInteger i = 0; i < n; i++) d[i] = clip16(d[i] * g); }];
}

- (void)reverse {
    NSUInteger n = self.frameCount, ls = self.loopStart, le = self.loopEnd;
    [self transform:^(int16_t *d, NSUInteger cnt) {
        for (NSUInteger i = 0; i < cnt / 2; i++) { int16_t t = d[i]; d[i] = d[cnt - 1 - i]; d[cnt - 1 - i] = t; }
    }];
    if (n) { self.loopStart = n - 1 - le; self.loopEnd = n - 1 - ls; }
}

- (void)fadeInFrames:(NSUInteger)f {
    [self transform:^(int16_t *d, NSUInteger n) {
        NSUInteger m = MIN(f, n);
        for (NSUInteger i = 0; i < m; i++) d[i] = clip16(d[i] * ((double)i / m));
    }];
}
- (void)fadeOutFrames:(NSUInteger)f {
    [self transform:^(int16_t *d, NSUInteger n) {
        NSUInteger m = MIN(f, n);
        for (NSUInteger i = 0; i < m; i++) d[n - 1 - i] = clip16(d[n - 1 - i] * ((double)i / m));
    }];
}

- (void)removeDC {
    [self transform:^(int16_t *d, NSUInteger n) {
        if (!n) return;
        double sum = 0; for (NSUInteger i = 0; i < n; i++) sum += d[i];
        double mean = sum / n;
        for (NSUInteger i = 0; i < n; i++) d[i] = clip16(d[i] - mean);
    }];
}

- (void)cropToFrom:(NSUInteger)from to:(NSUInteger)to {
    NSUInteger n = self.frameCount;
    if (n == 0 || from > to || to >= n) return;
    NSUInteger ls = self.loopStart, le = self.loopEnd, g = 4;   // keep the 4-frame guard the sampler expects
    NSUInteger len = to - from + 1 + 2 * g;
    NSMutableData *(^cut)(NSData *) = ^NSMutableData *(NSData *src) {
        if (!src) return nil;
        NSMutableData *o = [NSMutableData dataWithLength:len * 2];
        const int16_t *s = src.bytes; int16_t *d = o.mutableBytes;
        memcpy(d + g, s + from, (to - from + 1) * 2);
        return o;
    };
    NSMutableData *l = cut(self.left), *r = cut(self.right);
    self.loopStart = ls > from ? MIN(ls - from + g, len - 1) : g;
    self.loopEnd   = le > from ? MIN(le - from + g, len - 1) : g;
    [self replaceLeft:l right:r];
}

- (void)cropToLoop { if (self.loopEnd > self.loopStart) [self cropToFrom:self.loopStart to:self.loopEnd]; }

- (void)crossfadeLoopFrames:(NSUInteger)f {
    NSUInteger ls = self.loopStart, le = self.loopEnd;
    NSUInteger m = MIN(f, MIN(ls, le - ls));        // need audio before the loop start to fade from
    if (m < 2) return;
    [self transform:^(int16_t *d, NSUInteger n) {
        // the last m frames of the loop fade to the m frames that precede loopStart
        for (NSUInteger i = 0; i < m; i++) {
            double t = (double)(i + 1) / (m + 1);
            NSUInteger dst = le - m + 1 + i, src = ls - m + i;
            d[dst] = clip16(d[dst] * (1 - t) + d[src] * t);
        }
    }];
}
@end
