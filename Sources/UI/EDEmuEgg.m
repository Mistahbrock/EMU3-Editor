#import "EDEmuEgg.h"
#import "EDTheme.h"

typedef NS_ENUM(NSInteger, EggState) { EggRoam, EggRaise, EggLook, EggJump, EggRun, EggDone };
typedef NS_ENUM(NSInteger, EggAct) { ActWalk, ActPeck, ActLook, ActTrot, ActMount };

@implementation EDEmuEgg {
    NSTimer *_timer; id _monitor;
    EggState _state; double _t;
    CGFloat _x, _y, _u, _minX, _maxY, _tx, _ty; int _dir;
    NSArray<NSValue *> *_avoid; NSRect _mount; int _mountPhase;   // graphics to keep clear of (host coordinates), the mount icon it may go and peck
    double _ph;                                  // stride phase (radians)
    double _speed;                               // points per second along the facing
    EggAct _act; double _actT, _actDur; int _walkDir; int _lookFlips;
    double _peck;                                // 0 head up .. 1 beak at the floor
    CGPoint _head, _headFrom;                    // head cell relative to the body centre
    BOOL _entering; double _wag; BOOL _stepping; BOOL _headBack; double _jump; int _actCount; CGFloat _us;
    void (^_peckBlock)(BOOL); void (^_doneBlock)(BOOL); BOOL _pecked;   // _prev: last frame's pixels, drawn faintly like LCD ghosting; _headBack: the head looks over the shoulder
}

static __weak EDEmuEgg *sRunning;

+ (void)playOver:(NSView *)host avoiding:(NSArray<NSValue *> *)rects mount:(NSRect)mount leftLimit:(CGFloat)left peck:(void (^)(BOOL))peck done:(void (^)(BOOL))done {
    if (sRunning || !host.window) return;
    EDEmuEgg *e = [[EDEmuEgg alloc] initWithFrame:host.bounds]; e.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    CGFloat H = host.bounds.size.height;
    e->_u = MAX(2, MIN(4, floor((H - 74 - 12) / 40.0))); e->_minX = left + 10 * e->_u; e->_maxY = H - 34 * e->_u * 0.36 - 6;   // smaller at the top, so it can go higher
    e->_us = e->_u; e->_avoid = rects; e->_mount = mount; e->_peckBlock = [peck copy]; e->_doneBlock = [done copy]; e->_y = 74;
    [host addSubview:e positioned:NSWindowAbove relativeTo:nil]; sRunning = e; [e start];
}
- (NSView *)hitTest:(NSPoint)p { return nil; }
- (BOOL)isFlipped { return NO; }

- (void)start {
    CGFloat W = self.bounds.size.width;
    _state = EggRoam; _entering = YES; _x = W + 10 * _u; _dir = -1; _walkDir = -1; _act = ActWalk; _actT = 0; _actDur = 99; _head = CGPointMake(8, 19);
    __weak EDEmuEgg *w = self;
    _monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *ev) {
        EDEmuEgg *s = w; if (!s) return ev;
        if (s->_state == EggRoam) { s->_state = EggRaise; s->_t = 0; s->_headFrom = s->_head; s->_speed = 0; return nil; }   // the key or click that wakes the bird is not passed on
        return ev.type == NSEventTypeKeyDown ? nil : ev;   // while it leaves, keys are ignored; clicks work as usual
    }];
    _timer = [NSTimer timerWithTimeInterval:1.0 / 24 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)finish {
    if (_peckBlock) { _peckBlock(NO); _peckBlock = nil; }
    void (^done)(BOOL) = _doneBlock; _doneBlock = nil; BOOL pecked = _pecked;
    if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(pecked); });   // the bird is gone: now the mount opens
    [_timer invalidate]; _timer = nil; if (_monitor) { [NSEvent removeMonitor:_monitor]; _monitor = nil; }
    [self removeFromSuperview];
}
- (void)viewDidMoveToWindow { if (!self.window && (_timer || _monitor)) [self finish]; }
static CGFloat Lerp(CGFloat a, CGFloat b, double t) { return a + (b - a) * (CGFloat)t; }
static double Ease(double t) { t = MAX(0, MIN(1, t)); return t * t * (3 - 2 * t); }

