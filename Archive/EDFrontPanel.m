#import "EDFrontPanel.h"
#import "EDMainWindowController.h"
#import "EDTheme.h"
#import "EDBank.h"

// MARK: layout (design space 1980 x 590, origin top-left; follows the E64 front panel)

typedef struct { const char *key; const char *label; CGFloat x, y, w, h; int shape; CGFloat labelDy; } EDBtn;   // shape 0 round, 1 pill, 2 square key
static const EDBtn kButtons[] = {
    {"master", "MASTER", 225, 349, 50, 50, 0, -45},
    {"pmanage", "MANAGE", 340, 349, 50, 50, 0, -45}, {"pedit", "EDIT", 430, 349, 50, 50, 0, -45}, {"audition", "AUDITION", 560, 349, 50, 50, 0, -45},
    {"disk", "DISK", 225, 481, 50, 50, 0, -45},
    {"smanage", "MANAGE", 340, 481, 50, 50, 0, -45}, {"sedit", "EDIT", 430, 481, 50, 50, 0, -45},
    {"f1", "F1", 752, 349, 50, 50, 0, -45}, {"f2", "F2", 855, 349, 50, 50, 0, -45}, {"f3", "F3", 957, 349, 50, 50, 0, -45},
    {"f4", "F4", 1062, 349, 50, 50, 0, -45}, {"f5", "F5", 1166, 349, 50, 50, 0, -45}, {"f6", "F6", 1270, 349, 50, 50, 0, -45},
    {"a1", "1", 730, 481, 50, 50, 0, 0}, {"a2", "2", 820, 481, 50, 50, 0, 0}, {"a3", "3", 910, 481, 50, 50, 0, 0},
    {"exit", "EXIT", 1010, 481, 50, 50, 0, -45}, {"pageprev", "PREV", 1105, 481, 50, 50, 0, -45}, {"pagenext", "NEXT", 1190, 481, 50, 50, 0, -45},
    {"enter", "ENTER", 1290, 481, 50, 50, 0, -45},
    {"inc", "Inc", 1511, 259, 72, 42, 1, 0}, {"dec", "Dec", 1775, 259, 72, 42, 1, 0},
    {"1", "1", 1561, 320, 46, 46, 0, 0}, {"2", "2", 1652, 320, 46, 46, 0, 0}, {"3", "3", 1743, 320, 46, 46, 0, 0},
    {"4", "4", 1561, 387, 46, 46, 0, 0}, {"5", "5", 1652, 387, 46, 46, 0, 0}, {"6", "6", 1743, 387, 46, 46, 0, 0},
    {"7", "7", 1561, 453, 46, 46, 0, 0}, {"8", "8", 1652, 453, 46, 46, 0, 0}, {"9", "9", 1743, 453, 46, 46, 0, 0},
    {"0", "0", 1561, 520, 46, 46, 0, 0}, {"+/-", "+/-", 1652, 520, 46, 46, 0, 0}, {".", ".", 1743, 520, 46, 46, 0, 0},
    {"up", "▲", 1415, 370, 48, 48, 2, 0}, {"left", "◀", 1360, 428, 48, 48, 2, 0},
    {"right", "▶", 1470, 428, 48, 48, 2, 0}, {"down", "▼", 1415, 485, 48, 48, 2, 0},
};
static const int kButtonCount = sizeof(kButtons) / sizeof(kButtons[0]);
static const NSSize kDesign = {1980, 590};
static const NSRect kLCD = {{683, 62}, {674, 174}};
static const NSPoint kWheelCenter = {1645, 125};
static const CGFloat kWheelRadius = 112;
static const NSRect kFloppy = {{1862, 58}, {88, 480}};

static NSRect btnRect(const EDBtn *b) { return NSMakeRect(b->x - b->w / 2, b->y - b->h / 2, b->w, b->h); }

// MARK: the drawn panel

@interface EDFrontPanelView : NSView
@property (nonatomic, copy) NSDictionary *(^lcd)(void);                // header, rows, cursor, big, soft[6], note
@property (nonatomic, copy) void (^pressed)(NSString *key);
@property (nonatomic, copy) void (^wheel)(int steps);
@property (nonatomic, copy) void (^dropped)(NSURL *url);
@property (nonatomic) CGFloat wheelAngle;
@end

