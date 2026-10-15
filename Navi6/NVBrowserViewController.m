#import "NVBrowserViewController.h"
#import "NVSearchViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVCells.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"
#import "NVPlayer.h"
#import "NVDownloadManager.h"
#import "NVFavorites.h"
#import "NVOffline.h"
#import "NVLocalLibrary.h"
#import "NVCache.h"
#import "NVPlaylists.h"
#import "NVShare.h"
#import "NVLog.h"
#import "NVImageViewerController.h"

#define PAGE 500

#define MAX_SONGS ([NSProcessInfo processInfo].physicalMemory < 400u * 1024u * 1024u ? 6000u : 20000u)

static NSString *NVStr(id v) { return (v && v != [NSNull null]) ? [v description] : @""; }

static NSString *NVGroupLetter(NSString *title) {
    if (!title.length) return @"#";
    NSString *f = [[[title substringToIndex:1] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil] uppercaseString];
    unichar c = f.length ? [f characterAtIndex:0] : '#';
    return (c >= 'A' && c <= 'Z') ? [NSString stringWithCharacters:&c length:1] : @"#";
}

static void NVSectionize(NSMutableArray *items, NSString *key, NSArray **outTitles, NSArray **outRows) {
    NSMutableArray *wrap = [NSMutableArray arrayWithCapacity:items.count];
    for (NSDictionary *it in items) {
        NSString *t = NVStr(it[key]);
        NSString *folded = [t stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
        [wrap addObject:@[NVGroupLetter(t), folded, it]];
    }
    [wrap sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
        BOOL ha = [a[0] isEqualToString:@"#"], hb = [b[0] isEqualToString:@"#"];
        if (ha != hb) return ha ? NSOrderedDescending : NSOrderedAscending;
        return [a[1] compare:b[1]];
    }];
    NSMutableArray *titles = [NSMutableArray array], *secs = [NSMutableArray array], *cur = nil;
    NSString *curLetter = nil;
    [items removeAllObjects];
    for (NSArray *w in wrap) {
        [items addObject:w[2]];
        NSString *l = w[0];
        if (![l isEqualToString:curLetter]) { curLetter = l; cur = [NSMutableArray array]; [titles addObject:l]; [secs addObject:cur]; }
        [cur addObject:w[2]];
    }
    *outTitles = titles; *outRows = secs;
}

@interface NVBrowserViewController () <UISearchBarDelegate, UIActionSheetDelegate>
@property (nonatomic) NVBrowseKind kind;
@property (nonatomic) BOOL isRoot, loading, hasMore, artistQueuing, artistQueued;
@property (nonatomic, copy) NSString *itemID, *coverID, *statusText;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSArray *sectionTitles, *sectionRows;
@property (nonatomic) NSInteger generation;
@property (nonatomic, strong) UIBarButtonItem *downloadItem, *cloudItem;
@property (nonatomic, strong) NVHeaderIconButton *headerStar;
@property (nonatomic, strong) NSIndexPath *pendingDeletePath;
@property (nonatomic) BOOL silentLoad, appearedOnce;
@property (nonatomic, copy) NSString *scanKey;
@property (nonatomic, strong) UIImageView *headerArt;
@end

@implementation NVBrowserViewController

- (id)initRootKind:(NVBrowseKind)kind {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _isRoot = YES; _kind = kind;
        switch (kind) {
            case NVBrowseArtists: self.title = @"Artists"; break;
            case NVBrowseAlbums:  self.title = @"Albums"; break;
            case NVBrowseSongs:   self.title = @"Songs"; break;
            case NVBrowseGenres:  self.title = @"Genres"; break;
            default:              self.title = @"Playlists"; break;
        }
    }
    return self;
}

- (id)initWithKind:(NVBrowseKind)kind itemID:(NSString *)itemID title:(NSString *)title coverArt:(NSString *)cover {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) { _kind = kind; _itemID = [itemID copy]; _coverID = [cover copy]; self.title = title; }
    return self;
}