// depth: the bird shrinks as it walks up the panel
- (CGFloat)scaleAt:(CGFloat)y { double k = MAX(0, MIN(1, (y - 74) / MAX(_maxY - 74, 1))); return _u * (1 - 0.7 * k); }
// can the bird stand at (x, y) without touching any graphic?
- (BOOL)clearAtX:(CGFloat)x y:(CGFloat)y {
    CGFloat us = [self scaleAt:y]; NSRect r = NSMakeRect(x - 9 * us, y, 18 * us, 33 * us);
    for (NSValue *v in _avoid) if (NSIntersectsRect(r, v.rectValue)) return NO;
    return YES;
}
- (BOOL)pathClearFromX:(CGFloat)x y:(CGFloat)y toX:(CGFloat)tx y:(CGFloat)ty {
    for (int i = 0; i <= 16; i++) { double k = i / 16.0; if (![self clearAtX:Lerp(x, tx, k) y:Lerp(y, ty, k)]) return NO; }
    return YES;
}
- (void)pickTarget {
    CGFloat W = self.bounds.size.width, maxX = W - 9 * _u;
    for (int i = 0; i < 24; i++) {
        CGFloat tx = _minX + (maxX - _minX) * (arc4random() % 1000) / 1000.0, ty = 74 + (_maxY - 74) * (arc4random() % 1000) / 1000.0;
        if (hypot(tx - _x, ty - _y) > 120 && [self clearAtX:tx y:ty] && [self pathClearFromX:_x y:_y toX:tx y:ty]) { _tx = tx; _ty = ty; return; }
    }
    _tx = _x; _ty = _y;
}
- (void)pickAct {
    EggAct n;
    BOOL mountOK = !NSIsEmptyRect(_mount) && NSMinY(_mount) - 30 * [self scaleAt:NSMinY(_mount)] >= 74 - 1 && _y > 0;
    if (mountOK && ((_actCount >= 3 && arc4random() % 4 == 0))) n = ActMount;
    else do { n = (EggAct)(arc4random() % 4); } while (n == _act);
    _act = n; _actT = 0; _lookFlips = 0; _actCount++;
    switch (n) {
        case ActWalk: case ActTrot: _actDur = 9; [self pickTarget]; break;
        case ActPeck: _actDur = 2.1; break;
        case ActLook: _actDur = 2.4; break;
        case ActMount: _actDur = 30; _mountPhase = 0; _tx = NSMidX(_mount); _ty = NSMinY(_mount) - 30 * _u; for (int i = 0; i < 4; i++) _ty = NSMinY(_mount) - 30 * [self scaleAt:_ty]; break;
    }
}

