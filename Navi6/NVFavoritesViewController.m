#import "NVFavoritesViewController.h"
#import "NVBrowserViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVFavorites.h"
#import "NVCells.h"
#import "NVPlayer.h"
#import "NVTheme.h"
#import "NVDownloadManager.h"

@implementation NVFavoritesViewController {
    UISegmentedControl *_seg;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) { self.title = @"Favorites"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    _seg = [[UISegmentedControl alloc] initWithItems:@[@"Songs", @"Albums", @"Artists"]];
    _seg.segmentedControlStyle = UISegmentedControlStyleBar;
    _seg.frame = CGRectMake(0, 0, 230, 30);
    _seg.selectedSegmentIndex = 0;
    [_seg addTarget:self action:@selector(segChanged) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _seg;
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:[NVFavorites shared] action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(changed) name:NVFavoritesChangedNotification object:nil];
    [nc addObserver:self selector:@selector(changed) name:NVPlayerChangedNotification object:nil];
    [nc addObserver:self selector:@selector(changed) name:NVDownloadsChangedNotification object:nil];
    [[NVFavorites shared] refresh];
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)changed { [self.refreshControl endRefreshing]; [self.tableView reloadData]; }
- (void)segChanged { [self.tableView reloadData]; }

- (NSArray *)items {
    NVFavorites *f = [NVFavorites shared];
    switch (_seg.selectedSegmentIndex) { case 0: return f.songs; case 1: return f.albums; default: return f.artists; }
}
- (NSInteger)off { return (_seg.selectedSegmentIndex == 0 && [self items].count) ? 1 : 0; }   // "Shuffle" row

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    NSUInteger n = [self items].count;
    return n ? (NSInteger)n + [self off] : 1;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (![self items].count) return 120;
    return ([self off] && ip.row == 0) ? 44 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *items = [self items];
    if (!items.count) return [NVCells messageCellForTableView:tv text:@"No favorites yet.\nOpen the cover in Now Playing and tap the star,\nor use a song's detail button."];
    if ([self off] && ip.row == 0) return [NVCells shuffleCellForTableView:tv count:items.count];
    NVItemType t = _seg.selectedSegmentIndex == 0 ? NVItemSong : (_seg.selectedSegmentIndex == 1 ? NVItemAlbum : NVItemArtist);
    return [NVCells cellForTableView:tv item:items[ip.row - [self off]] type:t];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSArray *items = [self items];
    if (!items.count) return;
    if ([self off] && ip.row == 0) { [[NVPlayer shared] playSongs:items startIndex:0 shuffled:YES]; [self nv_openNowPlaying]; return; }
    NSDictionary *it = items[ip.row - [self off]];
    NVBrowserViewController *next = nil;
    if (_seg.selectedSegmentIndex == 0) {
        [[NVPlayer shared] playSongs:items startIndex:ip.row - 1];
        [self nv_openNowPlaying];
        return;
    } else if (_seg.selectedSegmentIndex == 1) {
        next = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:it[@"id"] title:it[@"name"] ?: it[@"title"] coverArt:it[@"coverArt"]];
    } else {
        next = [[NVBrowserViewController alloc] initWithKind:NVBrowseArtistAlbums itemID:it[@"id"] title:it[@"name"] coverArt:it[@"coverArt"]];
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    NSArray *items = [self items];
    if (_seg.selectedSegmentIndex == 0 && ip.row >= 1 && ip.row - 1 < (NSInteger)items.count) [NVCells showActionsForSong:items[ip.row - 1]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return _seg.selectedSegmentIndex == 0 && [self items].count > 0 && ip.row >= 1;
}

- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return @"Unfavorite"; }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if (st == UITableViewCellEditingStyleDelete) [[NVFavorites shared] toggleSong:[self items][ip.row - 1]];
}

@end