- (BOOL)offline { return [NVOffline shared].isOffline; }
- (BOOL)isSongKind { return self.kind == NVBrowseAlbumSongs || self.kind == NVBrowsePlaylistSongs; }
- (BOOL)hasHeader { return [self isSongKind] || self.kind == NVBrowseArtistAlbums; }
- (BOOL)isSectioned { return self.kind == NVBrowseArtists || self.kind == NVBrowseSongs; }
- (NSInteger)secOff { return self.kind == NVBrowseSongs ? 1 : 0; }
- (NSInteger)off { return ([self isSongKind] && self.rows.count) ? 1 : 0; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    if (self.isRoot && self.kind != NVBrowseGenres) {
        UISearchBar *sb = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, MAX(320, self.tableView.bounds.size.width), 44)];
        sb.delegate = self;
        sb.placeholder = @"Search";
        self.tableView.tableHeaderView = sb;
        self.tableView.contentOffset = CGPointMake(0, 44);
    }
    [self reload];
}

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)bar {
    [self.navigationController pushViewController:[[NVSearchViewController alloc] init] animated:YES];
    return NO;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(stateChanged) name:NVPlayerChangedNotification object:nil];
    [nc addObserver:self selector:@selector(stateChanged) name:NVDownloadsChangedNotification object:nil];
    [nc addObserver:self selector:@selector(stateChanged) name:NVFavoritesChangedNotification object:nil];
    [nc addObserver:self selector:@selector(offlineChanged) name:NVOfflineChangedNotification object:nil];
    [nc addObserver:self selector:@selector(playlistsChanged) name:NVPlaylistsChangedNotification object:nil];
    [self updateBarItems];
    [self.tableView reloadData];
    NVLog(@"appear kind=%d", (int)self.kind);
    if (self.appearedOnce) [self silentRefresh];
    self.appearedOnce = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stateChanged { [self updateDownloadButton]; [self refreshHeaderStar]; [self.tableView reloadData]; }
- (void)offlineChanged { [self reload]; [self updateBarItems]; }
- (void)playlistsChanged { if (self.kind == NVBrowsePlaylists || self.kind == NVBrowsePlaylistSongs) [self reload]; }

- (void)reload { [self loadFromOffset:0]; }

- (void)loadOfflineData {
    self.generation++; self.loading = NO; self.hasMore = NO; self.statusText = nil;
    [self.refreshControl endRefreshing];
    NSString *empty = @"Nothing downloaded here.\nTurn off offline mode to see everything.";
    switch (self.kind) {
        case NVBrowseSongs:
            self.rows = [[NVLocalLibrary songs] mutableCopy];
            [self rebuildSongSections];
            break;
        case NVBrowseAlbums:       self.rows = [[NVLocalLibrary albums] mutableCopy]; break;
        case NVBrowseArtists: {
            NSMutableArray *a = [[NVLocalLibrary artists] mutableCopy];
            NSArray *t, *s; NVSectionize(a, @"name", &t, &s);
            self.sectionTitles = t; self.sectionRows = s;
            break;
        }
        case NVBrowsePlaylists: {
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *pl in NVArray([NVCache loadKey:@"playlists"])) {
                for (NSDictionary *s in NVArray([NVCache loadKey:[@"playlist_" stringByAppendingString:NVStr(pl[@"id"])]])) {
                    if ([[NVDownloadManager shared] isDownloaded:s[@"id"]]) { [out addObject:pl]; break; }
                }
            }
            self.rows = out;
            break;
        }
        case NVBrowseArtistAlbums: self.rows = [[NVLocalLibrary albumsForArtistID:self.itemID] mutableCopy]; break;
        case NVBrowseAlbumSongs:   self.rows = [[NVLocalLibrary songsForAlbumID:self.itemID] mutableCopy]; break;
        case NVBrowsePlaylistSongs: {
            NSMutableArray *out = [NSMutableArray array];
            for (NSDictionary *s in NVArray([NVCache loadKey:[@"playlist_" stringByAppendingString:self.itemID ?: @""]])) {
                if ([[NVDownloadManager shared] isDownloaded:s[@"id"]]) [out addObject:s];
            }
            self.rows = out;
            break;
        }
        case NVBrowseGenres:       self.rows = [[NVLocalLibrary genres] mutableCopy]; break;
        case NVBrowseGenreAlbums:  self.rows = [[NVLocalLibrary albumsForGenre:self.itemID] mutableCopy]; break;
    }
    if ([self isEmptyState]) self.statusText = empty;
    if ([self hasHeader]) [self buildHeader];
    [self.tableView reloadData];
}

