// EDSMDIPanel — window for SMDI sample transfers over SCSI (BlueSCSI initiator board).
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
#import "EDSMDI.h"

NS_ASSUME_NONNULL_BEGIN
@interface EDSMDIPanel : NSWindowController
@property (nonatomic, copy, nullable) EDSDSSample * (^currentSample)(void);
@property (nonatomic, copy, nullable) void (^received)(EDSDSSample *sample, NSString *name);
@property (nonatomic, copy, nullable) void (^foundSampler)(void);
- (void)present;
- (void)presentAndFind;   // opens the panel and scans the SCSI bus for the sampler
@end
NS_ASSUME_NONNULL_END