@implementation EDFrontPanelView {
    NSString *_down;           // key currently held with the mouse
    BOOL _dragWheel; CGFloat _lastAngle, _wheelAcc;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}

- (CGFloat)scale { return MIN(self.bounds.size.width / kDesign.width, self.bounds.size.height / kDesign.height); }
- (NSPoint)origin { CGFloat s = [self scale]; return NSMakePoint((self.bounds.size.width - kDesign.width * s) / 2, (self.bounds.size.height - kDesign.height * s) / 2); }
- (NSPoint)designPoint:(NSPoint)p { CGFloat s = [self scale]; NSPoint o = [self origin]; return NSMakePoint((p.x - o.x) / s, (p.y - o.y) / s); }

- (void)drawRect:(NSRect)dirty {
    [[NSColor colorWithCalibratedWhite:0.05 alpha:1] setFill]; NSRectFill(self.bounds);
    CGFloat s = [self scale]; NSPoint o = [self origin];
    NSAffineTransform *t = [NSAffineTransform transform]; [t translateXBy:o.x yBy:o.y]; [t scaleBy:s]; [t concat];

    // body
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, kDesign.width, kDesign.height) xRadius:14 yRadius:14];
    [[NSGradient alloc] initWithColors:@[[NSColor colorWithCalibratedWhite:0.20 alpha:1], [NSColor colorWithCalibratedWhite:0.13 alpha:1]]];
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.22 alpha:1] endingColor:[NSColor colorWithCalibratedWhite:0.12 alpha:1]] drawInBezierPath:body angle:90];
    [[NSColor blackColor] setStroke]; body.lineWidth = 4; [body stroke];
    // lower control area is a slightly different tone
    NSBezierPath *lower = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(130, 285, 1730, 290) xRadius:8 yRadius:8];
    [[NSColor colorWithCalibratedWhite:0.17 alpha:1] setFill]; [lower fill];
    // red stripe
    [[EDTheme accent] setFill]; NSRectFill(NSMakeRect(148, 532, 1370, 4)); NSRectFill(NSMakeRect(1790, 532, 28, 3));

    [self drawWordmark];
    [self drawLCD];
    for (int i = 0; i < kButtonCount; i++) [self drawButton:&kButtons[i]];
    [self drawLEDsAndLabels];
    [self drawWheel];
    [self drawFloppy];
}

- (void)drawWordmark {
    NSDictionary *big = @{NSFontAttributeName: [NSFont systemFontOfSize:118 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: [EDTheme logoBlue]};
    [@"EMU" drawAtPoint:NSMakePoint(176, 50) withAttributes:big];
    [@"3" drawAtPoint:NSMakePoint(440, 50) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:118 weight:NSFontWeightHeavy], NSForegroundColorAttributeName: [EDTheme accent]}];
    NSDictionary *sub = @{NSFontAttributeName: [EDTheme panelFont:28], NSForegroundColorAttributeName: [EDTheme labelWhite]};
    [@"SAMPLER EDITOR" drawAtPoint:NSMakePoint(182, 192) withAttributes:sub];
    NSBezierPath *swoosh = [NSBezierPath bezierPath]; [swoosh moveToPoint:NSMakePoint(170, 168)];
    [swoosh curveToPoint:NSMakePoint(560, 150) controlPoint1:NSMakePoint(300, 205) controlPoint2:NSMakePoint(480, 130)];
    swoosh.lineWidth = 7; [[EDTheme accent] setStroke]; [swoosh stroke];
}

// MARK: LCD