- (void)loadFromOffset:(NSInteger)offset {
    BOOL silent = self.silentLoad;
    self.silentLoad = NO;
    if ([self offline]) { if (offset == 0) [self loadOfflineData]; return; }
    if (![NVSettings shared].isConfigured) {
        self.statusText = @"Set up your server:\nMore \u203A Settings";
        [self.refreshControl endRefreshing];
        [self.tableView reloadData];
        return;
    }
    self.loading = YES;
    NSInteger gen = ++self.generation;
    NVLog(@"load kind=%d offset=%d%@", (int)self.kind, (int)offset, silent ? @" silent" : @"");
    NSString *ep = nil;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    switch (self.kind) {
        case NVBrowseArtists:        ep = @"getArtists"; break;
        case NVBrowseAlbums:         ep = @"getAlbumList2"; p[@"type"] = @"alphabeticalByArtist"; p[@"size"] = @(PAGE); p[@"offset"] = @(offset); break;
        case NVBrowsePlaylists:      ep = @"getPlaylists"; break;
        case NVBrowseArtistAlbums:   ep = @"getArtist";   p[@"id"] = self.itemID; break;
        case NVBrowseAlbumSongs:     ep = @"getAlbum";    p[@"id"] = self.itemID; break;
        case NVBrowsePlaylistSongs:  ep = @"getPlaylist"; p[@"id"] = self.itemID; break;
        case NVBrowseGenres:         ep = @"getGenres"; break;
        case NVBrowseGenreAlbums:    ep = @"getAlbumList2"; p[@"type"] = @"byGenre"; p[@"genre"] = self.itemID ?: @""; p[@"size"] = @(PAGE); p[@"offset"] = @(offset); break;
        case NVBrowseSongs:
            ep = @"search3"; p[@"query"] = @""; p[@"artistCount"] = @0; p[@"albumCount"] = @0;
            p[@"songCount"] = @(PAGE); p[@"songOffset"] = @(offset); break;
    }
    [[NVClient shared] request:ep params:p completion:^(NSDictionary *r, NSError *err) {
        if (gen != self.generation) return;
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (err) {
            if (silent) return;
            if (offset == 0) { self.rows = nil; self.sectionRows = nil; self.sectionTitles = nil; }
            self.statusText = [err.localizedDescription stringByAppendingString:@"\nPull down to retry, or go offline to see your downloads."];
            [self.tableView reloadData];
            return;
        }
        self.statusText = nil;
        NSString *sigBefore = silent ? [self signature] : nil;
        NSArray *list = nil;
        switch (self.kind) {
            case NVBrowseArtists: {
                NSMutableArray *titles = [NSMutableArray array], *secs = [NSMutableArray array];
                for (NSDictionary *ix in NVArray(r[@"artists"][@"index"])) {
                    NSArray *a = NVArray(ix[@"artist"]);
                    if (!a.count) continue;
                    [titles addObject:ix[@"name"] ?: @"#"]; [secs addObject:a];
                }
                self.sectionTitles = titles; self.sectionRows = secs;
                break;
            }
            case NVBrowseAlbums:
            case NVBrowseGenreAlbums:
                list = NVArray(r[@"albumList2"][@"album"]);
                self.hasMore = list.count >= PAGE;
                break;
            case NVBrowseSongs:
                list = NVArray(r[@"searchResult3"][@"song"]);
                self.hasMore = list.count >= PAGE;
                if (offset == 0 && !list.count) self.statusText = @"The server returned no songs.\n(It may not support an empty search3 query.)";
                break;
            case NVBrowsePlaylists:
                list = NVArray(r[@"playlists"][@"playlist"]);
                [NVCache store:list key:@"playlists"];
                break;
            case NVBrowseArtistAlbums:  list = NVArray(r[@"artist"][@"album"]); break;
            case NVBrowseAlbumSongs:    list = NVArray(r[@"album"][@"song"]); break;
            case NVBrowsePlaylistSongs:
                list = NVArray(r[@"playlist"][@"entry"]);
                [NVCache store:list key:[@"playlist_" stringByAppendingString:self.itemID ?: @""]];
                break;
            case NVBrowseGenres: {
                NSMutableArray *g = [NSMutableArray array];
                for (NSDictionary *x in NVArray(r[@"genres"][@"genre"])) {
                    [g addObject:@{ @"name": NVStr(x[@"value"]), @"songCount": x[@"songCount"] ?: @0, @"albumCount": x[@"albumCount"] ?: @0 }];
                }
                list = g;
                break;
            }
        }
        if (list) {
            if (offset == 0 || !self.rows) self.rows = [list mutableCopy];
            else [self.rows addObjectsFromArray:list];
        }
        if (silent && [sigBefore isEqualToString:[self signature]]) return;
        NVLog(@"loaded kind=%d rows=%d", (int)self.kind, (int)self.rows.count);
        if (!silent && offset == 0 && [self isGated]) [self captureScanKey];
        if (self.kind == NVBrowseSongs) {
            BOOL more = self.hasMore && self.rows.count < MAX_SONGS;
            if (offset == 0 || !more) [self rebuildSongSections];
            if (more) [self loadFromOffset:self.rows.count];
        }
        if ([self hasHeader]) { [self buildHeader]; [self updateDownloadButton]; }
        [self.tableView reloadData];
    }];
}

