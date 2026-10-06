#import "NVFavorites.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"

@interface NVFavorites ()
@property (nonatomic, strong) NSArray *songs, *albums, *artists;
@property (nonatomic, strong) NSMutableSet *ids;
@end

@implementation NVFavorites

+ (instancetype)shared {
    static NVFavorites *f; static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NVFavorites alloc] init]; });
    return f;
}

- (id)init {
    self = [super init];
    if (self) { _songs = @[]; _albums = @[]; _artists = @[]; _ids = [NSMutableSet set]; }
    return self;
}

- (void)post { [[NSNotificationCenter defaultCenter] postNotificationName:NVFavoritesChangedNotification object:nil]; }

- (void)refresh {
    if (![NVSettings shared].isConfigured) { [self post]; return; }
    [[NVClient shared] request:@"getStarred2" params:@{} completion:^(NSDictionary *r, NSError *e) {
        if (!e) {
            NSDictionary *s = r[@"starred2"];
            self.songs = NVArray(s[@"song"]);
            self.albums = NVArray(s[@"album"]);
            self.artists = NVArray(s[@"artist"]);
            NSMutableSet *ids = [NSMutableSet set];
            for (NSDictionary *d in self.songs) if (d[@"id"]) [ids addObject:d[@"id"]];
            self.ids = ids;
        }
        [self post];
    }];
}

- (BOOL)isStarred:(NSString *)sid { return sid && [self.ids containsObject:sid]; }

- (void)apply:(NSDictionary *)song star:(BOOL)star {
    NSString *sid = song[@"id"];
    NSMutableArray *a = [self.songs mutableCopy];
    [a filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *d, NSDictionary *b) {
        return ![d[@"id"] isEqual:sid];
    }]];
    if (star) { [self.ids addObject:sid]; [a insertObject:song atIndex:0]; }
    else      { [self.ids removeObject:sid]; }
    self.songs = a;
    [self post];
}

- (void)toggleSong:(NSDictionary *)song {
    NSString *sid = song[@"id"];
    if (!sid) return;
    BOOL star = ![self isStarred:sid];
    [self apply:song star:star];
    [[NVClient shared] request:(star ? @"star" : @"unstar") params:@{ @"id": sid } completion:^(NSDictionary *r, NSError *e) {
        if (e) [self apply:song star:!star];     // offline / server error -> roll back
    }];
}

@end
