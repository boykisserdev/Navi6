#import "NVClient.h"
#import "NVSettings.h"
#import <CommonCrypto/CommonDigest.h>

NSArray *NVArray(id obj) {
    if ([obj isKindOfClass:[NSArray class]]) return obj;
    if ([obj isKindOfClass:[NSDictionary class]]) return @[obj];
    return @[];
}

static NSString *NVMD5(NSString *s) {
    const char *p = [s UTF8String];
    unsigned char d[CC_MD5_DIGEST_LENGTH];
    CC_MD5(p, (CC_LONG)strlen(p), d);
    NSMutableString *o = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) [o appendFormat:@"%02x", d[i]];
    return o;
}

static NSString *NVEscape(NSString *s) {
    return (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(
        NULL, (__bridge CFStringRef)s, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8);
}

static NSError *NVError(NSString *msg) {
    return [NSError errorWithDomain:@"Navi6" code:1 userInfo:@{ NSLocalizedDescriptionKey: msg }];
}

@implementation NVClient

+ (instancetype)shared {
    static NVClient *c; static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[NVClient alloc] init]; });
    return c;
}

- (NSString *)baseURLString {
    NSString *u = [[NVSettings shared].serverURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!u.length) return nil;
    if (![u hasPrefix:@"http://"] && ![u hasPrefix:@"https://"]) u = [@"http://" stringByAppendingString:u];
    while ([u hasSuffix:@"/"]) u = [u substringToIndex:u.length - 1];
    return u;
}

- (NSURL *)URLForEndpoint:(NSString *)name params:(NSDictionary *)params {
    NVSettings *st = [NVSettings shared];
    NSString *base = [self baseURLString];
    if (!base || !st.username.length) return nil;
    NSString *salt = [NSString stringWithFormat:@"%08x%08x", arc4random(), arc4random()];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary:@{
        @"u": st.username, @"t": NVMD5([st.password stringByAppendingString:salt]), @"s": salt,
        @"v": @"1.16.1", @"c": @"Navi6", @"f": @"json" }];
    [all addEntriesFromDictionary:params];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *k in all) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", NVEscape(k), NVEscape([all[k] description])]];
    }
    NSString *s = [NSString stringWithFormat:@"%@/rest/%@.view?%@", base, name, [parts componentsJoinedByString:@"&"]];
    return [NSURL URLWithString:s];
}

- (void)request:(NSString *)endpoint params:(NSDictionary *)params
     completion:(void (^)(NSDictionary *, NSError *))completion {
    NSURL *url = [self URLForEndpoint:endpoint params:params];
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, NVError(@"Server is not configured.")); });
        return;
    }
    static NSOperationQueue *q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = [[NSOperationQueue alloc] init]; q.maxConcurrentOperationCount = 4; });
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [NSURLConnection sendAsynchronousRequest:req queue:q completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        NSDictionary *root = nil; NSError *outErr = err;
        if (!err) {
            NSInteger code = [resp isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)resp statusCode] : 200;
            id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSDictionary *sr = [json isKindOfClass:[NSDictionary class]] ? json[@"subsonic-response"] : nil;
            if (![sr isKindOfClass:[NSDictionary class]]) {
                outErr = NVError(code >= 400 ? [NSString stringWithFormat:@"HTTP %d", (int)code] : @"Not a Subsonic/Navidrome server.");
            } else if (![sr[@"status"] isEqual:@"ok"]) {
                NSString *m = sr[@"error"][@"message"];
                outErr = NVError(m ?: @"Server error.");
            } else {
                root = sr;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(root, outErr); });
    }];
}

- (void)ping:(void (^)(NSError *))completion {
    [self request:@"ping" params:@{} completion:^(NSDictionary *r, NSError *e) { completion(e); }];
}

// iOS 6 AVPlayer plays these natively. Everything else (flac/ogg/opus/wma...) is transcoded to mp3 by the server.
- (BOOL)isNative:(NSString *)suffix {
    return [@[@"mp3", @"m4a", @"aac", @"alac", @"wav", @"aif", @"aiff", @"mp4", @"m4b"] containsObject:[suffix lowercaseString] ?: @""];
}

