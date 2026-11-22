#import <Foundation/Foundation.h>
#import "EMU3Types.h"

@class EMU3File;

@interface EMU3Directory : NSObject

@property (nonatomic, copy)   NSString        *name;
@property (nonatomic, assign) uint8_t          entryId;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *blockList;  // up to 7 block indices

@property (nonatomic, strong) NSMutableArray<EMU3File *>       *files;
@property (nonatomic, strong) NSMutableArray<EMU3Directory *>  *subdirectories;
@property (nonatomic, weak)   EMU3Directory   *parent;

// Directory entry location (for modification)
@property (nonatomic, assign) NSInteger  dentryBlock;
@property (nonatomic, assign) NSInteger  dentryOffset;

- (NSUInteger)totalFileCount;
- (NSArray<EMU3File *> *)allFiles; // non-deleted files

@end
