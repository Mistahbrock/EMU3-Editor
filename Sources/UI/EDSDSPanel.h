// EDSDSPanel — window for MIDI Sample Dump transfers of the selected sample.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDSDS.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDSDSPanel : NSWindowController
/// The sample to send (sdsRepresentation) — nil disables sending.
@property (nonatomic, copy, nullable) EDSDSSample * (^currentSample)(void);
/// Called on the main thread with a received sample; the host replaces the selected sample's audio.
@property (nonatomic, copy, nullable) void (^received)(EDSDSSample *sample);
- (void)present;
@end
NS_ASSUME_NONNULL_END