- (void)rebuildSongSections {
    NVLog(@"sectionize %d songs", (int)self.rows.count);
    NSArray *t, *s;
    NVSectionize(self.rows, @"title", &t, &s);
    self.sectionTitles = t; self.sectionRows = s;
}

- (BOOL)isGated { return self.kind == NVBrowseSongs || self.kind == NVBrowseAlbums || self.kind == NVBrowseArtists; }

- (NSString *)signature {
    NSMutableString *s = [NSMutableString string];
    void (^add)(NSDictionary *) = ^(NSDictionary *d) {
        [s appendFormat:@"%@:%@:%@;", NVStr(d[@"id"]), NVStr(d[@"name"] ?: d[@"title"]), NVStr(d[@"songCount"])];
    };
    if ([self isSectioned]) { for (NSArray *sec in self.sectionRows) for (NSDictionary *d in sec) add(d); }
    else { for (NSDictionary *d in self.rows) add(d); }
    return [NSString stringWithFormat:@"%lu:%lu", (unsigned long)s.length, (unsigned long)s.hash];
}

- (void)silentRefresh {
    if ([self offline] || ![NVSettings shared].isConfigured || self.loading) return;
    if ([self isEmptyState]) { [self reload]; return; }
    if ([self isGated]) [self refreshIfLibraryChanged];
    else { self.silentLoad = YES; [self loadFromOffset:0]; }
}

- (void)captureScanKey {
    [[NVClient shared] request:@"getScanStatus" params:@{} completion:^(NSDictionary *r, NSError *e) {
        NSDictionary *st = r[@"scanStatus"];
        if (!e && st) self.scanKey = [NSString stringWithFormat:@"%@|%@", NVStr(st[@"count"]), NVStr(st[@"lastScan"])];
    }];
}

