#import "NVCache.h"
#import "NVSettings.h"

static NSString *NVCachePath(NSString *key) {
    static NSString *dir; static dispatch_once_t once;
    dispatch_once(&once, ^{
        dir = [NVMusicDirectory() stringByAppendingPathComponent:@"cache"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < key.length; i++) {
        unichar c = [key characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_';
        [o appendFormat:@"%C", (unichar)(ok ? c : '_')];
    }
    return [dir stringByAppendingPathComponent:[o stringByAppendingString:@".json"]];
}

@implementation NVCache
+ (void)store:(id)obj key:(NSString *)key {
    if (!obj || ![NSJSONSerialization isValidJSONObject:obj]) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    [d writeToFile:NVCachePath(key) atomically:YES];
}
+ (id)loadKey:(NSString *)key {
    NSData *d = [NSData dataWithContentsOfFile:NVCachePath(key)];
    return d.length ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
}
@end
