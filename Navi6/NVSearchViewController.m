#import "NVSearchViewController.h"
#import "NVBrowserViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVCells.h"
#import "NVClient.h"
#import "NVPlayer.h"

@interface NVSearchViewController ()
@property (nonatomic, strong) UISearchBar *bar;
@property (nonatomic, strong) NSArray *groups;       // [{title, items, type}]
@property (nonatomic, copy) NSString *status;
@end

@implementation NVSearchViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) { self.title = @"Search"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    self.bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    self.bar.delegate = self;
    self.bar.placeholder = @"Artists, albums, songs";
    self.bar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tableView.tableHeaderView = self.bar;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.groups) [self.bar becomeFirstResponder];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)bar {
    [bar resignFirstResponder];
    NSString *q = bar.text;
    if (!q.length) return;
    self.status = @"Searching\u2026"; self.groups = nil; [self.tableView reloadData];
    [[NVClient shared] request:@"search3" params:@{ @"query": q, @"artistCount": @10, @"albumCount": @20, @"songCount": @50 }
                    completion:^(NSDictionary *r, NSError *e) {
        if (e) { self.status = e.localizedDescription; self.groups = nil; [self.tableView reloadData]; return; }
        NSDictionary *res = r[@"searchResult3"];
        NSMutableArray *g = [NSMutableArray array];
        NSArray *a = NVArray(res[@"artist"]), *al = NVArray(res[@"album"]), *s = NVArray(res[@"song"]);
        if (a.count)  [g addObject:@{ @"title": @"Artists", @"items": a,  @"type": @(NVItemArtist) }];
        if (al.count) [g addObject:@{ @"title": @"Albums",  @"items": al, @"type": @(NVItemAlbum) }];
        if (s.count)  [g addObject:@{ @"title": @"Songs",   @"items": s,  @"type": @(NVItemSong) }];
        self.groups = g;
        self.status = g.count ? nil : @"No results.";
        [self.tableView reloadData];
    }];
}

- (BOOL)empty { return self.groups.count == 0; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [self empty] ? 1 : (NSInteger)self.groups.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if ([self empty]) return self.status ? 1 : 0;
    return [self.groups[s][@"items"] count];
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return [self empty] ? nil : self.groups[s][@"title"]; }
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return [self empty] ? 80 : 52; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self empty]) return [NVCells messageCellForTableView:tv text:self.status];
    NSDictionary *g = self.groups[ip.section];
    return [NVCells cellForTableView:tv item:g[@"items"][ip.row] type:(NVItemType)[g[@"type"] integerValue]];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self empty]) return;
    NSDictionary *g = self.groups[ip.section];
    NSDictionary *it = g[@"items"][ip.row];
    NVItemType type = (NVItemType)[g[@"type"] integerValue];
    NVBrowserViewController *next = nil;
    if (type == NVItemArtist) {
        next = [[NVBrowserViewController alloc] initWithKind:NVBrowseArtistAlbums itemID:it[@"id"] title:it[@"name"] coverArt:it[@"coverArt"]];
    } else if (type == NVItemAlbum) {
        next = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:it[@"id"] title:it[@"name"] ?: it[@"title"] coverArt:it[@"coverArt"]];
    } else {
        [[NVPlayer shared] playSongs:g[@"items"] startIndex:ip.row];
        [self nv_openNowPlaying];
        return;
    }
    [self.navigationController pushViewController:next animated:YES];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    [NVCells showActionsForSong:self.groups[ip.section][@"items"][ip.row]];
}

@end