- (void)tick {
    _us = [self scaleAt:_y]; const double dt = 1.0 / 24; _t += dt; CGFloat W = self.bounds.size.width, maxX = W - 9 * _u;
    CGPoint walkHead = CGPointMake(9, 20), floorHead = CGPointMake(13, 3), upHead = CGPointMake(4, 28);
    _stepping = NO;
    switch (_state) {
        case EggRoam: {
            _actT += dt;
            if (_entering) { if (_x < W * 0.72) { _entering = NO; [self pickAct]; } }
            else if (_actT > _actDur) [self pickAct];
            BOOL moving = (_act == ActWalk || _act == ActTrot || _entering || (_act == ActMount && _mountPhase == 0));
            if (moving) {
                _speed = (_act == ActTrot && !_entering) ? 150 : (_act == ActMount ? 95 : 62); _stepping = YES;
                if (_entering) { _dir = -1; _x -= _speed * dt; }
                else {
                    double dx = _tx - _x, dy = _ty - _y, dist = hypot(dx, dy), step = _speed * dt * (_us / _u);   // farther away = slower
                    if (dist <= step + 1) { _x = _tx; _y = _ty; _stepping = NO;
                        if (_act == ActMount) { _mountPhase = 1; _actT = 0; _dir = 1; } else _actT = _actDur; }   // arrived
                    else { _x += dx / dist * step; _y += dy / dist * step; if (fabs(dx) > 3) _dir = dx > 0 ? 1 : -1; }
                }
                _ph += (_speed > 100 ? 15.0 : 7.0) * dt;
                // the head bobs and jerks forward with each step, the neck follows
                _head = CGPointMake(walkHead.x + 1.6 * sin(_ph), walkHead.y + 1.4 * sin(_ph * 2));
                _peck = 0;
            } else if (_act == ActMount) {              // reaching up to peck the mount icon, three times, then bolt before it opens
                double sv = fabs(sin(_actT * M_PI / 0.42)); _head = CGPointMake(upHead.x + 3, upHead.y - 2 + 4 * sv); _peck = 0;   // the beak is highest, at the icon, when sv = 1
                if (_peckBlock) _peckBlock(sv > 0.86); _pecked = YES;
                if (_actT > 1.3) { _state = EggLook; _t = 0; _head = upHead; if (_peckBlock) _peckBlock(NO); }
            } else if (_act == ActPeck) {
                double ph = fmod(_actT, 0.7) / 0.7; _peck = ph < 0.3 ? Ease(ph / 0.3) : (ph < 0.5 ? 1 - Ease((ph - 0.3) / 0.2) * 0.15 : 1 - Ease((ph - 0.5) / 0.5) * 1.0);
                if (ph < 0.3 || ph >= 0.5) {} // keep value
                _head = CGPointMake(Lerp(walkHead.x, floorHead.x, _peck), Lerp(walkHead.y, floorHead.y, _peck)); _wag += dt * 6;
            } else {                                   // neck up, a quick look around
                double k = Ease(_actT / 0.5); _head = CGPointMake(Lerp(walkHead.x, upHead.x, k), Lerp(walkHead.y, upHead.y, k));
                if (_actT > 0.5) _head.x = upHead.x + 2.5 + 5.5 * cos((_actT - 0.5) * 2 * M_PI / 1.6) - 5.5;
                if (_actT > _actDur - 0.5) { double b = Ease((_actT - (_actDur - 0.5)) / 0.5); _head = CGPointMake(Lerp(upHead.x, walkHead.x, b), Lerp(upHead.y, walkHead.y, b)); }
            }
            break; }
        case EggRaise: {
            double k = Ease(_t / 0.25); _head = CGPointMake(Lerp(_headFrom.x, upHead.x, k), Lerp(_headFrom.y, upHead.y, k)); _peck = 0;
            if (_t >= 0.25) { _state = EggLook; _t = 0; _lookFlips = 0; }
            break; }
        case EggLook:
            _head = upHead; _head.x = upHead.x + 2.5 + 5.5 * cos(_t * 2 * M_PI / 0.8) - 5.5;   // the neck sways: head swings forward, back over the shoulder, forward…
            if (_t > 1.6) { _state = EggJump; _t = 0; _dir = 1; _headFrom = upHead; }
            break;
        case EggJump: {   // startled: a hop straight up, neck stretched, wings out
            _head = CGPointMake(upHead.x - 1, upHead.y + 1); _jump = sin(MIN(_t / 0.42, 1.0) * M_PI) * 10;
            if (_t > 0.42) { _jump = 0; _state = EggRun; _t = 0; _headFrom = _head; }
            break; }
        case EggRun: {
            double k = Ease(_t / 0.18); _head = CGPointMake(Lerp(_headFrom.x, 14, k), Lerp(_headFrom.y, 18, k));
            if (_t > 0.12) { _speed = 1500 * Ease((_t - 0.12) / 0.5) + 200; _x += _speed * dt; _ph += 34 * dt; _stepping = YES; }
            if (_x > W + 12 * _u) { _state = EggDone; [self finish]; return; }
            break; }
        default: break;
    }
    _headBack = _head.x < 2.5 && (_state == EggLook || (_state == EggRoam && _act == ActLook));
    self.needsDisplay = YES;
}

