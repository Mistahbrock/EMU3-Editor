#import "EDHelp.h"
#import <WebKit/WebKit.h>

@interface EDHelp () <WKNavigationDelegate>
@end

@implementation EDHelp { NSWindow *_win; WKWebView *_web; }

+ (void)show {
    static EDHelp *h; if (!h) { h = [EDHelp new]; [h build]; }
    [h->_win makeKeyAndOrderFront:nil];
}
- (void)build {
    _web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 980, 720) configuration:[WKWebViewConfiguration new]];
    _web.navigationDelegate = self;
    NSURL *dir = [NSBundle.mainBundle URLForResource:@"Help" withExtension:nil], *page = [dir URLByAppendingPathComponent:@"index.html"];
    if (page && [NSFileManager.defaultManager fileExistsAtPath:page.path]) [_web loadFileURL:page allowingReadAccessToURL:dir];
    else [_web loadHTMLString:@"<body style='font:14px -apple-system;padding:30px'>The help pages are missing from this build.</body>" baseURL:nil];
    _win = [[NSWindow alloc] initWithContentRect:_web.frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    _win.title = @"EMU3 Editor Help"; _win.contentView = _web; _win.releasedWhenClosed = NO; _win.minSize = NSMakeSize(520, 400);
    [_win setFrameAutosaveName:@"EDHelpWindow"]; if (![_win setFrameUsingName:@"EDHelpWindow"]) [_win center];
}
// links inside the page stay in the window; web links open in the browser
- (void)webView:(WKWebView *)w decidePolicyForNavigationAction:(WKNavigationAction *)a decisionHandler:(void (^)(WKNavigationActionPolicy))h {
    NSURL *u = a.request.URL;
    if (a.navigationType == WKNavigationTypeLinkActivated && u.scheme.length && ![u.scheme isEqual:@"file"]) { [NSWorkspace.sharedWorkspace openURL:u]; h(WKNavigationActionPolicyCancel); return; }
    h(WKNavigationActionPolicyAllow);
}
@end
