// EDUtils — the sampler's Master > Utils screens as sheets: Assign Key, Channel Volume and Tones. GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDUtils : NSObject
+ (void)showAssignKeysIn:(NSWindow *)window;
+ (void)showChannelVolumeIn:(NSWindow *)window;
+ (void)showTonesIn:(NSWindow *)window;
@end
NS_ASSUME_NONNULL_END
