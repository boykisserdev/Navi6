#import "NVDownloadManager.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"
#import "NVOffline.h"

static NSDictionary *NVCleanSong(NSDictionary *s) {
    NSMutableDictionary *o = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"id", @"title", @"artist", @"album", @"albumId", @"artistId", @"coverArt", @"genre",
                          @"suffix", @"duration", @"track", @"discNumber", @"year", @"size"]) {
        id v = s[k];
        if (v && v != [NSNull null]) o[k] = v;
    }
    return o;
}

static NSString *NVSafeName(NSString *s) {
    NSMutableString *o = [NSMutableString string];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        BOOL ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_';
        [o appendFormat:@"%C", (unichar)(ok ? c : '_')];
    }
    return o;
}

@interface NVDownloadTask : NSObject
@property (nonatomic, strong) NSDictionary *song;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic) long long received, expected;
@end
@implementation NVDownloadTask
@end

@interface NVDownloadManager () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSMutableDictionary *entries;
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, strong) NSMutableArray *active;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic) UIBackgroundTaskIdentifier bgTask;
@property (nonatomic) NSTimeInterval lastNotify;
@end

@implementation NVDownloadManager

+ (instancetype)shared {
    static NVDownloadManager *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [[NVDownloadManager alloc] init]; });
    return m;
}

- (id)init {
    self = [super init];
    if (self) {
        _queue = [NSMutableArray array];
        _active = [NSMutableArray array];
        _bgTask = UIBackgroundTaskInvalid;
        _entries = [NSMutableDictionary dictionaryWithContentsOfFile:[self libraryPath]] ?: [NSMutableDictionary dictionary];
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *k in [_entries allKeys]) {
            if (![fm fileExistsAtPath:[self pathForFile:_entries[k][@"file"]]]) [_entries removeObjectForKey:k];
        }
        for (NSString *f in [fm contentsOfDirectoryAtPath:NVMusicDirectory() error:nil]) {
            if ([f hasSuffix:@".part"]) [fm removeItemAtPath:[self pathForFile:f] error:nil];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kick) name:NVOfflineChangedNotification object:nil];
    }
    return self;
}

- (NSString *)libraryPath { return [NVMusicDirectory() stringByAppendingPathComponent:@"library.plist"]; }
- (NSString *)pathForFile:(NSString *)f { return [NVMusicDirectory() stringByAppendingPathComponent:f]; }
- (void)save { [self.entries writeToFile:[self libraryPath] atomically:YES]; }

- (NSArray *)pending {
    NSMutableArray *a = [NSMutableArray array];
    for (NVDownloadTask *t in self.active) [a addObject:t.song];
    [a addObjectsFromArray:self.queue];
    return a;
}
- (NSInteger)activeCount { return self.active.count; }
- (BOOL)isActive:(NSString *)sid {
    for (NVDownloadTask *t in self.active) if ([t.song[@"id"] isEqual:sid]) return YES;
    return NO;
}
- (BOOL)isPending:(NSString *)sid {
    if ([self isActive:sid]) return YES;
    for (NSDictionary *s in self.queue) if ([s[@"id"] isEqual:sid]) return YES;
    return NO;
}
- (float)progressForSongID:(NSString *)sid {
    for (NVDownloadTask *t in self.active) {
        if ([t.song[@"id"] isEqual:sid]) return t.expected > 0 ? MIN(0.99f, (float)t.received / (float)t.expected) : 0;
    }
    return 0;
}
- (BOOL)isDownloaded:(NSString *)sid { return sid && self.entries[sid] != nil; }
- (NSURL *)localURLForSongID:(NSString *)sid {
    NSDictionary *e = sid ? self.entries[sid] : nil;
    if (!e) return nil;
    NSString *p = [self pathForFile:e[@"file"]];
    return [[NSFileManager defaultManager] fileExistsAtPath:p] ? [NSURL fileURLWithPath:p] : nil;
}
- (NSArray *)downloadedSongs {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *e in [self.entries allValues]) [a addObject:e[@"song"]];
    [a sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        NSComparisonResult r = [[x[@"artist"] description] caseInsensitiveCompare:[y[@"artist"] description]];
        if (r) return r;
        r = [[x[@"album"] description] caseInsensitiveCompare:[y[@"album"] description]];
        if (r) return r;
        r = [x[@"discNumber"] compare:y[@"discNumber"] ?: @0];
        if (r) return r;
        return [x[@"track"] compare:y[@"track"] ?: @0];
    }];
    return a;
}
- (long long)totalBytes {
    long long t = 0;
    for (NSDictionary *e in [self.entries allValues]) t += [e[@"bytes"] longLongValue];
    return t;
}

- (void)enqueueSongs:(NSArray *)songs {
    if ([NVOffline shared].isOffline) {
        self.lastError = @"You\u2019re offline.";
        [self notifyChanged];
        return;
    }
    for (NSDictionary *s in songs) {
        NSString *sid = s[@"id"];
        if (!sid || [self isDownloaded:sid] || [self isPending:sid]) continue;
        [self.queue addObject:NVCleanSong(s)];
    }
    self.lastError = nil;
    [self notifyChanged];
    [self kick];
}

