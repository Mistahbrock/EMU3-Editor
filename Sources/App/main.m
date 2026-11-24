#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // keep the system's extra Edit-menu entries (Start Dictation, Emoji & Symbols, AutoFill) out of our menus
        [NSUserDefaults.standardUserDefaults registerDefaults:@{@"NSDisabledDictationMenuItem": @YES, @"NSDisabledCharacterPaletteMenuItem": @YES, @"NSAutoFillHeuristicControllerEnabled": @NO}];
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *d = [AppDelegate new];
        app.delegate = d;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
