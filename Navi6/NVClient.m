#import "NVClient.h"
#import "NVSettings.h"
#import "NVOffline.h"
#import "NVLog.h"
#import <CommonCrypto/CommonDigest.h>

NSArray *NVArray(id obj) {
    if ([obj isKindOfClass:[NSArray class]]) return obj;
    if ([obj isKindOfClass:[NSDictionary class]]) return @[obj];
    return @[];
}

static NSString *NVMD5(NSString *s) {
    const char *p = [s UTF8String];
    if (!p) p = "";
    unsigned char d[CC_MD5_DIGEST_LENGTH];
    CC_MD5(p, (CC_LONG)strlen(p), d);
    char hex[2 * CC_MD5_DIGEST_LENGTH + 1];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) snprintf(hex + i * 2, 3, "%02x", d[i]);
    return [NSString stringWithUTF8String:hex];
}

static NSString *NVEscape(NSString *s) {
    const char *u = [(s ?: @"") UTF8String];
    if (!u) return @"";
    size_t n = strlen(u), j = 0;
    char *out = (char *)malloc(n * 3 + 1);
    if (!out) return @"";
    static const char *hexd = "0123456789ABCDEF";
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)u[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            out[j++] = (char)c;
        } else {
            out[j++] = '%'; out[j++] = hexd[c >> 4]; out[j++] = hexd[c & 15];
        }
    }
    out[j] = 0;
    NSString *r = [NSString stringWithUTF8String:out];
    free(out);
    return r ?: @"";
}

static void NVAppendParam(NSMutableString *q, NSString *key, id value) {
    if (q.length) [q appendString:@"&"];
    [q appendString:NVEscape(key)];
    [q appendString:@"="];
    [q appendString:NVEscape([value description])];
}

NSString *NVURLEscape(NSString *s) { return NVEscape(s); }

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
    NSString *user = st.username;
    NSString *pass = st.password;
    if (!base || !user.length) return nil;
    NVLog(@"url: base ok");
    NSString *salt = [NSString stringWithFormat:@"%08x%08x", (unsigned int)arc4random(), (unsigned int)arc4random()];
    NSString *token = NVMD5([(pass ?: @"") stringByAppendingString:salt]);
    NVLog(@"url: token ok");
    NSMutableString *q = [NSMutableString string];
    NVAppendParam(q, @"u", user);
    NVAppendParam(q, @"t", token);
    NVAppendParam(q, @"s", salt);
    NVAppendParam(q, @"v", @"1.16.1");
    NVAppendParam(q, @"c", @"Navi6");
    NVAppendParam(q, @"f", @"json");
    for (NSString *k in params) {
        id v = [params objectForKey:k];
        if ([v isKindOfClass:[NSArray class]]) { for (id x in v) NVAppendParam(q, k, x); }
        else NVAppendParam(q, k, v);
    }
    NVLog(@"url: query ok");
    NSString *s = [NSString stringWithFormat:@"%@/rest/%@.view?%@", base, name, q];
    return [NSURL URLWithString:s];
}

- (void)request:(NSString *)endpoint params:(NSDictionary *)params
     completion:(void (^)(NSDictionary *, NSError *))completion {
    [self performRequest:endpoint params:params bypass:NO completion:completion];
}

- (void)performRequest:(NSString *)endpoint params:(NSDictionary *)params bypass:(BOOL)bypass
            completion:(void (^)(NSDictionary *, NSError *))completion {
    if (!bypass && [NVOffline shared].isOffline) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, NVError(@"You\u2019re offline.")); });
        return;
    }
    NVLog(@"req %@", endpoint);
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
        NVLog(@"res %@ %@", endpoint, outErr ? outErr.localizedDescription : @"ok");
        dispatch_async(dispatch_get_main_queue(), ^{ completion(root, outErr); });
    }];
}

- (void)ping:(void (^)(NSError *))completion {
    [self performRequest:@"ping" params:@{} bypass:YES completion:^(NSDictionary *r, NSError *e) { completion(e); }];
}

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
        if (raw) {
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(pt, pt), YES, 0);
            [raw drawInRect:CGRectMake(0, 0, pt, pt)];
            out = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            [sCache setObject:out forKey:key];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    }];
}

+ (void)loadFullCover:(NSString *)cid maxPixels:(int)px completion:(void (^)(UIImage *))completion {
    if (!cid.length) { completion(nil); return; }
    [sQueue addOperationWithBlock:^{
        NSString *disk = [sDiskDir stringByAppendingPathComponent:[NSString stringWithFormat:@"full_%@_%d.jpg", [self safe:cid], px]];
        UIImage *img = [UIImage imageWithContentsOfFile:disk];
        if (!img && ![NVOffline shared].isOffline) {
            NSURL *url = [[NVClient shared] URLForEndpoint:@"getCoverArt" params:@{ @"id": cid, @"size": @(px) }];
            if (url) {
                NSData *d = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20]
                                                  returningResponse:NULL error:NULL];
                img = d.length ? [UIImage imageWithData:d] : nil;
                if (img) [d writeToFile:disk atomically:YES];
            }
        }
        if (!img) img = [UIImage imageWithContentsOfFile:[self offlinePath:cid]];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(img); });
    }];
}

+ (void)clearMemoryCache { [sCache removeAllObjects]; }

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
