#import "NVSettingsViewController.h"
#import "NVSettings.h"
#import "NVClient.h"
#import "NVDownloadManager.h"
#import "NVTheme.h"

// Sections: 0 Server (url/user/pass) | 1 Test connection | 2 Streaming | 3 Storage
@interface NVSettingsViewController ()
@property (nonatomic, copy) NSString *status;
@end

@implementation NVSettingsViewController

- (id)init {
    self = [super initWithStyle:UITableViewStyleGrouped];   // native iOS 6 linen grouped background
    if (self) { self.title = @"Settings"; }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageChanged) name:NVDownloadsChangedNotification object:nil];
    [self.tableView reloadData];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)storageChanged { [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:3] withRowAnimation:UITableViewRowAnimationNone]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return s == 0 ? 3 : (s == 3 ? 2 : 1); }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"Navidrome Server" : (s == 2 ? @"Streaming" : (s == 3 ? @"Storage" : nil));
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return self.status;
    if (s == 2) return @"Formats iOS 6 can\u2019t play (FLAC, Opus, OGG\u2026) are converted to MP3 by the server, both for streaming and downloads.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NVSettings *st = [NVSettings shared];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

    if (ip.section == 0) {
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
    } else if (ip.section == 1) {
        cell.textLabel.text = @"Test Connection";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
        cell.textLabel.textColor = [UIColor colorWithRed:.22 green:.33 blue:.53 alpha:1];
    } else if (ip.section == 2) {
        cell.textLabel.text = @"MP3 bitrate";
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"128", @"192", @"256", @"320"]];
        seg.segmentedControlStyle = UISegmentedControlStyleBar;
        seg.frame = CGRectMake(0, 0, 180, 30);
        NSInteger idx = [@[@128, @192, @256, @320] indexOfObject:@(st.transcodeBitrate)];
        seg.selectedSegmentIndex = idx == NSNotFound ? 2 : (NSInteger)idx;
        [seg addTarget:self action:@selector(bitrateChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = seg;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (ip.row == 0) {
        NVDownloadManager *dm = [NVDownloadManager shared];
        cell.textLabel.text = [NSString stringWithFormat:@"%d songs \u00B7 %@", (int)[dm downloadedSongs].count, [NVTheme sizeString:[dm totalBytes]]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.textLabel.text = @"Delete All Downloads";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor colorWithRed:.75 green:.1 blue:.08 alpha:1];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:17];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self testConnection];
    if (ip.section == 3 && ip.row == 1) {
        UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Remove all downloaded music from this device?" delegate:self
                                                  cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete All" otherButtonTitles:nil];
        [sheet showInView:self.view.window];
    }
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.destructiveButtonIndex) { [[NVDownloadManager shared] cancelPending]; [[NVDownloadManager shared] deleteAll]; }
}

- (void)bitrateChanged:(UISegmentedControl *)s {
    NSArray *v = @[@128, @192, @256, @320];
    [NVSettings shared].transcodeBitrate = [v[s.selectedSegmentIndex] integerValue];
}

- (void)testConnection {
    [self.view endEditing:YES];
    self.status = @"Connecting\u2026";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    [[NVClient shared] ping:^(NSError *e) {
        self.status = e ? [@"Failed: " stringByAppendingString:e.localizedDescription] : @"Connected \u2014 server is reachable and login works.";
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }];
}

#pragma mark Text fields

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    UITextField *next = (UITextField *)[self.tableView viewWithTag:f.tag + 1];
    if (next) [next becomeFirstResponder]; else [f resignFirstResponder];
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)f {
    NVSettings *st = [NVSettings shared];
    NSString *t = [f.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (f.tag == 10) st.serverURL = t;
    if (f.tag == 11) st.username = t;
    if (f.tag == 12) st.password = f.text;
}

@end
