#import "NVDownloadManager.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"

static NSDictionary *NVCleanSong(NSDictionary *s) {   // plist-safe subset (no NSNull)
    NSMutableDictionary *o = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"id", @"title", @"artist", @"album", @"albumId", @"artistId", @"coverArt",
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

@interface NVDownloadManager () <NSURLConnectionDataDelegate>
@property (nonatomic, strong) NSMutableDictionary *entries;    // id -> {song, file, bytes}
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic, strong) NSURLConnection *connection;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic) long long received, expected;
@property (nonatomic) float currentProgress;
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
        _bgTask = UIBackgroundTaskInvalid;
        _entries = [NSMutableDictionary dictionaryWithContentsOfFile:[self libraryPath]] ?: [NSMutableDictionary dictionary];
        // drop entries whose files vanished, clean stale .part files
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *k in [_entries allKeys]) {
            if (![fm fileExistsAtPath:[self pathForFile:_entries[k][@"file"]]]) [_entries removeObjectForKey:k];
        }
        for (NSString *f in [fm contentsOfDirectoryAtPath:NVMusicDirectory() error:nil]) {
            if ([f hasSuffix:@".part"]) [fm removeItemAtPath:[self pathForFile:f] error:nil];
        }
    }
    return self;
}

- (NSString *)libraryPath { return [NVMusicDirectory() stringByAppendingPathComponent:@"library.plist"]; }
- (NSString *)pathForFile:(NSString *)f { return [NVMusicDirectory() stringByAppendingPathComponent:f]; }
- (void)save { [self.entries writeToFile:[self libraryPath] atomically:YES]; }

- (NSArray *)pending { return [self.queue copy]; }

#pragma mark Queries

- (BOOL)isDownloaded:(NSString *)sid { return sid && self.entries[sid] != nil; }
- (BOOL)isPending:(NSString *)sid {
    for (NSDictionary *s in self.queue) if ([s[@"id"] isEqual:sid]) return YES;
    return NO;
}
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

#pragma mark Mutations

- (void)enqueueSongs:(NSArray *)songs {
    for (NSDictionary *s in songs) {
        NSString *sid = s[@"id"];
        if (!sid || [self isDownloaded:sid] || [self isPending:sid]) continue;
        [self.queue addObject:NVCleanSong(s)];
    }
    self.lastError = nil;
    [self notifyChanged];
    [self startNext];
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
    [self.connection cancel]; self.connection = nil;
    [self.handle closeFile]; self.handle = nil;
    NSDictionary *cur = ([self.queue count] ? [self.queue objectAtIndex:0] : nil);
    if (cur) [[NSFileManager defaultManager] removeItemAtPath:[self partPathForSong:cur] error:nil];
    [self.queue removeAllObjects];
    [self endBackground];
    [self notifyChanged];
}

#pragma mark Download loop

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

- (void)startNext {
    if (self.connection) return;
    if (self.queue.count == 0) { [self endBackground]; return; }
    NSDictionary *song = self.queue[0];
    NSURL *url = [[NVClient shared] streamURLForSong:song];
    if (!url) {
        self.lastError = @"Server is not configured.";
        [self.queue removeAllObjects];
        [self notifyChanged];
        return;
    }
    [self beginBackground];
    NSString *part = [self partPathForSong:song];
    [[NSFileManager defaultManager] createFileAtPath:part contents:nil attributes:nil];
    self.handle = [NSFileHandle fileHandleForWritingAtPath:part];
    self.received = 0; self.expected = 0; self.currentProgress = 0;
    NSURLRequest *req = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    self.connection = [[NSURLConnection alloc] initWithRequest:req delegate:self startImmediately:NO];
    [self.connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];   // keep going while scrolling
    [self.connection start];
    [self notifyChanged];
}

- (void)failCurrent:(NSString *)msg {
    [self.connection cancel]; self.connection = nil;
    [self.handle closeFile]; self.handle = nil;
    NSDictionary *cur = ([self.queue count] ? [self.queue objectAtIndex:0] : nil);
    if (cur) {
        [[NSFileManager defaultManager] removeItemAtPath:[self partPathForSong:cur] error:nil];
        [self.queue removeObjectAtIndex:0];
    }
    self.lastError = msg;
    [self notifyChanged];
    [self startNext];
}

- (void)connection:(NSURLConnection *)c didReceiveResponse:(NSURLResponse *)r {
    NSInteger code = [r isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)r statusCode] : 200;
    NSString *mime = [[r MIMEType] lowercaseString] ?: @"";
    if (code >= 400 || [mime hasPrefix:@"text/"] || [mime rangeOfString:@"json"].location != NSNotFound
        || [mime rangeOfString:@"xml"].location != NSNotFound) {
        [self failCurrent:@"Server refused the download."];
        return;
    }
    self.expected = [r expectedContentLength];
}

- (void)connection:(NSURLConnection *)c didReceiveData:(NSData *)data {
    [self.handle writeData:data];
    self.received += data.length;
    self.currentProgress = self.expected > 0 ? MIN(0.99f, (float)self.received / (float)self.expected) : 0;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - self.lastNotify > 0.3) {
        self.lastNotify = now;
        [[NSNotificationCenter defaultCenter] postNotificationName:NVDownloadProgressNotification object:nil];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)c {
    [self.handle closeFile]; self.handle = nil;
    self.connection = nil;
    NSDictionary *song = ([self.queue count] ? [self.queue objectAtIndex:0] : nil);
    if (!song || self.received == 0) { [self failCurrent:@"Empty response."]; return; }
    NSString *file = [NSString stringWithFormat:@"%@.%@", NVSafeName(song[@"id"]), [[NVClient shared] fileExtensionForSong:song]];
    NSString *dst = [self pathForFile:file];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dst error:nil];
    [fm moveItemAtPath:[self partPathForSong:song] toPath:dst error:nil];
    self.entries[song[@"id"]] = @{ @"song": song, @"file": file, @"bytes": @(self.received) };
    [self save];
    [NVImageLoader saveOfflineCover:song[@"coverArt"]];
    [self.queue removeObjectAtIndex:0];
    [self notifyChanged];
    [self startNext];
}

- (void)connection:(NSURLConnection *)c didFailWithError:(NSError *)error {
    [self failCurrent:error.localizedDescription];
}

- (void)notifyChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:NVDownloadsChangedNotification object:nil];
}

@end
