#import "NVDownloadsViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVCells.h"
#import "NVDownloadManager.h"
#import "NVPlayer.h"
#import "NVTheme.h"

@implementation NVDownloadsViewController {
    NSArray *_songs;
}

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) { self.title = @"Downloads"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reload) name:NVDownloadsChangedNotification object:nil];
    [nc addObserver:self selector:@selector(progress) name:NVDownloadProgressNotification object:nil];
    [nc addObserver:self selector:@selector(reload) name:NVPlayerChangedNotification object:nil];
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reload { _songs = [[NVDownloadManager shared] downloadedSongs]; [self.tableView reloadData]; }

- (void)progress {
    if (![self hasPending]) return;
    UITableViewCell *c = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    ((UIProgressView *)[c viewWithTag:101]).progress = [NVDownloadManager shared].currentProgress;
}

- (BOOL)hasPending { return [NVDownloadManager shared].pending.count > 0; }
- (BOOL)isPendingSection:(NSInteger)s { return [self hasPending] && s == 0; }
- (NSInteger)off { return _songs.count ? 1 : 0; }      // "Shuffle" row at top of the songs section

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return [self hasPending] ? 2 : 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if ([self isPendingSection:s]) return [NVDownloadManager shared].pending.count;
    return _songs.count ? (NSInteger)_songs.count + 1 : 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return [self isPendingSection:s] ? @"Downloading" : nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if ([self isPendingSection:s] || !_songs.count) return nil;
    NSString *f = [NSString stringWithFormat:@"%d songs \u00B7 %@", (int)_songs.count, [NVTheme sizeString:[NVDownloadManager shared].totalBytes]];
    NSString *err = [NVDownloadManager shared].lastError;
    return err ? [f stringByAppendingFormat:@"\nLast error: %@", err] : f;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isPendingSection:ip.section]) return 66;
    if (!_songs.count) return 120;
    return ip.row == 0 ? 44 : 52;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isPendingSection:ip.section]) {
        UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"pend"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"pend"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
            pv.frame = CGRectMake(15, 52, 270, 9); pv.tag = 101;
            pv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [cell.contentView addSubview:pv];
        }
        NSDictionary *s = [NVDownloadManager shared].pending[ip.row];
        cell.textLabel.text = s[@"title"];
        cell.detailTextLabel.text = ip.row == 0 ? s[@"artist"] : [NSString stringWithFormat:@"%@ \u00B7 waiting", s[@"artist"] ?: @""];
        UIProgressView *pv = (UIProgressView *)[cell viewWithTag:101];
        pv.hidden = ip.row != 0;
        pv.progress = ip.row == 0 ? [NVDownloadManager shared].currentProgress : 0;
        return cell;
    }
    if (!_songs.count) return [NVCells messageCellForTableView:tv text:@"No downloaded music yet.\nOpen an album and tap Download."];
    if (ip.row == 0) return [NVCells shuffleCellForTableView:tv count:_songs.count];
    return [NVCells cellForTableView:tv item:_songs[ip.row - 1] type:NVItemSong];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if ([self isPendingSection:ip.section] || !_songs.count) return;
    if (ip.row == 0) { [[NVPlayer shared] playSongs:_songs startIndex:0 shuffled:YES]; }
    else             { [[NVPlayer shared] playSongs:_songs startIndex:ip.row - 1]; }
    [self nv_openNowPlaying];
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    if (_songs.count && ![self isPendingSection:ip.section] && ip.row >= 1) [NVCells showActionsForSong:_songs[ip.row - 1]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    if ([self isPendingSection:ip.section]) return YES;
    return _songs.count > 0 && ip.row >= 1;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    if ([self isPendingSection:ip.section]) [[NVDownloadManager shared] cancelPending];
    else [[NVDownloadManager shared] deleteSongID:_songs[ip.row - 1][@"id"]];
}

@end