- (void)deleteSongID:(NSString *)sid {
    NSDictionary *e = self.entries[sid];
    if (!e) return;
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForFile:e[@"file"]] error:nil];
    [self.entries removeObjectForKey:sid];
    [self save];
    [self notifyChanged];
}

- (void)deleteAll {
    for (NSString *k in [self.entries allKeys]) {
        [[NSFileManager defaultManager] removeItemAtPath:[self pathForFile:self.entries[k][@"file"]] error:nil];
    }
    [self.entries removeAllObjects];
    [self save];
    [self notifyChanged];
}

- (void)cancelPending {
    for (NVDownloadTask *t in [self.active copy]) {
        [t.connection cancel]; t.connection = nil;
        [t.handle closeFile]; t.handle = nil;
        [[NSFileManager defaultManager] removeItemAtPath:[self partPathForSong:t.song] error:nil];
    }
    [self.active removeAllObjects];
    [self.queue removeAllObjects];
    [self endBackground];
    [self notifyChanged];
}

- (NSString *)partPathForSong:(NSDictionary *)s {
    return [self pathForFile:[NVSafeName(s[@"id"]) stringByAppendingString:@".part"]];
}

- (void)beginBackground {
    if (self.bgTask != UIBackgroundTaskInvalid) return;
    self.bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ [self endBackground]; }];
}
- (void)endBackground {
    if (self.bgTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:self.bgTask];
    self.bgTask = UIBackgroundTaskInvalid;
}

- (void)kick {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self kick]; }); return; }
    if ([NVOffline shared].isOffline) return;
    NSInteger limit = [NVSettings shared].maxConcurrentDownloads;
    BOOL started = NO;
    while ((NSInteger)self.active.count < limit && self.queue.count) {
        NSDictionary *song = self.queue[0];
        [self.queue removeObjectAtIndex:0];
        [self startSong:song];
        started = YES;
    }
    if (!self.active.count && !self.queue.count) [self endBackground];
    if (started) [self notifyChanged];
}

- (void)startSong:(NSDictionary *)song {
    NSURL *url = [[NVClient shared] streamURLForSong:song];
    if (!url) {
        self.lastError = @"Server is not configured.";
        [self.queue removeAllObjects];
        return;
    }
    [self beginBackground];
    NSString *part = [self partPathForSong:song];
    [[NSFileManager defaultManager] createFileAtPath:part contents:nil attributes:nil];
    NVDownloadTask *t = [[NVDownloadTask alloc] init];
    t.song = song;
    t.handle = [NSFileHandle fileHandleForWritingAtPath:part];
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    t.connection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:NO];
    [t.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [self.active addObject:t];
    [t.connection start];
}

- (NVDownloadTask *)taskForConnection:(NSURLConnection *)c {
    for (NVDownloadTask *t in self.active) if (t.connection == c) return t;
    return nil;
}

- (void)failTask:(NVDownloadTask *)t message:(NSString *)msg {
    [t.connection cancel]; t.connection = nil;
    [t.handle closeFile]; t.handle = nil;
    [[NSFileManager defaultManager] removeItemAtPath:[self partPathForSong:t.song] error:nil];
    [self.active removeObject:t];
    self.lastError = msg;
    [self notifyChanged];
    [self kick];
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    NVDownloadTask *t = [self taskForConnection:c];
    if (!t) return;
    NSInteger code = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 200;
    NSString *mime = [[r MIMEType] lowercaseString] ?: @"";
    if (code >= 400 || [mime hasPrefix:@"text/"] || [mime rangeOfString:@"json"].location != NSNotFound
        || [mime rangeOfString:@"xml"].location != NSNotFound) {
        [self failTask:t message:@"Server refused the download."];
        return;
    }
    t.expected = [r expectedContentLength];
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    NVDownloadTask *t = [self taskForConnection:c];
    if (!t) return;
    [t.handle writeData:data];
    t.received += data.length;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastNotify > 0.3) {
        self.lastNotify = now;
        [[NSNotificationCenter defaultCenter] postNotificationName:NVDownloadProgressNotification object:nil];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    NVDownloadTask *t = [self taskForConnection:c];
    if (!t) return;
    [t.handle closeFile]; t.handle = nil; t.connection = nil;
    if (t.received == 0) { [self failTask:t message:@"Empty response."]; return; }
    NSDictionary *song = t.song;
    NSString *file = [NSString stringWithFormat:@"%@.%@", NVSafeName(song[@"id"]), [[NVClient shared] fileExtensionForSong:song]];
    NSString *dst = [self pathForFile:file];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dst error:nil];
    [fm moveItemAtPath:[self partPathForSong:song] toPath:dst error:nil];
    self.entries[song[@"id"]] = @{ @"song": song, @"file": file, @"bytes": @(t.received) };
    [self save];
    [NVImageLoader saveOfflineCover:song[@"coverArt"]];
    [self.active removeObject:t];
    [self notifyChanged];
    [self kick];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    NVDownloadTask *t = [self taskForConnection:c];
    if (t) [self failTask:t message:error.localizedDescription];
}

- (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:NVDownloadsChangedNotification object:nil];
}

@end
