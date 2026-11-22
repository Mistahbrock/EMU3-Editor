#import "EMU3Directory.h"
#import "EMU3File.h"

@implementation EMU3Directory

- (instancetype)init {
    self = [super init];
    if (self) {
        _blockList      = [NSMutableArray array];
        _files          = [NSMutableArray array];
        _subdirectories = [NSMutableArray array];
    }
    return self;
}

- (NSArray<EMU3File *> *)allFiles {
    NSMutableArray *result = [NSMutableArray array];
    for (EMU3File *f in self.files) {
        if (!f.isDeleted) [result addObject:f];
    }
    return result;
}

- (NSUInteger)totalFileCount {
    return self.allFiles.count;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<EMU3Directory: %@ (%lu files, %lu subdirs)>",
            self.name,
            (unsigned long)self.files.count,
            (unsigned long)self.subdirectories.count];
}

@end
