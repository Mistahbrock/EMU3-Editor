// EDEmuEgg — a small pixel-art emu that wanders over a panel (Shift+F7). A nod to the bird in the E-mu Emax II's hidden menu.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDEmuEgg : NSView
/// Adds the bird to `host`: it walks in from the right and wanders the whole panel, keeping clear of `rects` (other graphics, host coordinates,
/// origin bottom-left). Now and then it walks up to `mount` (the mount icon's rectangle) and pecks at it, then bolts before it opens.
/// `leftLimit` is the x it must not go left of. Any key or click makes it look around, get scared and run out. No-op while one is already running.
/// `done` is called when the bird has left the panel; `peckedMount` says whether it had been at the mount icon (the caller then opens it).
/// `peck` is called with YES each frame the beak hits the mount icon and NO when it lets go (so the icon can animate).
+ (void)playOver:(NSView *)host avoiding:(NSArray<NSValue *> *)rects mount:(NSRect)mount leftLimit:(CGFloat)left peck:(nullable void (^)(BOOL hit))peck done:(nullable void (^)(BOOL peckedMount))done;
@end
NS_ASSUME_NONNULL_END
