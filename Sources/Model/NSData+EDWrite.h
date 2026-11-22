// NSData+EDWrite — file writes that behave on the sampler disk mount.
// GPL-3.0-or-later, Copyright (C) 2026 Rhyno Audio.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface NSData (EDWrite)
/// Atomic write everywhere, except on an NFS volume (the sampler disk under ~/EMU3 Disks): there macOS' atomic save leaves
/// `._name.sb-…` temp files behind, so the file is overwritten in place instead.
- (BOOL)ed_writeToURL:(NSURL *)url error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