- (void)refreshIfLibraryChanged {
    [[NVClient shared] request:@"getScanStatus" params:@{} completion:^(NSDictionary *r, NSError *e) {
        NSDictionary *st = r[@"scanStatus"];
        if (e || !st) {
            if (self.kind == NVBrowseArtists && !self.loading) { self.silentLoad = YES; [self loadFromOffset:0]; }
            return;
        }
        NSString *key = [NSString stringWithFormat:@"%@|%@", NVStr(st[@"count"]), NVStr(st[@"lastScan"])];
        if (!self.scanKey) { self.scanKey = key; return; }
        if ([key isEqualToString:self.scanKey]) return;
        self.scanKey = key;
        if (!self.loading) [self loadFromOffset:0];
    }];
}

- (void)buildHeader {
    self.headerStar = nil;
    if (!self.rows.count && ![self hasHeader]) { self.tableView.tableHeaderView = nil; return; }
    BOOL artistKind = self.kind == NVBrowseArtistAlbums;
    NVHeaderView *h = [[NVHeaderView alloc] initWithFrame:CGRectMake(0, 0, MAX(320, self.tableView.bounds.size.width), 104)];
    h.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *bezel = [[UIView alloc] initWithFrame:CGRectMake(10, 10, 84, 84)];
    bezel.backgroundColor = [UIColor whiteColor];
    bezel.layer.shadowColor = [UIColor blackColor].CGColor;
    bezel.layer.shadowOpacity = .5; bezel.layer.shadowRadius = 3; bezel.layer.shadowOffset = CGSizeMake(0, 2);
    [h addSubview:bezel];
    UIImageView *art = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, 80, 80)];
    art.image = [NVTheme placeholder];
    art.contentMode = UIViewContentModeScaleAspectFill; art.clipsToBounds = YES;
    [h addSubview:art];
    self.headerArt = art;
    art.userInteractionEnabled = YES;
    [art addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(headerArtTapped)]];
    NSString *cid = self.coverID ?: (self.rows.count ? self.rows[0][@"coverArt"] : nil);
    if (cid) [NVImageLoader loadCover:cid size:80 completion:^(UIImage *img) { if (img) art.image = img; }];

    NSString *sub, *meta;
    if (artistKind) {
        sub = @"Artist";
        meta = [NSString stringWithFormat:@"%d album%@", (int)self.rows.count, self.rows.count == 1 ? @"" : @"s"];
    } else {
        NSTimeInterval total = 0;
        for (NSDictionary *s in self.rows) total += [s[@"duration"] doubleValue];
        NSInteger mins = (NSInteger)round(total / 60);
        sub = (self.kind == NVBrowseAlbumSongs && self.rows.count) ? NVStr(self.rows[0][@"artist"]) : @"Playlist";
        meta = [NSString stringWithFormat:@"%d song%@, %d minute%@", (int)self.rows.count, self.rows.count == 1 ? @"" : @"s", (int)mins, mins == 1 ? @"" : @"s"];
    }
    CGRect f[3] = { CGRectMake(104, 12, 150, 40), CGRectMake(104, 54, 150, 17), CGRectMake(104, 72, 150, 16) };
    UILabel *t = [[UILabel alloc] initWithFrame:f[0]];
    t.backgroundColor = [UIColor clearColor]; t.font = [UIFont boldSystemFontOfSize:16]; t.numberOfLines = 2;
    t.text = self.title; t.shadowColor = [UIColor whiteColor]; t.shadowOffset = CGSizeMake(0, 1);
    UILabel *a = [[UILabel alloc] initWithFrame:f[1]];
    a.backgroundColor = [UIColor clearColor]; a.font = [UIFont systemFontOfSize:13];
    a.textColor = [UIColor colorWithRed:.33 green:.35 blue:.40 alpha:1]; a.text = sub;
    a.shadowColor = [UIColor whiteColor]; a.shadowOffset = CGSizeMake(0, 1);
    UILabel *m = [[UILabel alloc] initWithFrame:f[2]];
    m.backgroundColor = [UIColor clearColor]; m.font = [UIFont systemFontOfSize:12];
    m.textColor = [UIColor colorWithRed:.45 green:.47 blue:.52 alpha:1]; m.text = meta;
    m.shadowColor = [UIColor whiteColor]; m.shadowOffset = CGSizeMake(0, 1);
    [h addSubview:t]; [h addSubview:a]; [h addSubview:m];

    CGFloat right = MAX(320, self.tableView.bounds.size.width);
    BOOL canStar = self.kind == NVBrowseAlbumSongs || artistKind;
    BOOL canShare = self.kind == NVBrowseAlbumSongs || self.kind == NVBrowsePlaylistSongs;
    if (canStar) {
        NVHeaderIconButton *st = [NVHeaderIconButton buttonWithIcon:NVHeaderIconStar];
        st.frame = CGRectMake(right - 88, 8, 40, 40);
        st.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [st addTarget:self action:@selector(headerStarTapped) forControlEvents:UIControlEventTouchUpInside];
        [h addSubview:st];
        self.headerStar = st;
    }
    if (canShare) {
        NVHeaderIconButton *sh = [NVHeaderIconButton buttonWithIcon:NVHeaderIconShare];
        sh.frame = CGRectMake(right - 46, 8, 40, 40);
        sh.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [sh addTarget:self action:@selector(headerShareTapped) forControlEvents:UIControlEventTouchUpInside];
        [h addSubview:sh];
    }
    self.tableView.tableHeaderView = h;
    [self refreshHeaderStar];
}

