#import <Foundation/Foundation.h>

@interface NVLyrics : NSObject

+ (void)fetchForSong:(NSDictionary *)song completion:(void (^)(NSArray *lines, NSArray *times, NSString *error))completion;
@end
