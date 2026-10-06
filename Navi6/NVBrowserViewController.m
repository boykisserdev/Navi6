#import "NVBrowserViewController.h"
#import "NVSearchViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVCells.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"
#import "NVPlayer.h"
#import "NVDownloadManager.h"

#define PAGE 500
#define MAX_SONGS 20000

static NSString *NVGroupLetter(NSString *title) {
    if (!title.length) return @"#";
    NSString *f = [[[title substringToIndex:1] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil] uppercaseString];
    unichar c = f.length ? [f characterAtIndex:0] : '#';
    return (c >= 'A' && c <= 'Z') ? [NSString stringWithCharacters:&c length:1] : @"#";
}

@interface NVBrowserViewController () <UISearchBarDelegate>
@property (nonatomic) NVBrowseKind kind;
@property (nonatomic) BOOL isRoot, loading, hasMore;
@property (nonatomic, copy) NSString *itemID, *coverID, *statusText;
@property (nonatomic, strong) NSMutableArray *rows;
@property (nonatomic, strong) NSArray *sectionTitles, *sectionRows;
@property (nonatomic) NSInteger generation;
@property (nonatomic, strong) UIBarButtonItem *downloadItem;
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

- (BOOL)isSongKind { return self.kind == NVBrowseAlbumSongs || self.kind == NVBrowsePlaylistSongs; }
- (BOOL)isSectioned { return self.kind == NVBrowseArtists || self.kind == NVBrowseSongs; }
- (NSInteger)secOff { return self.kind == NVBrowseSongs ? 1 : 0; }                         // Songs: section 0 = "Shuffle"
- (NSInteger)off { return ([self isSongKind] && self.rows.count) ? 1 : 0; }               // album/playlist: row 0 = "Shuffle"

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    if (self.isRoot) {   // like the stock Music app: search bar on top of the list, tapping it opens search
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
    [self updateDownloadButton];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)stateChanged { [self updateDownloadButton]; [self.tableView reloadData]; }

#pragma mark Loading

- (void)reload { [self loadFromOffset:0]; }

- (void)loadFromOffset:(NSInteger)offset {
    if (![NVSettings shared].isConfigured) {
        self.statusText = @"Set up your server:\nMore \u203A Settings";
        [self.refreshControl endRefreshing];
        [self.tableView reloadData];
        return;
    }
    self.loading = YES;
    NSInteger gen = ++self.generation;
    NSString *ep = nil;
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    switch (self.kind) {
        case NVBrowseArtists:        ep = @"getArtists"; break;
        case NVBrowseAlbums:         ep = @"getAlbumList2"; p[@"type"] = @"alphabeticalByArtist"; p[@"size"] = @(PAGE); p[@"offset"] = @(offset); break;
        case NVBrowsePlaylists:      ep = @"getPlaylists"; break;
        case NVBrowseArtistAlbums:   ep = @"getArtist";   p[@"id"] = self.itemID; break;
        case NVBrowseAlbumSongs:     ep = @"getAlbum";    p[@"id"] = self.itemID; break;
        case NVBrowsePlaylistSongs:  ep = @"getPlaylist"; p[@"id"] = self.itemID; break;
        case NVBrowseSongs:          // Navidrome returns the whole library for an empty search3 query
            ep = @"search3"; p[@"query"] = @""; p[@"artistCount"] = @0; p[@"albumCount"] = @0;
            p[@"songCount"] = @(PAGE); p[@"songOffset"] = @(offset); break;
    }
    [[NVClient shared] request:ep params:p completion:^(NSDictionary *r, NSError *err) {
        if (gen != self.generation) return;
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (err) {
            if (offset == 0) { self.rows = nil; self.sectionRows = nil; self.sectionTitles = nil; }
            self.statusText = [err.localizedDescription stringByAppendingString:@"\nPull down to retry.\nDownloaded music: More \u203A Downloads"];
            [self.tableView reloadData];
            return;
        }
        self.statusText = nil;
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
                list = NVArray(r[@"albumList2"][@"album"]);
                self.hasMore = list.count >= PAGE;
                break;
            case NVBrowseSongs:
                list = NVArray(r[@"searchResult3"][@"song"]);
                self.hasMore = list.count >= PAGE;
                if (offset == 0 && !list.count) self.statusText = @"The server returned no songs.\n(It may not support an empty search3 query.)";
                break;
            case NVBrowsePlaylists:     list = NVArray(r[@"playlists"][@"playlist"]); break;
            case NVBrowseArtistAlbums:  list = NVArray(r[@"artist"][@"album"]); break;
            case NVBrowseAlbumSongs:    list = NVArray(r[@"album"][@"song"]); break;
            case NVBrowsePlaylistSongs: list = NVArray(r[@"playlist"][@"entry"]); break;
        }
        if (list) {
            if (offset == 0 || !self.rows) self.rows = [list mutableCopy];
            else [self.rows addObjectsFromArray:list];
        }
        if (self.kind == NVBrowseSongs) {
            BOOL more = self.hasMore && self.rows.count < MAX_SONGS;
            if (offset == 0 || !more) [self rebuildSongSections];      // sort only on first and last page
            if (more) [self loadFromOffset:self.rows.count];
        }
        if ([self isSongKind]) { [self buildHeader]; [self updateDownloadButton]; }
        [self.tableView reloadData];
    }];
}