- (void)headerArtTapped {
    NSString *cid = self.coverID ?: (self.rows.count ? self.rows[0][@"coverArt"] : nil);
    if (cid.length) [NVImageViewerController presentCoverID:cid placeholder:self.headerArt.image title:self.title];
}

- (void)refreshHeaderStar {
    if (!self.headerStar) return;
    self.headerStar.on = self.kind == NVBrowseArtistAlbums ? [[NVFavorites shared] isArtistStarred:self.itemID]
                                                           : [[NVFavorites shared] isAlbumStarred:self.itemID];
}

- (void)headerStarTapped {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    if (self.itemID) d[@"id"] = self.itemID;
    if (self.title) d[@"name"] = self.title;
    if (self.coverID) d[@"coverArt"] = self.coverID;
    if (self.kind == NVBrowseArtistAlbums) { [[NVFavorites shared] toggleArtist:d]; return; }
    NSString *artist = self.rows.count ? NVStr(self.rows[0][@"artist"]) : nil;
    if (artist.length) d[@"artist"] = artist;
    [[NVFavorites shared] toggleAlbum:d];
}

- (void)headerShareTapped { [NVShare shareItemID:self.itemID title:self.title]; }

- (void)updateDownloadButton {
    if (![self isSongKind] && self.kind != NVBrowseArtistAlbums) return;
    if (!self.downloadItem) {
        self.downloadItem = [[UIBarButtonItem alloc] initWithTitle:@"Download" style:UIBarButtonItemStyleBordered
                                                            target:self action:@selector(downloadAll)];
    }
    if (self.kind == NVBrowseArtistAlbums) {
        self.downloadItem.title = self.artistQueuing ? @"Queuing\u2026" : (self.artistQueued ? @"Queued" : @"Download");
        self.downloadItem.enabled = !self.artistQueuing && !self.artistQueued && self.rows.count > 0;
        return;
    }
    NVDownloadManager *dm = [NVDownloadManager shared];
    BOOL all = self.rows.count > 0, queued = NO;
    for (NSDictionary *s in self.rows) {
        if (![dm isDownloaded:s[@"id"]]) all = NO;
        if ([dm isPending:s[@"id"]]) queued = YES;
    }
    self.downloadItem.title = all ? @"Downloaded" : (queued ? @"Queued" : @"Download");
    self.downloadItem.enabled = !all && !queued && self.rows.count > 0;
}

