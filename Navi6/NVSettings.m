#import "NVSettings.h"
#import <Security/Security.h>

NSString *NVMusicDirectory(void) {
    static NSString *dir; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        dir = [docs stringByAppendingPathComponent:@"Music"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"covers"]
                                  withIntermediateDirectories:YES attributes:nil error:nil];

        [[NSURL fileURLWithPath:dir] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    });
    return dir;
}

static NSDictionary *NVKeychainQuery(void) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: @"Navi6",
              (__bridge id)kSecAttrAccount: @"server" };
}

@implementation NVSettings

+ (instancetype)shared {
    static NVSettings *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[NVSettings alloc] init]; });
    return s;
}

- (NSString *)serverURL { return [[NSUserDefaults standardUserDefaults] stringForKey:@"serverURL"] ?: @""; }
- (void)setServerURL:(NSString *)v { [[NSUserDefaults standardUserDefaults] setObject:v ?: @"" forKey:@"serverURL"]; }
- (NSString *)username { return [[NSUserDefaults standardUserDefaults] stringForKey:@"username"] ?: @""; }
- (void)setUsername:(NSString *)v { [[NSUserDefaults standardUserDefaults] setObject:v ?: @"" forKey:@"username"]; }

- (NSInteger)transcodeBitrate {
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"transcodeBitrate"];
    return v ? v : 256;
}
- (void)setTranscodeBitrate:(NSInteger)v { [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"transcodeBitrate"]; }

static BOOL NVKeychainUsable(void) {
    static BOOL ok; static dispatch_once_t once;
    dispatch_once(&once, ^{ ok = [[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"] != nil; });
    return ok;
}

static NSString *NVKeychainGet(void) {
    if (!NVKeychainUsable()) return nil;
    NSMutableDictionary *q = [NVKeychainQuery() mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef res = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &res) == errSecSuccess && res) {
        NSData *d = (__bridge_transfer NSData *)res;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return nil;
}

- (NSString *)password {
    NSString *k = NVKeychainGet();
    if (k.length) return k;
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"passwordFallback"] ?: @"";
}

- (void)setPassword:(NSString *)p {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (NVKeychainUsable()) SecItemDelete((__bridge CFDictionaryRef)NVKeychainQuery());
    [d removeObjectForKey:@"passwordFallback"];
    if (!p.length) return;
    if (NVKeychainUsable()) {
        NSMutableDictionary *q = [NVKeychainQuery() mutableCopy];
        q[(__bridge id)kSecValueData] = [p dataUsingEncoding:NSUTF8StringEncoding];
        SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    }
    if (![NVKeychainGet() isEqualToString:p]) [d setObject:p forKey:@"passwordFallback"];
}

- (NSInteger)maxConcurrentDownloads {
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxConcurrentDownloads"];
    return (v >= 1 && v <= 3) ? v : 1;
}
- (void)setMaxConcurrentDownloads:(NSInteger)v { [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"maxConcurrentDownloads"]; }
- (NSInteger)lyricsSource { return [[NSUserDefaults standardUserDefaults] integerForKey:@"lyricsSource"]; }
- (void)setLyricsSource:(NSInteger)v { [[NSUserDefaults standardUserDefaults] setInteger:v forKey:@"lyricsSource"]; }
- (BOOL)offlineMode { return [[NSUserDefaults standardUserDefaults] boolForKey:@"offlineMode"]; }
- (void)setOfflineMode:(BOOL)v { [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"offlineMode"]; }

- (BOOL)isConfigured { return self.serverURL.length && self.username.length; }

@end
