#import <Foundation/Foundation.h>

@interface NVCache : NSObject
+ (void)store:(id)jsonObject key:(NSString *)key;
+ (id)loadKey:(NSString *)key;
@end