- (void)updateBarItems {
    if ([self offline]) {
        if (!self.cloudItem) self.cloudItem = [[NVOffline shared] cloudItem];
        self.navigationItem.rightBarButtonItem = self.cloudItem;
        return;
    }
    if ([self isSongKind] || self.kind == NVBrowseArtistAlbums) {
        [self updateDownloadButton];
        self.navigationItem.rightBarButtonItem = self.downloadItem;
    } else if (self.kind == NVBrowsePlaylists) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                                target:self action:@selector(newPlaylist)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)newPlaylist { NVLog(@"new playlist tapped"); [NVPlaylists promptCreateWithSongs:nil completion:nil]; }

- (void)downloadAll {
    if (self.kind != NVBrowseArtistAlbums) {
        [[NVDownloadManager shared] enqueueSongs:self.rows];
        [self updateDownloadButton];
        return;
    }

    self.artistQueuing = YES;
    [self updateDownloadButton];
    NSArray *albums = [self.rows copy];
    __block NSInteger remaining = albums.count;
    for (NSDictionary *al in albums) {
        [[NVClient shared] request:@"getAlbum" params:@{ @"id": al[@"id"] } completion:^(NSDictionary *r, NSError *e) {
            if (!e) [[NVDownloadManager shared] enqueueSongs:NVArray(r[@"album"][@"song"])];
            if (--remaining == 0) { self.artistQueuing = NO; self.artistQueued = YES; [self updateDownloadButton]; }
        }];
    }
}

- (BOOL)isEmptyState { return [self isSectioned] ? self.sectionRows.count == 0 : self.rows.count == 0; }

- (NSDictionary *)itemAt:(NSIndexPath *)ip {
    if ([self isSectioned]) return self.sectionRows[ip.section - [self secOff]][ip.row];
    return self.rows[ip.row - [self off]];
}

