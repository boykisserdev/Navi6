#import "NVSettingsViewController.h"
#import "NVSettings.h"
#import "NVClient.h"
#import "NVDownloadManager.h"
#import "NVOffline.h"
#import "NVTheme.h"
#import "NVLog.h"

enum { SecServer, SecTest, SecMode, SecStreaming, SecDownloads, SecStorage, SecCount };

@interface NVSettingsViewController ()
@property (nonatomic, copy) NSString *status;
@end

@implementation NVSettingsViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) { self.title = @"Settings"; }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NVLog(@"settings appear");
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(storageChanged) name:NVDownloadsChangedNotification object:nil];
    [nc addObserver:self selector:@selector(modeChanged) name:NVOfflineChangedNotification object:nil];
    [self.tableView reloadData];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)storageChanged { [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecStorage] withRowAnimation:UITableViewRowAnimationNone]; }
- (void)modeChanged    { [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecMode] withRowAnimation:UITableViewRowAnimationNone]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return SecCount; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) { case SecServer: return 3; case SecStreaming: return 2; case SecStorage: return 2; default: return 1; }
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case SecServer: return @"Navidrome Server";
        case SecMode: return @"Connection";
        case SecStreaming: return @"Streaming & Lyrics";
        case SecDownloads: return @"Downloads";
        case SecStorage: return @"Storage";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case SecTest: return self.status;
        case SecMode: {
            NVOffline *o = [NVOffline shared];
            if (o.manualOffline) return @"Offline mode is on: only downloaded music is shown and nothing is loaded from the server.";
            if (!o.networkReachable) return @"No network connection: only downloaded music is shown.";
            return @"Offline mode shows only downloaded music everywhere and saves data.";
        }
        case SecStreaming: return @"Formats iOS 6 can\u2019t play (FLAC, Opus, OGG\u2026) are converted to MP3 by the server. Lyrics come from Navidrome (tags / .lrc) or from the web.";
        case SecDownloads: return @"More simultaneous downloads are faster but need more bandwidth.";
        default: return nil;
    }
}