// Songs: sort A-Z (non-letters last) and split into letter sections for the index bar.
- (void)rebuildSongSections {
    [self.rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ta = [a[@"title"] description] ?: @"", *tb = [b[@"title"] description] ?: @"";
        BOOL ha = [NVGroupLetter(ta) isEqualToString:@"#"], hb = [NVGroupLetter(tb) isEqualToString:@"#"];
        if (ha != hb) return ha ? NSOrderedDescending : NSOrderedAscending;
        return [ta localizedCaseInsensitiveCompare:tb];
    }];
    NSMutableArray *titles = [NSMutableArray array], *secs = [NSMutableArray array];
    NSMutableArray *cur = nil; NSString *curLetter = nil;
    for (NSDictionary *s in self.rows) {
        NSString *l = NVGroupLetter([s[@"title"] description] ?: @"");
        if (![l isEqualToString:curLetter]) { curLetter = l; cur = [NSMutableArray array]; [titles addObject:l]; [secs addObject:cur]; }
        [cur addObject:s];
    }
    self.sectionTitles = titles; self.sectionRows = secs;
}

#pragma mark Header (album / playlist) and Download bar button

- (void)buildHeader {
    if (!self.rows.count) { self.tableView.tableHeaderView = nil; return; }
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
    NSString *cid = self.coverID ?: self.rows[0][@"coverArt"];
    [NVImageLoader loadCover:cid size:80 completion:^(UIImage *img) { if (img) art.image = img; }];

    NSTimeInterval total = 0;
    for (NSDictionary *s in self.rows) total += [s[@"duration"] doubleValue];
    NSString *artist = (self.kind == NVBrowseAlbumSongs) ? [self.rows[0][@"artist"] description] : @"Playlist";
    NSInteger mins = (NSInteger)round(total / 60);

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(104, 12, 206, 40)];
    t.backgroundColor = [UIColor clearColor]; t.font = [UIFont boldSystemFontOfSize:16]; t.numberOfLines = 2;
    t.text = self.title; t.shadowColor = [UIColor whiteColor]; t.shadowOffset = CGSizeMake(0, 1);
    [h addSubview:t];
    UILabel *a = [[UILabel alloc] initWithFrame:CGRectMake(104, 54, 206, 17)];
    a.backgroundColor = [UIColor clearColor]; a.font = [UIFont systemFontOfSize:13];
    a.textColor = [UIColor colorWithRed:.33 green:.35 blue:.40 alpha:1]; a.text = artist;
    a.shadowColor = [UIColor whiteColor]; a.shadowOffset = CGSizeMake(0, 1);
    [h addSubview:a];
    UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(104, 72, 206, 16)];
    m.backgroundColor = [UIColor clearColor]; m.font = [UIFont systemFontOfSize:12];
    m.textColor = [UIColor colorWithRed:.45 green:.47 blue:.52 alpha:1];
    m.text = [NSString stringWithFormat:@"%d song%@, %d minute%@", (int)self.rows.count, self.rows.count == 1 ? @"" : @"s", (int)mins, mins == 1 ? @"" : @"s"];
    m.shadowColor = [UIColor whiteColor]; m.shadowOffset = CGSizeMake(0, 1);
    [h addSubview:m];
    for (UIView *sv in h.subviews) if ([sv isKindOfClass:[UILabel class]]) sv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = h;
}

- (void)updateDownloadButton {
    if (![self isSongKind]) return;
    NVDownloadManager *dm = [NVDownloadManager shared];
    BOOL all = self.rows.count > 0, queued = NO;
    for (NSDictionary *s in self.rows) {
        if (![dm isDownloaded:s[@"id"]]) all = NO;
        if ([dm isPending:s[@"id"]]) queued = YES;
    }
    if (!self.downloadItem) {
        self.downloadItem = [[UIBarButtonItem alloc] initWithTitle:@"Download" style:UIBarButtonItemStyleBordered
                                                            target:self action:@selector(downloadAll)];
    }
    self.downloadItem.title = all ? @"Downloaded" : (queued ? @"Queued" : @"Download");
    self.downloadItem.enabled = !all && !queued && self.rows.count > 0;
    self.navigationItem.rightBarButtonItem = self.downloadItem;
}

- (void)downloadAll {
    [[NVDownloadManager shared] enqueueSongs:self.rows];
    [self updateDownloadButton];
}

#pragma mark Table

- (BOOL)isEmptyState { return [self isSectioned] ? self.sectionRows.count == 0 : self.rows.count == 0; }

- (NSDictionary *)itemAt:(NSIndexPath *)ip {
    if ([self isSectioned]) return self.sectionRows[ip.section - [self secOff]][ip.row];
    return self.rows[ip.row - [self off]];
}

- (NSInteger)flatSongIndex:(NSIndexPath *)ip {      // position of a Songs-tab row inside the sorted self.rows
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
    return self.kind == NVBrowseAlbumSongs ? 44 : 52;
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
        case NVBrowseArtistAlbums:  type = NVItemAlbum; break;
        case NVBrowsePlaylists:     type = NVItemPlaylist; break;
        case NVBrowseAlbumSongs:    type = NVItemSongNumbered; break;
        default:                    type = NVItemSong; break;
    }
    if (self.kind == NVBrowseAlbums && self.hasMore && !self.loading && ip.row == (NSInteger)self.rows.count - 5) {
        [self loadFromOffset:self.rows.count];
    }
    return [NVCells cellForTableView:tv item:[self itemAt:ip] type:type];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
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
        case NVBrowseArtistAlbums:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:it[@"id"] title:it[@"name"] ?: it[@"title"] coverArt:it[@"coverArt"]]; break;
        case NVBrowsePlaylists:
            next = [[NVBrowserViewController alloc] initWithKind:NVBrowsePlaylistSongs itemID:it[@"id"] title:it[@"name"] coverArt:it[@"coverArt"]]; break;
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

@end
