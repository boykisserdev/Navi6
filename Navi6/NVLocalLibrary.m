#import "NVLocalLibrary.h"
#import "NVDownloadManager.h"

static NSString *NVS(id v) { return (v && v != [NSNull null]) ? [v description] : nil; }
static NSString *AlbumKey(NSDictionary *s) {
    NSString *a = NVS(s[@"albumId"]);
    return a ?: [@"album:" stringByAppendingString:(NVS(s[@"album"]) ?: @"")];
}
static NSString *ArtistKey(NSDictionary *s) {
    NSString *a = NVS(s[@"artistId"]);
    return a ?: [@"artist:" stringByAppendingString:(NVS(s[@"artist"]) ?: @"")];
}

@implementation NVLocalLibrary

+ (NSArray *)songs { return [[NVDownloadManager shared] downloadedSongs]; }

+ (NSArray *)albums {
    NSMutableDictionary *by = [NSMutableDictionary dictionary];
    for (NSDictionary *s in [self songs]) {
        NSString *k = AlbumKey(s);
        NSMutableDictionary *a = by[k];
        if (!a) {
            a = [NSMutableDictionary dictionary];
            a[@"id"] = k;
            a[@"name"] = NVS(s[@"album"]) ?: @"Unknown Album";
            a[@"artistKey"] = ArtistKey(s);
            if (NVS(s[@"artist"])) a[@"artist"] = NVS(s[@"artist"]);
            if (NVS(s[@"coverArt"])) a[@"coverArt"] = NVS(s[@"coverArt"]);
            if (s[@"year"]) a[@"year"] = s[@"year"];
            a[@"songCount"] = @0;
            by[k] = a;
        }
        a[@"songCount"] = @([a[@"songCount"] integerValue] + 1);
    }
    NSMutableArray *out = [[by allValues] mutableCopy];
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        NSComparisonResult r = [(NVS(x[@"artist"]) ?: @"") localizedCaseInsensitiveCompare:(NVS(y[@"artist"]) ?: @"")];
        return r ? r : [NVS(x[@"name"]) localizedCaseInsensitiveCompare:NVS(y[@"name"])];
    }];
    return out;
}

+ (NSArray *)artists {
    NSMutableDictionary *by = [NSMutableDictionary dictionary], *albumSets = [NSMutableDictionary dictionary];
    for (NSDictionary *s in [self songs]) {
        NSString *k = ArtistKey(s);
        NSMutableDictionary *a = by[k];
        if (!a) {
            a = [NSMutableDictionary dictionary];
            a[@"id"] = k;
            a[@"name"] = NVS(s[@"artist"]) ?: @"Unknown Artist";
            if (NVS(s[@"coverArt"])) a[@"coverArt"] = NVS(s[@"coverArt"]);
            by[k] = a; albumSets[k] = [NSMutableSet set];
        }
        [albumSets[k] addObject:AlbumKey(s)];
        a[@"albumCount"] = @([albumSets[k] count]);
    }
    return [[by allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        return [NVS(x[@"name"]) localizedCaseInsensitiveCompare:NVS(y[@"name"])];
    }];
}

+ (NSArray *)genres {
    NSMutableDictionary *songs = [NSMutableDictionary dictionary], *albums = [NSMutableDictionary dictionary];
    for (NSDictionary *s in [self songs]) {
        NSString *g = NVS(s[@"genre"]);
        if (!g.length) continue;
        songs[g] = @([songs[g] integerValue] + 1);
        if (!albums[g]) albums[g] = [NSMutableSet set];
        [albums[g] addObject:AlbumKey(s)];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *g in [[songs allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        [out addObject:@{ @"name": g, @"songCount": songs[g], @"albumCount": @([albums[g] count]) }];
    }
    return out;
}

+ (NSArray *)songsForAlbumID:(NSString *)albumID {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in [self songs]) if ([AlbumKey(s) isEqualToString:albumID]) [out addObject:s];
    return out;
}

+ (NSArray *)albumsForArtistID:(NSString *)artistID {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *a in [self albums]) if ([a[@"artistKey"] isEqualToString:artistID]) [out addObject:a];
    return out;
}

+ (NSArray *)albumsForGenre:(NSString *)genre {
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *s in [self songs]) if ([NVS(s[@"genre"]) isEqualToString:genre]) [keys addObject:AlbumKey(s)];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *a in [self albums]) if ([keys containsObject:a[@"id"]]) [out addObject:a];
    return out;
}

+ (NSArray *)songsFiltered:(NSString *)query {
    NSString *q = [query lowercaseString];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *s in [self songs]) {
        NSString *hay = [[NSString stringWithFormat:@"%@ %@ %@", NVS(s[@"title"]) ?: @"", NVS(s[@"artist"]) ?: @"", NVS(s[@"album"]) ?: @""] lowercaseString];
        if ([hay rangeOfString:q].location != NSNotFound) [out addObject:s];
    }
    return out;
}

+ (NSSet *)albumKeys {
    NSMutableSet *k = [NSMutableSet set];
    for (NSDictionary *s in [self songs]) [k addObject:AlbumKey(s)];
    return k;
}
+ (NSSet *)artistKeys {
    NSMutableSet *k = [NSMutableSet set];
    for (NSDictionary *s in [self songs]) [k addObject:ArtistKey(s)];
    return k;
}

@end