- (NSString *)lyricsSourceName {
    switch ([NVSettings shared].lyricsSource) {
        case 1: return @"Navidrome";
        case 2: return @"LRCLIB";
        case 3: return @"lyrics.ovh";
        default: return @"Automatic";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NVSettings *st = [NVSettings shared];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:(ip.section == SecStreaming && ip.row == 1) ? UITableViewCellStyleValue1 : UITableViewCellStyleDefault reuseIdentifier:nil];

    switch (ip.section) {
        case SecServer: {
            NSArray *labels = @[@"URL", @"User", @"Password"];
            cell.textLabel.text = labels[ip.row];
            cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
            UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(100, 12, 190, 22)];
            f.tag = 10 + ip.row; f.delegate = self;
            f.font = [UIFont systemFontOfSize:15];
            f.textColor = [UIColor colorWithRed:.22 green:.33 blue:.53 alpha:1];
            f.autocapitalizationType = UITextAutocapitalizationTypeNone;
            f.autocorrectionType = UITextAutocorrectionTypeNo;
            f.clearButtonMode = UITextFieldViewModeWhileEditing;
            f.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            if (ip.row == 0) { f.text = st.serverURL; f.placeholder = @"http://192.168.1.10:4533"; f.keyboardType = UIKeyboardTypeURL; f.returnKeyType = UIReturnKeyNext; }
            if (ip.row == 1) { f.text = st.username;  f.placeholder = @"username"; f.returnKeyType = UIReturnKeyNext; }
            if (ip.row == 2) { f.text = st.password;  f.placeholder = @"required"; f.secureTextEntry = YES; f.returnKeyType = UIReturnKeyDone; }
            [cell.contentView addSubview:f];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case SecTest:
            cell.textLabel.text = @"Test Connection";
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
            cell.textLabel.textColor = [UIColor colorWithRed:.22 green:.33 blue:.53 alpha:1];
            break;
        case SecMode: {
            cell.textLabel.text = @"Offline Mode";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = [NVOffline shared].manualOffline;
            [sw addTarget:self action:@selector(offlineSwitched:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case SecStreaming:
            if (ip.row == 0) {
                cell.textLabel.text = @"MP3 bitrate";
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"128", @"192", @"256", @"320"]];
                seg.segmentedControlStyle = UISegmentedControlStyleBar;
                seg.frame = CGRectMake(0, 0, 180, 30);
                NSUInteger idx = [@[@128, @192, @256, @320] indexOfObject:@(st.transcodeBitrate)];
                seg.selectedSegmentIndex = idx == NSNotFound ? 2 : (NSInteger)idx;
                [seg addTarget:self action:@selector(bitrateChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = seg;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = @"Lyrics source";
                cell.detailTextLabel.text = [self lyricsSourceName];
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;
        case SecDownloads: {
            cell.textLabel.text = @"At the same time";
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"1", @"2", @"3"]];
            seg.segmentedControlStyle = UISegmentedControlStyleBar;
            seg.frame = CGRectMake(0, 0, 130, 30);
            seg.selectedSegmentIndex = st.maxConcurrentDownloads - 1;
            [seg addTarget:self action:@selector(concurrencyChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = seg;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        default:
            if (ip.row == 0) {
                NVDownloadManager *dm = [NVDownloadManager shared];
                cell.textLabel.text = [NSString stringWithFormat:@"%d songs \u00B7 %@", (int)[dm downloadedSongs].count, [NVTheme sizeString:[dm totalBytes]]];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            } else {
                cell.textLabel.text = @"Delete All Downloads";
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.textLabel.textColor = [UIColor colorWithRed:.75 green:.1 blue:.08 alpha:1];
                cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
            }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NVLog(@"settings row %d/%d", (int)ip.section, (int)ip.row);
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == SecTest) [self testConnection];
    if (ip.section == SecStreaming && ip.row == 1) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Lyrics source" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        sheet.tag = 2;
        for (NSString *t in @[@"Automatic (Navidrome, then web)", @"Navidrome (tags / .lrc)", @"LRCLIB (web)", @"lyrics.ovh (web)"]) [sheet addButtonWithTitle:t];
        sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
        [sheet showInView:self.view.window];
    }
    if (ip.section == SecStorage && ip.row == 1) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Remove all downloaded music from this device?" delegate:self
                                                  cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete All" otherButtonTitles:nil];
        sheet.tag = 1;
        [sheet showInView:self.view.window];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex) return;
    if (sheet.tag == 1 && i == sheet.destructiveButtonIndex) {
        [[NVDownloadManager shared] cancelPending]; [[NVDownloadManager shared] deleteAll];
    } else if (sheet.tag == 2) {
        [NVSettings shared].lyricsSource = i;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecStreaming] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)offlineSwitched:(UISwitch *)sw { [NVOffline shared].manualOffline = sw.on; [self modeChanged]; }

- (void)bitrateChanged:(UISegmentedControl *)s {
    NSArray *v = @[@128, @192, @256, @320];
    [NVSettings shared].transcodeBitrate = [v[s.selectedSegmentIndex] integerValue];
}

- (void)concurrencyChanged:(UISegmentedControl *)s {
    [NVSettings shared].maxConcurrentDownloads = s.selectedSegmentIndex + 1;
    [[NVDownloadManager shared] kick];
}

- (void)testConnection {
    NVLog(@"test connection tapped");
    [self.view endEditing:YES];
    self.status = @"Connecting\u2026";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecTest] withRowAnimation:UITableViewRowAnimationNone];
    [[NVClient shared] ping:^(NSError *e) {
        self.status = e ? [@"Failed: " stringByAppendingString:e.localizedDescription] : @"Connected \u2014 server is reachable and login works.";
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SecTest] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    UITextField *next = (UITextField *)[self.tableView viewWithTag:f.tag + 1];
    if (next) [next becomeFirstResponder]; else [f resignFirstResponder];
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)f {
    NVLog(@"settings field %d edited", (int)f.tag);
    NVSettings *st = [NVSettings shared];
    NSString *t = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (f.tag == 10) st.serverURL = t;
    if (f.tag == 11) st.username = t;
    if (f.tag == 12) st.password = f.text;
}

@end