- (void)drawLCD {
    NSBezierPath *bezel = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(kLCD, -22, -28) xRadius:10 yRadius:10];
    [[NSColor blackColor] setFill]; [bezel fill];
    NSBezierPath *glass = [NSBezierPath bezierPathWithRoundedRect:kLCD xRadius:4 yRadius:4];
    [[EDTheme lcdBackground] setFill]; [glass fill];
    [NSGraphicsContext saveGraphicsState]; [glass addClip];
    NSDictionary *d = self.lcd ? self.lcd() : @{};
    NSColor *ink = [EDTheme lcdInk];
    NSString *header = d[@"header"] ?: @"";
    NSMutableParagraphStyle *center = [NSMutableParagraphStyle new]; center.alignment = NSTextAlignmentCenter; center.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSMutableParagraphStyle *left = [NSMutableParagraphStyle new]; left.lineBreakMode = NSLineBreakByTruncatingTail;
    [header drawInRect:NSMakeRect(kLCD.origin.x + 8, kLCD.origin.y + 6, kLCD.size.width - 16, 34)
        withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:27], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: center}];
    [ink setFill]; NSRectFill(NSMakeRect(kLCD.origin.x + 10, kLCD.origin.y + 42, kLCD.size.width - 20, 2));

    NSArray<NSString *> *rows = d[@"rows"] ?: @[]; NSInteger cursor = [d[@"cursor"] integerValue]; BOOL big = [d[@"big"] boolValue];
    CGFloat top = kLCD.origin.y + 50;
    if (big) {
        NSString *t = rows.firstObject ?: @"";
        [t drawInRect:NSMakeRect(kLCD.origin.x + 14, top + 6, kLCD.size.width - 28, 56)
       withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:38], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: left}];
    } else {
        for (NSUInteger i = 0; i < rows.count && i < 3; i++) {
            NSRect r = NSMakeRect(kLCD.origin.x + 10, top + i * 30, kLCD.size.width - 20, 29);
            BOOL sel = (NSInteger)[d[@"first"] integerValue] + (NSInteger)i == cursor;
            if (sel) { [ink setFill]; NSRectFill(r); }
            [rows[i] drawInRect:NSInsetRect(r, 6, 1) withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:22],
                NSForegroundColorAttributeName: sel ? [EDTheme lcdBackground] : ink, NSParagraphStyleAttributeName: left}];
        }
    }
    NSString *note = d[@"note"];
    if (note.length) [note drawInRect:NSMakeRect(kLCD.origin.x + 14, kLCD.origin.y + kLCD.size.height - 66, kLCD.size.width - 28, 22)
        withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:17], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: left}];
    NSArray<NSString *> *soft = d[@"soft"] ?: @[];
    CGFloat cw = (kLCD.size.width - 16) / 6;
    for (NSUInteger i = 0; i < 6 && i < soft.count; i++) {
        if (![soft[i] length]) continue;
        NSRect r = NSMakeRect(kLCD.origin.x + 8 + i * cw + 3, kLCD.origin.y + kLCD.size.height - 40, cw - 6, 32);
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:8 yRadius:8]; p.lineWidth = 2; [ink setStroke]; [p stroke];
        [soft[i] drawInRect:NSOffsetRect(r, 0, 4) withAttributes:@{NSFontAttributeName: [EDTheme lcdFont:17], NSForegroundColorAttributeName: ink, NSParagraphStyleAttributeName: center}];
    }
    // dot-matrix feel
    [[NSColor colorWithCalibratedWhite:0 alpha:0.010] setFill];
    for (CGFloat x = kLCD.origin.x; x < NSMaxX(kLCD); x += 4) NSRectFill(NSMakeRect(x, kLCD.origin.y, 1, kLCD.size.height));
    for (CGFloat y = kLCD.origin.y; y < NSMaxY(kLCD); y += 4) NSRectFill(NSMakeRect(kLCD.origin.x, y, kLCD.size.width, 1));
    [NSGraphicsContext restoreGraphicsState];
}

// MARK: buttons

