#import "NVFavorites.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"
#import "NVOffline.h"
#import "NVCache.h"

enum { NVKindSong = 0, NVKindAlbum = 1, NVKindArtist = 2 };

@interface NVFavorites ()
@property (nonatomic, strong) NSArray *songs, *albums, *artists;
@property (nonatomic, strong) NSArray *idSets;
@end

@implementation NVFavorites

+ (instancetype)shared {
    static NVFavorites *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NVFavorites alloc] init]; });
    return f;
}

- (id)init {
    self = [super init];
    if (self) {
        NSDictionary *c = [NVCache loadKey:@"starred"];
        if ([c isKindOfClass:[NSDictionary class]]) {
            _songs = NVArray(c[@"song"]); _albums = NVArray(c[@"album"]); _artists = NVArray(c[@"artist"]);
        } else {
            _songs = @[]; _albums = @[]; _artists = @[];
        }
        [self rebuildIDs];
    }
    return self;
}

- (void)post { [[NSNotificationCenter defaultCenter] postNotificationName:NVFavoritesChangedNotification object:nil]; }

- (NSArray *)listForKind:(int)k { return k == NVKindSong ? self.songs : (k == NVKindAlbum ? self.albums : self.artists); }
- (void)setList:(NSArray *)a forKind:(int)k {
    if (k == NVKindSong) self.songs = a; else if (k == NVKindAlbum) self.albums = a; else self.artists = a;
}

- (void)rebuildIDs {
    NSMutableArray *sets = [NSMutableArray array];
    for (int k = 0; k < 3; k++) {
        NSMutableSet *s = [NSMutableSet set];
        for (NSDictionary *d in [self listForKind:k]) if (d[@"id"]) [s addObject:d[@"id"]];
        [sets addObject:s];
    }
    self.idSets = sets;
}

- (void)storeCache {
    [NVCache store:@{ @"song": self.songs, @"album": self.albums, @"artist": self.artists } key:@"starred"];
}

- (void)refresh {
    if (![NVSettings shared].isConfigured || [NVOffline shared].isOffline) { [self post]; return; }
    [[NVClient shared] request:@"getStarred2" params:@{} completion:^(NSDictionary *r, NSError *e) {
        if (!e) {
            NSDictionary *s = r[@"starred2"];
            self.songs = NVArray(s[@"song"]);
            self.albums = NVArray(s[@"album"]);
            self.artists = NVArray(s[@"artist"]);
            [self rebuildIDs];
            [self storeCache];
        }
        [self post];
    }];
}

- (BOOL)isStarredID:(NSString *)iid kind:(int)k { return iid && [self.idSets[k] containsObject:iid]; }
- (BOOL)isStarred:(NSString *)sid { return [self isStarredID:sid kind:NVKindSong]; }
- (BOOL)isAlbumStarred:(NSString *)aid { return [self isStarredID:aid kind:NVKindAlbum]; }
- (BOOL)isArtistStarred:(NSString *)aid { return [self isStarredID:aid kind:NVKindArtist]; }

- (void)apply:(NSDictionary *)item kind:(int)k star:(BOOL)star {
    NSString *iid = item[@"id"];
    NSMutableArray *a = [[self listForKind:k] mutableCopy];
    [a filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
        return ![d[@"id"] isEqual:iid];
    }]];
    if (star) [a insertObject:item atIndex:0];
    [self setList:a forKind:k];
    [self rebuildIDs];
    [self post];
}

- (void)toggleItem:(NSDictionary *)item kind:(int)k {
    NSString *iid = item[@"id"];
    if (!iid) return;
    if ([NVOffline shared].isOffline) { [[NVOffline shared] showOfflineAlert]; return; }
    BOOL star = ![self isStarredID:iid kind:k];
    [self apply:item kind:k star:star];
    NSString *key = k == NVKindSong ? @"id" : (k == NVKindAlbum ? @"albumId" : @"artistId");
    [[NVClient shared] request:(star ? @"star" : @"unstar") params:@{ key: iid } completion:^(NSDictionary *r, NSError *e) {
        if (e) [self apply:item kind:k star:!star];
        else [self storeCache];
    }];
}

- (void)toggleSong:(NSDictionary *)song     { [self toggleItem:song kind:NVKindSong]; }
- (void)toggleAlbum:(NSDictionary *)album   { [self toggleItem:album kind:NVKindAlbum]; }
- (void)toggleArtist:(NSDictionary *)artist { [self toggleItem:artist kind:NVKindArtist]; }

@end
