#import "NVCells.h"
#import "NVClient.h"
#import "NVTheme.h"
#import "NVPlayer.h"
#import "NVDownloadManager.h"
#import "NVFavorites.h"
#import "NVOffline.h"
#import "NVPlaylists.h"
#import "NVShare.h"

static NSString * const kAddToPlaylist = @"Add to Playlist\u2026";
static NSString * const kShare = @"Share\u2026";

@interface NVSongSheet : NSObject <UIActionSheetDelegate>
@property (nonatomic, strong) NSDictionary *song;
@end
static NVSongSheet *sCurrentSheet;

@implementation NVSongSheet
- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex) return;
    NSString *t = [sheet buttonTitleAtIndex:i];
    if ([t isEqualToString:@"Play Next"])             [[NVPlayer shared] addNext:self.song];
    else if ([t isEqualToString:@"Add to Queue"])     [[NVPlayer shared] addToQueue:self.song];
    else if ([t isEqualToString:@"Download"])         [[NVDownloadManager shared] enqueueSongs:@[self.song]];
    else if ([t isEqualToString:@"Remove Download"])  [[NVDownloadManager shared] deleteSongID:self.song[@"id"]];
    else if ([t isEqualToString:@"Favorite"] || [t isEqualToString:@"Unfavorite"]) [[NVFavorites shared] toggleSong:self.song];
    else if ([t isEqualToString:kAddToPlaylist])      [NVPlaylists presentPickerForSongs:@[self.song[@"id"]]];
    else if ([t isEqualToString:kShare])              [NVShare shareItemID:self.song[@"id"] title:self.song[@"title"]];
}
- (void)actionSheet:(UIActionSheet *)s didDismissWithButtonIndex:(NSInteger)i { sCurrentSheet = nil; }
@end

@implementation NVCells

+ (UITableViewCell *)messageCellForTableView:(UITableView *)tv text:(NSString *)text {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"msg"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"msg"];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor grayColor];
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.text = text;
    return cell;
}

+ (UITableViewCell *)shuffleCellForTableView:(UITableView *)tv count:(NSInteger)n {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"shuf"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"shuf"];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.imageView.image = [NVTheme shuffleRowIcon];
    }
    cell.textLabel.text = @"Shuffle";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%d song%@", (int)n, n == 1 ? @"" : @"s"];
    return cell;
}

+ (UITableViewCell *)cellForTableView:(UITableView *)tv item:(NSDictionary *)item type:(NVItemType)type {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"nv"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"nv"];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    }
    cell.textLabel.textColor = [UIColor blackColor];
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = nil;

    NSString *title = item[@"title"] ?: item[@"name"] ?: @"";
    NSString *detail = nil;
    BOOL cover = YES;
    NVFavorites *fav = [NVFavorites shared];

    switch (type) {
        case NVItemArtist: {
            title = item[@"name"] ?: @"";
            NSInteger n = [item[@"albumCount"] integerValue];
            detail = n ? [NSString stringWithFormat:@"%d album%@", (int)n, n == 1 ? @"" : @"s"] : nil;
            if ([fav isArtistStarred:item[@"id"]]) detail = [(detail ?: @"") stringByAppendingString:@" \u2605"];
            break;
        }
        case NVItemAlbum: {
            title = item[@"name"] ?: item[@"title"] ?: @"";
            NSString *year = [item[@"year"] description];
            detail = [item[@"artist"] description];
            if (year.length && ![year isEqualToString:@"0"]) detail = detail.length ? [NSString stringWithFormat:@"%@ \u00B7 %@", detail, year] : year;
            if ([fav isAlbumStarred:item[@"id"]]) detail = [(detail ?: @"") stringByAppendingString:@" \u2605"];
            break;
        }
        case NVItemPlaylist: {
            title = item[@"name"] ?: @"";
            NSInteger n = [item[@"songCount"] integerValue];
            detail = [NSString stringWithFormat:@"%d song%@", (int)n, n == 1 ? @"" : @"s"];
            break;
        }
        case NVItemGenre: {
            cover = NO;
            title = item[@"name"] ?: @"";
            NSInteger a = [item[@"albumCount"] integerValue], s = [item[@"songCount"] integerValue];
            detail = [NSString stringWithFormat:@"%d album%@, %d song%@", (int)a, a == 1 ? @"" : @"s", (int)s, s == 1 ? @"" : @"s"];
            break;
        }
        case NVItemSong:
        case NVItemSongNumbered: {
            cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
            NSString *time = [NVTheme timeString:[item[@"duration"] doubleValue]];
            NSString *sid = item[@"id"];
            NSString *state = [[NVDownloadManager shared] isDownloaded:sid] ? @" \u00B7 Offline"
                            : ([[NVDownloadManager shared] isPending:sid] ? @" \u00B7 Queued" : @"");
            if ([fav isStarred:sid]) state = [state stringByAppendingString:@" \u2605"];
            if (type == NVItemSongNumbered) {
                cover = NO;
                NSInteger tr = [item[@"track"] integerValue];
                if (tr) title = [NSString stringWithFormat:@"%d. %@", (int)tr, title];
                detail = [time stringByAppendingString:state];
            } else {
                NSString *artist = [item[@"artist"] description];
                detail = [NSString stringWithFormat:@"%@%@%@", artist.length ? [artist stringByAppendingString:@" \u00B7 "] : @"", time, state];
            }
            if ([[NVPlayer shared].currentSong[@"id"] isEqual:sid]) cell.textLabel.textColor = [UIColor colorWithRed:.10 green:.36 blue:.80 alpha:1];
            break;
        }
    }
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;

    NSString *cid = cover ? item[@"coverArt"] : nil;
    cell.accessibilityIdentifier = cid ?: @"";
    if (cover) {
        cell.imageView.image = [NVTheme placeholder];
        if (cid.length) {
            [NVImageLoader loadCover:cid size:44 completion:^(UIImage *img) {
                if (img && [cell.accessibilityIdentifier isEqualToString:cid]) {
                    cell.imageView.image = img;
                    [cell setNeedsLayout];
                }
            }];
        }
    }
    return cell;
}

+ (void)showActionsForSong:(NSDictionary *)song {
    NVSongSheet *h = [[NVSongSheet alloc] init];
    h.song = song;
    sCurrentSheet = h;
    BOOL offline = [NVOffline shared].isOffline;
    NVDownloadManager *dm = [NVDownloadManager shared];
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:song[@"title"] delegate:h cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:@"Play Next"];
    [sheet addButtonWithTitle:@"Add to Queue"];
    [sheet addButtonWithTitle:[[NVFavorites shared] isStarred:song[@"id"]] ? @"Unfavorite" : @"Favorite"];
    if (!offline) {
        [sheet addButtonWithTitle:kAddToPlaylist];
        [sheet addButtonWithTitle:kShare];
    }
    if ([dm isDownloaded:song[@"id"]]) {
        sheet.destructiveButtonIndex = [sheet addButtonWithTitle:@"Remove Download"];
    } else if (![dm isPending:song[@"id"]] && !offline) {
        [sheet addButtonWithTitle:@"Download"];
    }
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showInView:[UIApplication sharedApplication].keyWindow];
}

@end
