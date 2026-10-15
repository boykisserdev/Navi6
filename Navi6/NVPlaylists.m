#import "NVPlaylists.h"
#import "NVClient.h"
#import "NVOffline.h"
#import "NVTheme.h"

static void NVAlertError(NSString *title, NSError *e) {
    [[[UIAlertView alloc] initWithTitle:title message:e.localizedDescription delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
}

@interface NVPlaylistPrompt : NSObject <UIAlertViewDelegate>
@property (nonatomic, copy) NSArray *songIDs;
@property (nonatomic, copy) void (^completion)(BOOL ok);
@end
static NVPlaylistPrompt *sPrompt;

@implementation NVPlaylistPrompt
- (void)alertView:(UIAlertView *)av clickedButtonAtIndex:(NSInteger)i {
    NSString *name = i == av.cancelButtonIndex ? nil
        : [[av textFieldAtIndex:0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!name.length) { sPrompt = nil; return; }
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObject:name forKey:@"name"];
    if (self.songIDs.count) p[@"songId"] = self.songIDs;
    [[NVClient shared] request:@"createPlaylist" params:p completion:^(NSDictionary *r, NSError *e) {
        if (e) NVAlertError(@"Couldn\u2019t create playlist", e);
        else [[NSNotificationCenter defaultCenter] postNotificationName:NVPlaylistsChangedNotification object:nil];
        if (self.completion) self.completion(e == nil);
        sPrompt = nil;
    }];
}
@end

@interface NVPlaylistPicker : UITableViewController
@property (nonatomic, copy) NSArray *songIDs;
@property (nonatomic, strong) NSArray *playlists;
@property (nonatomic) BOOL loaded;
@end

@implementation NVPlaylistPicker

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Add to Playlist";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    [[NVClient shared] request:@"getPlaylists" params:@{} completion:^(NSDictionary *r, NSError *e) {
        if (e) { NVAlertError(@"Couldn\u2019t load playlists", e); [self cancel]; return; }
        self.playlists = NVArray(r[@"playlists"][@"playlist"]);
        self.loaded = YES;
        [self.tableView reloadData];
    }];
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.loaded ? (NSInteger)self.playlists.count + 1 : 0; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"pl"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"pl"];
    if (ip.row == 0) {
        cell.textLabel.text = @"New Playlist\u2026";
        cell.textLabel.textColor = [UIColor colorWithRed:.10 green:.36 blue:.80 alpha:1];
        cell.detailTextLabel.text = nil;
    } else {
        NSDictionary *p = self.playlists[ip.row - 1];
        cell.textLabel.text = p[@"name"];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%d songs", [p[@"songCount"] intValue]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *ids = self.songIDs;
    if (ip.row == 0) {
        [self dismissViewControllerAnimated:YES completion:^{ [NVPlaylists promptCreateWithSongs:ids completion:nil]; }];
        return;
    }
    NSString *pid = self.playlists[ip.row - 1][@"id"];
    [[NVClient shared] request:@"updatePlaylist" params:@{ @"playlistId": pid, @"songIdToAdd": ids } completion:^(NSDictionary *r, NSError *e) {
        if (e) NVAlertError(@"Couldn\u2019t add songs", e);
        else [[NSNotificationCenter defaultCenter] postNotificationName:NVPlaylistsChangedNotification object:nil];
    }];
    [self cancel];
}
@end

@implementation NVPlaylists

+ (void)promptCreateWithSongs:(NSArray *)songIDs completion:(void (^)(BOOL))completion {
    if ([NVOffline shared].isOffline) { [[NVOffline shared] showOfflineAlert]; return; }
    NVPlaylistPrompt *p = [[NVPlaylistPrompt alloc] init];
    p.songIDs = songIDs; p.completion = completion;
    sPrompt = p;
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"New Playlist" message:@"Enter a name for this playlist." delegate:p
                                       cancelButtonTitle:@"Cancel" otherButtonTitles:@"Create", nil];
    av.alertViewStyle = UIAlertViewStylePlainTextInput;
    [av textFieldAtIndex:0].placeholder = @"Playlist name";
    [av textFieldAtIndex:0].autocapitalizationType = UITextAutocapitalizationTypeSentences;
    [av show];
}

+ (void)presentPickerForSongs:(NSArray *)songIDs {
    if ([NVOffline shared].isOffline) { [[NVOffline shared] showOfflineAlert]; return; }
    NVPlaylistPicker *picker = [[NVPlaylistPicker alloc] initWithStyle:UITableViewStylePlain];
    picker.songIDs = songIDs;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [NVTopViewController() presentViewController:nav animated:YES completion:nil];
}

+ (void)removeIndex:(NSInteger)index fromPlaylistID:(NSString *)pid completion:(void (^)(BOOL))completion {
    [[NVClient shared] request:@"updatePlaylist" params:@{ @"playlistId": pid, @"songIndexToRemove": @(index) } completion:^(NSDictionary *r, NSError *e) {
        if (e) NVAlertError(@"Couldn\u2019t remove song", e);
        else [[NSNotificationCenter defaultCenter] postNotificationName:NVPlaylistsChangedNotification object:nil];
        if (completion) completion(e == nil);
    }];
}

+ (void)deletePlaylistID:(NSString *)pid completion:(void (^)(BOOL))completion {
    [[NVClient shared] request:@"deletePlaylist" params:@{ @"id": pid } completion:^(NSDictionary *r, NSError *e) {
        if (e) NVAlertError(@"Couldn\u2019t delete playlist", e);
        else [[NSNotificationCenter defaultCenter] postNotificationName:NVPlaylistsChangedNotification object:nil];
        if (completion) completion(e == nil);
    }];
}

@end