- (void)drawButton:(const EDBtn *)b {
    NSRect r = btnRect(b); BOOL on = _down && strcmp(_down.UTF8String, b->key) == 0;
    NSBezierPath *p;
    if (b->shape == 1) p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:r.size.height / 2 yRadius:r.size.height / 2];
    else if (b->shape == 2) p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:10 yRadius:10];
    else p = [NSBezierPath bezierPathWithOvalInRect:r];
    NSColor *a = on ? [NSColor colorWithCalibratedWhite:0.34 alpha:1] : [NSColor colorWithCalibratedWhite:0.19 alpha:1];
    NSColor *c = on ? [NSColor colorWithCalibratedWhite:0.20 alpha:1] : [NSColor colorWithCalibratedWhite:0.07 alpha:1];
    [[[NSGradient alloc] initWithStartingColor:a endingColor:c] drawInBezierPath:p angle:on ? 90 : -90];
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] setStroke]; p.lineWidth = 3; [p stroke];
    [[NSColor colorWithCalibratedWhite:0.38 alpha:1] setStroke]; NSBezierPath *hi = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(r, 3, 3)];
    if (b->shape == 0) { hi.lineWidth = 1; [hi stroke]; }
    NSString *label = [NSString stringWithUTF8String:b->label];
    BOOL inside = b->labelDy == 0;
    NSDictionary *at = @{NSFontAttributeName: [EDTheme panelFont:inside ? 24 : 19], NSForegroundColorAttributeName: [EDTheme labelWhite]};
    NSSize sz = [label sizeWithAttributes:at];
    NSPoint at0 = inside ? NSMakePoint(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2) : NSMakePoint(NSMidX(r) - sz.width / 2, NSMidY(r) + b->labelDy - sz.height / 2);
    [label drawAtPoint:at0 withAttributes:at];
}
- (void)drawHeader:(NSString *)t centerX:(CGFloat)cx y:(CGFloat)y width:(CGFloat)w {
    NSDictionary *at = @{NSFontAttributeName: [EDTheme panelFont:17], NSForegroundColorAttributeName: [EDTheme labelWhite]};
    NSSize sz = [t sizeWithAttributes:at];
    [t drawAtPoint:NSMakePoint(cx - sz.width / 2, y - sz.height / 2) withAttributes:at];
    CGFloat ly = y + sz.height / 2 + 2;
    [[EDTheme accent] setFill];
    NSRectFill(NSMakeRect(cx - w / 2, ly, w, 2));
    NSRectFill(NSMakeRect(cx - w / 2, ly, 2, 8)); NSRectFill(NSMakeRect(cx + w / 2 - 2, ly, 2, 8));      // bracket ends pointing down at the buttons
}
- (void)drawLEDsAndLabels {
    [self drawHeader:@"PRESET" centerX:385 y:271 width:130];
    [self drawHeader:@"SAMPLE" centerX:385 y:403 width:130];
    [self drawHeader:@"ASSIGNABLE KEYS" centerX:820 y:403 width:230];
    [self drawHeader:@"PAGE" centerX:1148 y:403 width:130];
    NSDictionary *at = @{NSFontAttributeName: [EDTheme panelFont:15], NSForegroundColorAttributeName: [EDTheme labelWhite]};
    [[NSColor colorWithCalibratedWhite:0.28 alpha:1] setFill];
    for (NSArray *l in @[@[@"MIDI", @440], @[@"SCSI", @466]]) {
        CGFloat y = [l[1] doubleValue];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(512, y - 5, 10, 10)] fill];
        [l[0] drawAtPoint:NSMakePoint(530, y - 9) withAttributes:at];
    }
}

// MARK: wheel

- (void)drawWheel {
    NSPoint c = kWheelCenter; CGFloat R = kWheelRadius;
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - R, c.y - R, 2 * R, 2 * R)];
    [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.25 alpha:1] endingColor:[NSColor colorWithCalibratedWhite:0.05 alpha:1]] drawInBezierPath:rim angle:-90];
    [[NSColor blackColor] setStroke]; rim.lineWidth = 4; [rim stroke];
    NSBezierPath *dish = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - R + 9, c.y - R + 9, 2 * R - 18, 2 * R - 18)];
    [[NSColor colorWithCalibratedWhite:0.11 alpha:1] setFill]; [dish fill];
    CGFloat a = _wheelAngle, dr = R * 0.62;
    NSPoint dc = NSMakePoint(c.x + cos(a) * dr, c.y + sin(a) * dr);
    NSBezierPath *dimple = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dc.x - 30, dc.y - 30, 60, 60)];
    [[NSColor colorWithCalibratedWhite:0.04 alpha:1] setFill]; [dimple fill];
    [[NSColor colorWithCalibratedWhite:0.28 alpha:1] setStroke]; dimple.lineWidth = 1.5; [dimple stroke];
}

