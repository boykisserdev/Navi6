#import "NVLyrics.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVOffline.h"
#import "NVCache.h"

typedef void (^NVLyricsDone)(NSArray *lines, NSArray *times);

@implementation NVLyrics

+ (void)fetchForSong:(NSDictionary *)song completion:(void (^)(NSArray *, NSArray *, NSString *))completion {
    NSString *sid = song[@"id"];
    NSString *cacheKey = sid ? [@"lyrics_" stringByAppendingString:sid] : nil;
    NSDictionary *cached = cacheKey ? [NVCache loadKey:cacheKey] : nil;
    if ([cached isKindOfClass:[NSDictionary class]] && [cached[@"lines"] count]) {
        NSArray *t = cached[@"times"];
        completion(cached[@"lines"], t.count ? t : nil, nil);
        return;
    }
    if ([NVOffline shared].isOffline) { completion(nil, nil, @"Lyrics need a connection (none saved for this song yet)."); return; }
    NSInteger src = [NVSettings shared].lyricsSource;
    NSArray *order = src == 0 ? @[@1, @2, @3] : @[@(src)];
    [self tryProviders:order index:0 song:song done:^(NSArray *lines, NSArray *times) {
        if (lines.count) {
            if (cacheKey) [NVCache store:@{ @"lines": lines, @"times": times ?: @[] } key:cacheKey];
            completion(lines, times, nil);
        } else {
            completion(nil, nil, @"No lyrics found.");
        }
    }];
}

+ (void)tryProviders:(NSArray *)order index:(NSUInteger)i song:(NSDictionary *)song done:(NVLyricsDone)done {
    if (i >= order.count) { done(nil, nil); return; }
    NVLyricsDone next = ^(NSArray *lines, NSArray *times) {
        if (lines.count) done(lines, times);
        else [self tryProviders:order index:i + 1 song:song done:done];
    };
    switch ([order[i] integerValue]) {
        case 1:  [self providerNavidrome:song done:next]; break;
        case 2:  [self providerLRCLIB:song done:next]; break;
        default: [self providerOVH:song done:next]; break;
    }
}

+ (void)providerNavidrome:(NSDictionary *)song done:(NVLyricsDone)done {
    [[NVClient shared] request:@"getLyricsBySongId" params:@{ @"id": song[@"id"] } completion:^(NSDictionary *r, NSError *e) {
        NSDictionary *best = nil;
        for (NSDictionary *l in (e ? @[] : NVArray(r[@"lyricsList"][@"structuredLyrics"]))) {
            if ([l[@"synced"] boolValue]) { best = l; break; }
            if (!best) best = l;
        }
        if (best) {
            BOOL synced = [best[@"synced"] boolValue];
            double off = [best[@"offset"] doubleValue];
            NSMutableArray *lines = [NSMutableArray array], *times = [NSMutableArray array];
            for (NSDictionary *ln in NVArray(best[@"line"])) {
                [lines addObject:[ln[@"value"] description] ?: @""];
                if (synced) [times addObject:@(([ln[@"start"] doubleValue] + off) / 1000.0)];
            }
            if (lines.count) { done(lines, synced ? times : nil); return; }
        }
        NSString *artist = song[@"artist"], *title = song[@"title"];
        if (!artist.length || !title.length) { done(nil, nil); return; }
        [[NVClient shared] request:@"getLyrics" params:@{ @"artist": artist, @"title": title } completion:^(NSDictionary *r2, NSError *e2) {
            done(e2 ? nil : [self splitPlain:[r2[@"lyrics"][@"value"] description]], nil);
        }];
    }];
}

+ (void)providerLRCLIB:(NSDictionary *)song done:(NVLyricsDone)done {
    NSString *artist = song[@"artist"], *title = song[@"title"];
    if (!title.length) { done(nil, nil); return; }
    NSMutableString *u = [NSMutableString stringWithFormat:@"https://lrclib.net/api/get?artist_name=%@&track_name=%@",
                          NVURLEscape(artist ?: @""), NVURLEscape(title)];
    if ([song[@"album"] length]) [u appendFormat:@"&album_name=%@", NVURLEscape([song[@"album"] description])];
    if ([song[@"duration"] intValue] > 0) [u appendFormat:@"&duration=%d", [song[@"duration"] intValue]];
    [self getJSON:u done:^(NSDictionary *j) {
        NSString *synced = [j[@"syncedLyrics"] isKindOfClass:[NSString class]] ? j[@"syncedLyrics"] : nil;
        if (synced.length) {
            NSArray *lines = nil, *times = nil;
            [self parseLRC:synced lines:&lines times:&times];
            if (lines.count) { done(lines, times); return; }
        }
        NSString *plain = [j[@"plainLyrics"] isKindOfClass:[NSString class]] ? j[@"plainLyrics"] : nil;
        done([self splitPlain:plain], nil);
    }];
}

+ (void)providerOVH:(NSDictionary *)song done:(NVLyricsDone)done {
    NSString *artist = song[@"artist"], *title = song[@"title"];
    if (!artist.length || !title.length) { done(nil, nil); return; }
    NSString *u = [NSString stringWithFormat:@"https://api.lyrics.ovh/v1/%@/%@", NVURLEscape(artist), NVURLEscape(title)];
    [self getJSON:u done:^(NSDictionary *j) {
        done([self splitPlain:[j[@"lyrics"] isKindOfClass:[NSString class]] ? j[@"lyrics"] : nil], nil);
    }];
}

+ (void)getJSON:(NSString *)url done:(void (^)(NSDictionary *json))done {
    static NSOperationQueue *q; static dispatch_once_t once;
    dispatch_once(&once, ^{ q = [[NSOperationQueue alloc] init]; });
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
    [req setValue:@"Navi6/1.0 (iOS 6)" forHTTPHeaderField:@"User-Agent"];
    [NSURLConnection sendAsynchronousRequest:req queue:q completionHandler:^(NSURLResponse *resp, NSData *data, NSError *err) {
        id j = (!err && data.length) ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done([j isKindOfClass:[NSDictionary class]] ? j : nil); });
    }];
}

+ (NSArray *)splitPlain:(NSString *)text {
    if (!text.length) return nil;
    NSMutableArray *lines = [[[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"] mutableCopy];
    while (lines.count && ![[lines lastObject] length]) [lines removeLastObject];
    return lines.count ? lines : nil;
}

+ (void)parseLRC:(NSString *)lrc lines:(NSArray **)outLines times:(NSArray **)outTimes {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *raw in [lrc componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSMutableArray *stamps = [NSMutableArray array];
        while ([line hasPrefix:@"["]) {
            NSRange close = [line rangeOfString:@"]"];
            if (close.location == NSNotFound) break;
            NSArray *parts = [[line substringWithRange:NSMakeRange(1, close.location - 1)] componentsSeparatedByString:@":"];
            if (parts.count == 2 && [parts[0] length] && isdigit([parts[0] characterAtIndex:0])) {
                [stamps addObject:@([parts[0] doubleValue] * 60 + [parts[1] doubleValue])];
            }
            line = [line substringFromIndex:close.location + 1];
        }
        NSString *text = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        for (NSNumber *t in stamps) [items addObject:@[t, text]];
    }
    [items sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    NSMutableArray *lines = [NSMutableArray array], *times = [NSMutableArray array];
    for (NSArray *it in items) { [times addObject:it[0]]; [lines addObject:it[1]]; }
    *outLines = lines; *outTimes = times;
}

@end