- (NSString *)fileExtensionForSong:(NSDictionary *)song {
    NSString *sfx = song[@"suffix"];
    return [self isNative:sfx] ? [sfx lowercaseString] : @"mp3";
}

- (NSURL *)streamURLForSong:(NSDictionary *)song {
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObject:song[@"id"] forKey:@"id"];
    if ([self isNative:song[@"suffix"]]) {
        p[@"format"] = @"raw";
    } else {
        p[@"format"] = @"mp3";
        p[@"maxBitRate"] = @([NVSettings shared].transcodeBitrate);
        p[@"estimateContentLength"] = @"true";
    }
    return [self URLForEndpoint:@"stream" params:p];
}

- (void)scrobbleSongID:(NSString *)songID submission:(BOOL)submission {
    if (!songID) return;
    [self request:@"scrobble" params:@{ @"id": songID, @"submission": submission ? @"true" : @"false",
                                        @"time": @((long long)([[NSDate date] timeIntervalSince1970] * 1000)) }
       completion:^(NSDictionary *r, NSError *e) {}];
}

@end


#pragma mark - Images

@implementation NVImageLoader

static NSCache *sCache; static NSOperationQueue *sQueue; static NSString *sDiskDir;

+ (void)initialize {
    if (self != [NVImageLoader class]) return;
    sCache = [[NSCache alloc] init]; sCache.countLimit = 200;
    sQueue = [[NSOperationQueue alloc] init]; sQueue.maxConcurrentOperationCount = 3;
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    sDiskDir = [caches stringByAppendingPathComponent:@"covers"];
    [[NSFileManager defaultManager] createDirectoryAtPath:sDiskDir withIntermediateDirectories:YES attributes:nil error:nil];
}

+ (NSString *)safe:(NSString *)s {
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_';
        [o appendFormat:@"%C", (unichar)(ok ? c : '_')];
    }
    return o;
}

+ (NSString *)offlinePath:(NSString *)cid {
    return [[NVMusicDirectory() stringByAppendingPathComponent:@"covers"] stringByAppendingPathComponent:[[self safe:cid] stringByAppendingString:@".jpg"]];
}

+ (void)loadCover:(NSString *)cid size:(CGFloat)pt completion:(void (^)(UIImage *))completion {
    if (!cid.length) { completion(nil); return; }
    NSString *key = [NSString stringWithFormat:@"%@@%d", cid, (int)pt];
    UIImage *hit = [sCache objectForKey:key];
    if (hit) { completion(hit); return; }
    int px = (int)(pt * [UIScreen mainScreen].scale);
    [sQueue addOperationWithBlock:^{
        UIImage *raw = [UIImage imageWithContentsOfFile:[self offlinePath:cid]];
        if (!raw) {
            NSString *disk = [sDiskDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%d.jpg", [self safe:cid], px]];
            raw = [UIImage imageWithContentsOfFile:disk];
            if (!raw) {
                NSURL *url = [[NVClient shared] URLForEndpoint:@"getCoverArt" params:@{ @"id": cid, @"size": @(px) }];
                if (url) {
                    NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:15]
                                                      returningResponse:NULL error:NULL];
                    raw = d.length ? [UIImage imageWithData:d] : nil;
                    if (raw) [d writeToFile:disk atomically:YES];
                }
            }
        }
        UIImage *out = nil;
        if (raw) {   // decode off the main thread so scrolling stays smooth
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(pt, pt), YES, 0);
            [raw drawInRect:CGRectMake(0, 0, pt, pt)];
            out = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            [sCache setObject:out forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    }];
}

+ (void)saveOfflineCover:(NSString *)cid {
    if (!cid.length) return;
    NSString *path = [self offlinePath:cid];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    [sQueue addOperationWithBlock:^{
        NSURL *url = [[NVClient shared] URLForEndpoint:@"getCoverArt" params:@{ @"id": cid, @"size": @600 }];
        if (!url) return;
        NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20]
                                          returningResponse:NULL error:NULL];
        if (d.length && [UIImage imageWithData:d]) [d writeToFile:path atomically:YES];
    }];
}

@end
