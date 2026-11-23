// EDSettings — the Settings window (⌘,): default folders for the file dialogs, sampler memory and auto-save, bank conversion offer.
// All values live in NSUserDefaults; the main window follows changes through NSUserDefaultsDidChangeNotification.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Cocoa/Cocoa.h>
NS_ASSUME_NONNULL_BEGIN
@interface EDSettings : NSObject
+ (void)show;
@end
NS_ASSUME_NONNULL_END