// ---- drawing: everything is blocks of one sprite pixel, in the LCD ink colour ----
- (void)cx:(int)ix y:(int)iy { CGFloat u = _us; NSRectFill(NSMakeRect(round(_x + (_dir > 0 ? ix : -ix - 1) * u), round(_y + iy * u), ceil(u), ceil(u))); }
- (void)line:(CGPoint)a to:(CGPoint)b thick:(int)th {
    int x0 = lround(a.x), y0 = lround(a.y), x1 = lround(b.x), y1 = lround(b.y);
    int dx = abs(x1 - x0), dy = abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1, err = dx - dy;
    for (;;) { [self cx:x0 y:y0]; if (th > 1) { [self cx:x0 + 1 y:y0]; } if (th > 2) { [self cx:x0 y:y0 + 1]; }
        if (x0 == x1 && y0 == y1) break; int e2 = 2 * err; if (e2 > -dy) { err -= dy; x0 += sx; } if (e2 < dx) { err += dx; y0 += sy; } }
}
- (void)leg:(int)hipX phase:(double)ph moving:(BOOL)mv running:(BOOL)run bodyY:(int)by {
    CGPoint hip = CGPointMake(hipX, 9 + by), foot, knee;
    if (_state == EggJump) { foot = CGPointMake(hipX + (hipX < 0 ? -2 : 3), MAX(0, by - 1)); }
    else if (mv) { double stride = run ? 5 : 3; foot = CGPointMake(hipX + round(sin(ph) * stride), MAX(0, cos(ph)) * (run ? 5 : 3)); }
    else foot = CGPointMake(hipX, 0);
    knee = CGPointMake((hip.x + foot.x) / 2 + (run ? 3 : 2), (hip.y + foot.y) / 2 + 1);
    [self line:hip to:knee thick:2]; [self line:knee to:foot thick:1];
    int fx = lround(foot.x), fy = lround(foot.y); [self cx:fx + 1 y:fy]; [self cx:fx + 2 y:fy]; [self cx:fx + 3 y:fy];   // toes
}
- (void)drawRect:(NSRect)dirty {
    [EDTheme.lcdInk setFill];
    BOOL run = _state == EggRun && _t > 0.12, mv = _stepping, jumping = _state == EggJump;
    int bodyY = mv ? (int)lround(fabs(sin(_ph)) * (run ? 2 : 1)) : 0; if (jumping) bodyY = (int)lround(_jump);
    [self leg:-2 phase:_ph moving:mv running:run bodyY:bodyY]; [self leg:2 phase:_ph + M_PI moving:mv running:run bodyY:bodyY];
    // body: a rounded block with a few LCD-gap feathers
    for (int y = 9; y <= 15; y++) { int a = (y == 9) ? -4 : (y == 15 ? -3 : -5), b = (y == 9) ? 3 : (y == 15 ? 2 : 4); for (int x = a; x <= b; x++) [self cx:x y:y + bodyY]; }
    // tail tuft wags
    int tw = (int)lround(sin(_wag + _ph * 0.5) > 0 ? 1 : 0);
    for (int y = 11; y <= 14; y++) { [self cx:-6 y:y + bodyY + tw]; if (y >= 12 && y <= 13) [self cx:-7 y:y + bodyY + tw]; }
    // wing: a short feathered flap, beating while running
    int flap = run ? (int)lround(sin(_ph * 1.0) * 2) : (jumping ? (int)(_t * 24) % 2 * 3 - 1 : 0); [self cx:-3 y:16 + bodyY + flap]; [self cx:-2 y:16 + bodyY + flap]; [self cx:-4 y:15 + bodyY + flap];
    [EDTheme.lcdBackground setFill]; for (NSValue *v in @[@[@-1, @12], @[@1, @11], @[@-3, @11], @[@2, @13], @[@0, @14]]) { NSArray *c = (NSArray *)v; [self cx:[c[0] intValue] y:[c[1] intValue] + bodyY]; }
    [EDTheme.lcdInk setFill];
    // neck: a bent S curve from the shoulder to the head
    CGPoint p0 = CGPointMake(3, 14 + bodyY), p3 = CGPointMake(_head.x, _head.y);
    CGPoint p1 = CGPointMake(p0.x + 3, p0.y + (p3.y - p0.y) * 0.7), p2 = CGPointMake(p3.x - 3, p3.y + (p0.y - p3.y) * 0.3);
    for (int i = 0; i <= 40; i++) { double t = i / 40.0, m = 1 - t;
        CGFloat x = m*m*m*p0.x + 3*m*m*t*p1.x + 3*m*t*t*p2.x + t*t*t*p3.x, y = m*m*m*p0.y + 3*m*m*t*p1.y + 3*m*t*t*p2.y + t*t*t*p3.y;
        int cx = (int)lround(x), cy = (int)lround(y); [self cx:cx y:cy]; [self cx:cx + 1 y:cy]; [self cx:cx y:cy + 1]; }
    // head and beak (the beak tips down while pecking)
    int hx = (int)lround(p3.x), hy = (int)lround(p3.y);
    int f = _headBack ? -1 : 1;   // beak side
    for (int y = hy; y <= hy + 1; y++) for (int x = (f > 0 ? hx : hx - 2); x <= (f > 0 ? hx + 2 : hx); x++) [self cx:x y:y];
    [self cx:hx + 3 * f y:hy]; [self cx:hx + 4 * f y:_peck > 0.4 ? hy - 1 : hy]; if (_peck > 0.4) [self cx:hx + 5 * f y:hy - 2];
    if (_state == EggLook || _state == EggJump) {   // scare rays burst around the head, flickering between two patterns
        BOOL alt = ((int)(_t * 14)) % 2; int cxh = hx + 1, cyh = hy + 1;
        static const int dirs[8][2] = {{1,0},{1,1},{0,1},{-1,1},{-1,0},{-1,-1},{0,-1},{1,-1}};
        for (int i = 0; i < 8; i++) { if ((i % 2) != alt) continue; int dx = dirs[i][0], dy = dirs[i][1];
            for (int r = 4; r <= 6; r++) [self cx:cxh + dx * r y:cyh + dy * r]; }
    }
    if (_state == EggJump) { int ex = hx + 1, ey = hy + 9; for (int y = ey + 2; y <= ey + 6; y++) { [self cx:ex y:y]; [self cx:ex + 1 y:y]; } [self cx:ex y:ey]; [self cx:ex + 1 y:ey]; }   // “!”
    [EDTheme.lcdBackground setFill]; [self cx:hx + 2 * f - (f < 0 ? 0 : 0) y:hy + 1];   // eye
}
- (void)dealloc { [_timer invalidate]; if (_monitor) [NSEvent removeMonitor:_monitor]; }
@end
