// EDBlueSCSIIni — "Write bluescsi.ini": makes the settings file for a BlueSCSI SD card and saves it on the card.
// Two presets: a stock BlueSCSI serving a disk image to an E-mu sampler (the settings that worked on the E6400), and the USB
// bridge board of this project (its USB block drive; ported from the EMU3 Disk Manager's configurator).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@interface EDBlueSCSIIni : NSObject
/// `imageURL`: the open disk image, used to pre-fill the bridge preset's size (may be nil). `status` gets the result text.
+ (void)runWithImage:(nullable NSURL *)imageURL status:(void (^)(NSString *text))status;
@end
NS_ASSUME_NONNULL_END