- (void)drawFloppy {
    NSBezierPath *slot = [NSBezierPath bezierPathWithRoundedRect:kFloppy xRadius:6 yRadius:6];
    [[NSColor colorWithCalibratedWhite:0.06 alpha:1] setFill]; [slot fill];
    [[NSColor colorWithCalibratedWhite:0.30 alpha:1] setStroke]; slot.lineWidth = 2; [slot stroke];
    [[NSColor blackColor] setFill]; NSRectFill(NSMakeRect(kFloppy.origin.x + 30, kFloppy.origin.y + 70, 28, 330));
    [[NSColor colorWithCalibratedWhite:0.35 alpha:1] setFill]; NSRectFill(NSMakeRect(kFloppy.origin.x + 62, kFloppy.origin.y + 32, 14, 56));
}

// MARK: mouse

- (const EDBtn *)buttonAt:(NSPoint)d {
    for (int i = 0; i < kButtonCount; i++) if (NSPointInRect(d, NSInsetRect(btnRect(&kButtons[i]), -4, -4))) return &kButtons[i];
    return NULL;
}
- (BOOL)onWheel:(NSPoint)d { CGFloat dx = d.x - kWheelCenter.x, dy = d.y - kWheelCenter.y; return dx * dx + dy * dy <= kWheelRadius * kWheelRadius; }
- (CGFloat)angleAt:(NSPoint)d { return atan2(d.y - kWheelCenter.y, d.x - kWheelCenter.x); }

- (void)mouseDown:(NSEvent *)e {
    [self.window makeFirstResponder:self];
    NSPoint d = [self designPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    const EDBtn *b = [self buttonAt:d];
    if (b) { _down = [NSString stringWithUTF8String:b->key]; [self setNeedsDisplay:YES]; if (self.pressed) self.pressed(_down); return; }
    if ([self onWheel:d]) { _dragWheel = YES; _lastAngle = [self angleAt:d]; _wheelAcc = 0; return; }
    if (NSPointInRect(d, kFloppy)) { if (self.pressed) self.pressed(@"floppy"); return; }
}
- (void)mouseDragged:(NSEvent *)e {
    if (!_dragWheel) return;
    NSPoint d = [self designPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    CGFloat a = [self angleAt:d], da = a - _lastAngle;
    while (da > M_PI) da -= 2 * M_PI; while (da < -M_PI) da += 2 * M_PI;
    _lastAngle = a; [self turnWheel:da];
}
- (void)mouseUp:(NSEvent *)e { _dragWheel = NO; if (_down) { _down = nil; [self setNeedsDisplay:YES]; } }
- (void)scrollWheel:(NSEvent *)e {
    CGFloat dy = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.012 : 0.12);
    [self turnWheel:-dy];
}
- (void)turnWheel:(CGFloat)rad {
    _wheelAngle += rad; _wheelAcc += rad;
    CGFloat step = 2 * M_PI / 14;
    while (_wheelAcc >= step) { _wheelAcc -= step; if (self.wheel) self.wheel(1); }
    while (_wheelAcc <= -step) { _wheelAcc += step; if (self.wheel) self.wheel(-1); }
    [self setNeedsDisplay:YES];
}

// MARK: keyboard (digits = keypad, arrows = cursor, return = ENTER, esc = CANCEL, space = DEMO)

- (void)keyDown:(NSEvent *)e {
    NSString *c = e.charactersIgnoringModifiers; if (!c.length) return;
    unichar u = [c characterAtIndex:0]; NSString *k = nil;
    if (u >= '0' && u <= '9') k = [NSString stringWithFormat:@"%c", (char)u];
    else if (u == NSUpArrowFunctionKey) k = @"up"; else if (u == NSDownArrowFunctionKey) k = @"down";
    else if (u == NSLeftArrowFunctionKey) k = @"left"; else if (u == NSRightArrowFunctionKey) k = @"right";
    else if (u == '\r' || u == 3) k = @"enter"; else if (u == 27) k = @"exit"; else if (u == ' ') k = @"audition";
    else if (u == '+' || u == '=') k = @"inc"; else if (u == '-') k = @"dec"; else if (u == '.') k = @".";
    if (k && self.pressed) self.pressed(k); else [super keyDown:e];
}

// MARK: drag and drop onto the floppy slot (or anywhere on the panel)

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)i { return [i.draggingPasteboard canReadObjectForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ? NSDragOperationCopy : NSDragOperationNone; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)i {
    NSArray *urls = [i.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls.count) return NO;
    if (self.dropped) self.dropped(urls.firstObject);
    return YES;
}
@end

// MARK: controller — modes, LCD content and the button map

typedef NS_ENUM(NSInteger, EDMode) { EDModeHome, EDModeSample, EDModeProgram, EDModeDisk, EDModeMaster };

@implementation EDFrontPanelController {
    __weak EDMainWindowController *_editor;
    EDFrontPanelView *_view;
    EDMode _mode;
    NSInteger _utilCursor;
    NSMutableString *_entry;
    NSString *_flash; NSTimer *_flashTimer;
}

- (instancetype)initWithEditor:(EDMainWindowController *)editor {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1188, 354)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    w.title = @"EMU3 Editor — Front Panel"; w.releasedWhenClosed = NO;
    w.minSize = NSMakeSize(792, 236); w.contentAspectRatio = NSMakeSize(kDesign.width, kDesign.height);
    [w setFrameAutosaveName:@"EMU3EditorFrontPanel"];
    [EDTheme styleWindow:w];
    if ((self = [super initWithWindow:w])) {
        _editor = editor; _entry = [NSMutableString string];
        w.delegate = self;
        _view = [[EDFrontPanelView alloc] initWithFrame:w.contentView.bounds];
        _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        __weak EDFrontPanelController *weak = self;
        _view.lcd = ^NSDictionary *{ return [weak lcdContent]; };
        _view.pressed = ^(NSString *k) { [weak press:k]; };
        _view.wheel = ^(int n) { [weak step:n]; };
        _view.dropped = ^(NSURL *u) { [weak dropURL:u]; };
        [w.contentView addSubview:_view];
        _editor.onModelChange = ^{ [weak refreshLCD]; };
    }
    return self;
}
- (void)showPanel { [self showWindow:nil]; [self.window makeFirstResponder:_view]; [_view setNeedsDisplay:YES]; }
- (void)windowDidBecomeKey:(NSNotification *)n { [self.window makeFirstResponder:_view]; }

