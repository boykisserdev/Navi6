#import "NVSettings.h"
#import <Security/Security.h>

NSString *NVMusicDirectory(void) {
    static NSString *dir; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        dir = [docs stringByAppendingPathComponent:@"Music"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"covers"]
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        // don't let iCloud/iTunes back up gigabytes of music
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

// Keychain needs entitlements. Unsigned / "fake-signed" builds on a jailbroken device (JailCoder etc.) can't use it:
// SecItemAdd fails and the password would silently come back empty, which the server reports as "wrong password".
// So: try the Keychain, verify it really round-trips, otherwise fall back to NSUserDefaults.
static NSString *NVKeychainGet(void) {
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
    SecItemDelete((__bridge CFDictionaryRef)NVKeychainQuery());
    [d removeObjectForKey:@"passwordFallback"];
    if (!p.length) return;
    NSMutableDictionary *q = [NVKeychainQuery() mutableCopy];
    q[(__bridge id)kSecValueData] = [p dataUsingEncoding:NSUTF8StringEncoding];
    SecItemAdd((__bridge CFDictionaryRef)q, NULL);
    if (![NVKeychainGet() isEqualToString:p]) [d setObject:p forKey:@"passwordFallback"];
}

- (BOOL)isConfigured { return self.serverURL.length && self.username.length; }

@end
