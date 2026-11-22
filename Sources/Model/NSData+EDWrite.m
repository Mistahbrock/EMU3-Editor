#import "NSData+EDWrite.h"
#import <sys/mount.h>

@implementation NSData (EDWrite)
- (BOOL)ed_writeToURL:(NSURL *)url error:(NSError **)error {
    BOOL onNFS = NO;
    struct statfs fs;
    NSString *dir = url.URLByDeletingLastPathComponent.path;
    if (dir.length && statfs(dir.fileSystemRepresentation, &fs) == 0) onNFS = strcmp(fs.f_fstypename, "nfs") == 0;
    return [self writeToURL:url options:onNFS ? 0 : NSDataWritingAtomic error:error];
}
@end