- (void)refreshLCD { [_view setNeedsDisplay:YES]; }
- (void)clearFlash { _flash = nil; [_view setNeedsDisplay:YES]; }
- (void)flash:(NSString *)s {
    _flash = s; [_flashTimer invalidate];
    __weak EDFrontPanelController *w = self;
    _flashTimer = [NSTimer scheduledTimerWithTimeInterval:2.5 repeats:NO block:^(NSTimer *t) { [w clearFlash]; }];
    [_view setNeedsDisplay:YES];
}

// ── LCD content per mode
- (NSDictionary *)lcdContent {
    EDMainWindowController *ed = _editor; EDBank *bank = ed.bank;
    NSString *bankName = bank ? (ed.bankTitle ?: @"Bank") : @"No Bank Loaded";
    NSString *note = _entry.length ? [NSString stringWithFormat:@"Go to #%@_", _entry] : _flash;
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary:@{@"header": bankName, @"note": note ?: @""}];
    switch (_mode) {
    case EDModeHome: {
        NSInteger pi = ed.selectedPresetIndex; EDPreset *p = (bank && pi >= 0 && pi < (NSInteger)bank.presets.count) ? bank.presets[pi] : nil;
        d[@"big"] = @YES; d[@"rows"] = @[p ? [NSString stringWithFormat:@"P%03u %@", p.number, p.name] : (bank ? @"(no presets)" : @"Open a bank")];
        d[@"soft"] = @[@"", @"", @"", @"", @"Open", @"Load"]; break; }
    case EDModeSample: {
        NSInteger n = bank.samples.count, cur = ed.selectedSampleIndex; NSMutableArray *rows = [NSMutableArray array];
        NSInteger first = MAX(0, MIN(cur - 1, n - 3)); if (n <= 3) first = 0;
        for (NSInteger i = first; i < MIN(first + 3, n); i++) { EDSample *s = bank.samples[i]; [rows addObject:[NSString stringWithFormat:@"S%03u %-16s %5u", s.number, s.name.UTF8String, s.sampleRate]]; }
        if (!n) [rows addObject:@"(no samples)"];
        d[@"rows"] = rows; d[@"cursor"] = @(cur); d[@"first"] = @(first);
        d[@"soft"] = @[@"Edit", @"Play", @"Export", @"Replace", @"SMDI", @"Dump"]; break; }
    case EDModeProgram: {
        NSInteger n = bank.presets.count, cur = ed.selectedPresetIndex; NSMutableArray *rows = [NSMutableArray array];
        NSInteger first = MAX(0, MIN(cur - 1, n - 3)); if (n <= 3) first = 0;
        for (NSInteger i = first; i < MIN(first + 3, n); i++) { EDPreset *p = bank.presets[i]; [rows addObject:[NSString stringWithFormat:@"P%03u %@", p.number, p.name]]; }
        if (!n) [rows addObject:@"(no presets)"];
        d[@"rows"] = rows; d[@"cursor"] = @(cur); d[@"first"] = @(first);
        d[@"soft"] = @[@"Edit", @"", @"", @"", @"", @""]; break; }
    case EDModeDisk:
        d[@"header"] = @"Disk"; d[@"rows"] = @[ed.diskTitle.length ? ed.diskTitle : @"(no disk image)", bank ? [NSString stringWithFormat:@"%lu samples  %lu presets", (unsigned long)bank.samples.count, (unsigned long)bank.presets.count] : @"", ed.statusText ?: @""];
        d[@"cursor"] = @(-1); d[@"first"] = @0; d[@"soft"] = @[@"Image", @"Bank", @"Save", @"Save As", @"", @""]; break;
    case EDModeMaster: {
        BOOL panel = ![NSUserDefaults.standardUserDefaults boolForKey:@"SkipFrontPanel"];
        NSArray *all = @[@"SMDI Transfer (SCSI)", @"MIDI Sample Dump", @"Sample to Sampler Disk", [NSString stringWithFormat:@"Start with front panel: %@", panel ? @"On" : @"Off"]];
        NSInteger first = MAX(0, MIN(_utilCursor - 1, (NSInteger)all.count - 3));
        d[@"header"] = @"Master"; d[@"rows"] = [all subarrayWithRange:NSMakeRange(first, 3)];
        d[@"cursor"] = @(_utilCursor); d[@"first"] = @(first); d[@"soft"] = @[@"SMDI", @"Dump", @"To Disk", @"Startup", @"", @""]; break; }
    }
    return d;
}

