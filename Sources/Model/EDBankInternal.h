// Internal access to EDSample / EDPreset state for the bank format readers. Not for the UI.
#import "EDBank.h"
@interface EDSample ()
@property (nonatomic, readwrite) NSUInteger chunkIndex;
@property (nonatomic, readwrite) BOOL dirty;
@end
@interface EDPreset ()
@property (nonatomic, readwrite) NSUInteger chunkIndex;
@property (nonatomic, readwrite) NSMutableData *raw;
@property (nonatomic, readwrite) BOOL dirty;
@end