- (NSInteger)flatSongIndex:(NSIndexPath *)ip {
    NSInteger idx = 0;
    for (NSInteger s = 0; s < ip.section - 1; s++) idx += [self.sectionRows[s] count];
    return idx + ip.row;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return ([self isSectioned] && ![self isEmptyState]) ? (NSInteger)self.sectionRows.count + [self secOff] : 1;
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if ([self isEmptyState]) return 1;
    if (self.kind == NVBrowseSongs && s == 0) return 1;
    if ([self isSectioned]) return (NSInteger)[self.sectionRows[s - [self secOff]] count];
    return (NSInteger)self.rows.count + [self off];
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (![self isSectioned] || [self isEmptyState] || s < [self secOff]) return nil;
    return self.sectionTitles[s - [self secOff]];
}
- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tv {
    return ([self isSectioned] && ![self isEmptyState]) ? self.sectionTitles : nil;
}
- (NSInteger)tableView:(UITableView *)tv sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
    return index + [self secOff];
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isEmptyState]) return 120;
    if (self.kind == NVBrowseSongs && ip.section == 0) return 44;
    if ([self off] && ip.row == 0) return 44;
    return (self.kind == NVBrowseAlbumSongs || self.kind == NVBrowseGenres) ? 44 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isEmptyState]) {
        return [NVCells messageCellForTableView:tv text:self.statusText ?: (self.loading ? @"Loading\u2026" : @"Nothing here yet.")];
    }
    if ((self.kind == NVBrowseSongs && ip.section == 0) || ([self off] && ip.row == 0))
        return [NVCells shuffleCellForTableView:tv count:self.rows.count];
    NVItemType type;
    switch (self.kind) {
        case NVBrowseArtists:       type = NVItemArtist; break;
        case NVBrowseAlbums:
        case NVBrowseGenreAlbums:
        case NVBrowseArtistAlbums:  type = NVItemAlbum; break;
        case NVBrowsePlaylists:     type = NVItemPlaylist; break;
        case NVBrowseAlbumSongs:    type = NVItemSongNumbered; break;
        case NVBrowseGenres:        type = NVItemGenre; break;
        default:                    type = NVItemSong; break;
    }
    if ((self.kind == NVBrowseAlbums || self.kind == NVBrowseGenreAlbums) && self.hasMore && !self.loading && ip.row == (NSInteger)self.rows.count - 5) {
        [self loadFromOffset:self.rows.count];
    }
    return [NVCells cellForTableView:tv item:[self itemAt:ip] type:type];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NVLog(@"select kind=%d section=%d row=%d", (int)self.kind, (int)ip.section, (int)ip.row);
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self isEmptyState]) return;
    if ((self.kind == NVBrowseSongs && ip.section == 0) || ([self off] && ip.row == 0)) {
        [[NVPlayer shared] playSongs:self.rows startIndex:0 shuffled:YES];
        [self nv_openNowPlaying];
        return;
    }
    if (self.kind == NVBrowseSongs) {
        [[NVPlayer shared] playSongs:self.rows startIndex:[self flatSongIndex:ip]];
        [self nv_openNowPlaying];
        return;
    }
    NSDictionary *it = [self itemAt:ip];
    NVBrowserViewController *next = nil;
    switch (self.kind) {
        case NVBrowseArtists:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowseArtistAlbums itemID:it[@"id"] title:it[@"name"] coverArt:it[@"coverArt"]]; break;
        case NVBrowseAlbums:
        case NVBrowseGenreAlbums:
        case NVBrowseArtistAlbums:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:it[@"id"] title:it[@"name"] ?: it[@"title"] coverArt:it[@"coverArt"]]; break;
        case NVBrowsePlaylists:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowsePlaylistSongs itemID:it[@"id"] title:it[@"name"] coverArt:it[@"coverArt"]]; break;
        case NVBrowseGenres:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowseGenreAlbums itemID:it[@"name"] title:it[@"name"] coverArt:nil]; break;
        default:
            [[NVPlayer shared] playSongs:self.rows startIndex:ip.row - [self off]];
            [self nv_openNowPlaying];
            return;
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    if ((self.kind == NVBrowseSongs && ip.section == 0) || ([self off] && ip.row == 0)) return;
    [NVCells showActionsForSong:[self itemAt:ip]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    if ([self offline] || [self isEmptyState]) return NO;
    if (self.kind == NVBrowsePlaylists) return YES;
    return self.kind == NVBrowsePlaylistSongs && ip.row >= 1;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (self.kind == NVBrowsePlaylists) {
        self.pendingDeletePath = ip;
        NSString *name = NVStr(self.rows[ip.row][@"name"]);
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:[NSString stringWithFormat:@"Delete \u201C%@\u201D?", name] delegate:self
                                                  cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete Playlist" otherButtonTitles:nil];
        [sheet showInView:self.view.window];
    } else if (self.kind == NVBrowsePlaylistSongs) {
        NSInteger idx = ip.row - 1;
        [self.rows removeObjectAtIndex:idx];
        [self buildHeader];
        [self.tableView reloadData];
        [NVPlaylists removeIndex:idx fromPlaylistID:self.itemID completion:^(BOOL ok) { if (!ok) [self reload]; }];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i != sheet.destructiveButtonIndex || !self.pendingDeletePath) { self.pendingDeletePath = nil; return; }
    NSString *pid = self.rows[self.pendingDeletePath.row][@"id"];
    self.pendingDeletePath = nil;
    [NVPlaylists deletePlaylistID:pid completion:^(BOOL ok) {}];
}

@end