// ── buttons
- (void)setMode:(EDMode)m { _mode = m; [_entry setString:@""]; [_view setNeedsDisplay:YES]; }
- (void)press:(NSString *)k {
    EDMainWindowController *ed = _editor;
    if ([k isEqual:@"master"]) return [self setMode:EDModeMaster];
    if ([k isEqual:@"smanage"]) return [self setMode:EDModeSample];
    if ([k isEqual:@"pmanage"]) return [self setMode:EDModeProgram];
    if ([k isEqual:@"disk"]) return [self setMode:EDModeDisk];
    if ([k isEqual:@"sedit"]) return [ed showEditorTab:@"samples"];
    if ([k isEqual:@"pedit"]) return [ed showEditorTab:@"presets"];
    if ([k isEqual:@"audition"]) return [ed togglePlay:nil];
    if ([k isEqual:@"a1"]) return [ed smdiTransfer:nil];
    if ([k isEqual:@"a2"]) return [ed sdsTransfer:nil];
    if ([k isEqual:@"a3"]) return [ed saveBank:nil];
    if ([k isEqual:@"floppy"]) return [ed openDiskImage:nil];
    if ([k isEqual:@"pagenext"] || [k isEqual:@"right"]) return [self setMode:(_mode + 1) % (EDModeMaster + 1)];
    if ([k isEqual:@"pageprev"] || [k isEqual:@"left"]) return [self setMode:(_mode + EDModeMaster) % (EDModeMaster + 1)];
    if ([k isEqual:@"exit"]) { if (_entry.length) [_entry setString:@""]; else [self setMode:EDModeHome]; return [_view setNeedsDisplay:YES]; }
    if ([k isEqual:@"inc"] || [k isEqual:@"down"]) return [self step:1];
    if ([k isEqual:@"dec"] || [k isEqual:@"+/-"] || [k isEqual:@"up"]) return [self step:-1];
    if ([k isEqual:@"."]) return;
    if (k.length == 1 && [k characterAtIndex:0] >= '0' && [k characterAtIndex:0] <= '9') {
        if (_mode == EDModeSample || _mode == EDModeProgram) { if (_entry.length < 3) [_entry appendString:k]; [_view setNeedsDisplay:YES]; }
        return;
    }
    if ([k isEqual:@"enter"]) return [self enter];
    if (k.length == 2 && [k characterAtIndex:0] == 'f') return [self softKey:[k characterAtIndex:1] - '1'];
}

- (void)step:(int)n {
    EDMainWindowController *ed = _editor;
    if (_mode == EDModeSample && ed.bank.samples.count) [ed selectSampleAtIndex:MAX(0, MIN(ed.selectedSampleIndex + n, (NSInteger)ed.bank.samples.count - 1))];
    else if (_mode == EDModeProgram && ed.bank.presets.count) [ed selectPresetAtIndex:MAX(0, MIN(ed.selectedPresetIndex + n, (NSInteger)ed.bank.presets.count - 1))];
    else if (_mode == EDModeHome && ed.bank.presets.count) [ed selectPresetAtIndex:MAX(0, MIN(ed.selectedPresetIndex + n, (NSInteger)ed.bank.presets.count - 1))];
    else if (_mode == EDModeMaster) _utilCursor = MAX(0, MIN(_utilCursor + n, 3));
    [_view setNeedsDisplay:YES];
}

- (void)enter {
    EDMainWindowController *ed = _editor;
    if (_entry.length && (_mode == EDModeSample || _mode == EDModeProgram)) {
        NSInteger num = _entry.integerValue; [_entry setString:@""]; BOOL found = NO;
        if (_mode == EDModeSample) { for (NSUInteger i = 0; i < ed.bank.samples.count; i++) if (ed.bank.samples[i].number == num) { [ed selectSampleAtIndex:i]; found = YES; break; } }
        else for (NSUInteger i = 0; i < ed.bank.presets.count; i++) if (ed.bank.presets[i].number == num) { [ed selectPresetAtIndex:i]; found = YES; break; }
        if (!found) { NSBeep(); [self flash:[NSString stringWithFormat:@"No %@%03ld in this bank", _mode == EDModeSample ? @"S" : @"P", (long)num]]; }
        return [_view setNeedsDisplay:YES];
    }
    switch (_mode) {
        case EDModeHome: case EDModeSample: [ed showEditorTab:@"samples"]; break;
        case EDModeProgram: [ed showEditorTab:@"presets"]; break;
        case EDModeMaster: [self softKey:_utilCursor]; break;
        default: break;
    }
}

- (void)softKey:(int)i {
    EDMainWindowController *ed = _editor;
    switch (_mode) {
    case EDModeHome: if (i == 4 || i == 5) [ed openBankFile:nil]; break;
    case EDModeSample:
        switch (i) { case 0: [ed showEditorTab:@"samples"]; break; case 1: [ed togglePlay:nil]; break; case 2: [ed exportWAV:nil]; break;
                     case 3: [ed importWAV:nil]; break; case 4: [ed smdiTransfer:nil]; break; case 5: [ed sdsTransfer:nil]; break; } break;
    case EDModeProgram: if (i == 0) [ed showEditorTab:@"presets"]; break;
    case EDModeDisk: switch (i) { case 0: [ed openDiskImage:nil]; break; case 1: [ed openBankFile:nil]; break; case 2: [ed saveBank:nil]; break; case 3: [ed saveBankAs:nil]; break; } break;
    case EDModeMaster:
        switch (i) { case 0: [ed smdiTransfer:nil]; break; case 1: [ed sdsTransfer:nil]; break; case 2: [ed sendToSamplerDisk:nil]; break;
            case 3: { NSUserDefaults *u = NSUserDefaults.standardUserDefaults; [u setBool:![u boolForKey:@"SkipFrontPanel"] forKey:@"SkipFrontPanel"]; [_view setNeedsDisplay:YES]; break; } }
        break;
    default: break;
    }
}

- (void)dropURL:(NSURL *)u {
    if ([_editor openURL:u]) { [self setMode:EDModeHome]; [self flash:[@"Loaded " stringByAppendingString:u.lastPathComponent]]; }
}
@end
