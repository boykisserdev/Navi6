#import "NVShare.h"
#import "NVClient.h"
#import "NVOffline.h"
#import "NVTheme.h"

@interface NVShare () <UIActionSheetDelegate>
@property (nonatomic, copy) NSString *itemID, *title;
@property (nonatomic, strong) UIPopoverController *popover;
@end

static NVShare *sShare;

@implementation NVShare

+ (void)shareItemID:(NSString *)itemID title:(NSString *)title {
    if (!itemID) return;
    if ([NVOffline shared].isOffline) { [[NVOffline shared] showOfflineAlert]; return; }
    NVShare *s = [[NVShare alloc] init];
    s.itemID = itemID; s.title = title;
    sShare = s;
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Link available for" delegate:s cancelButtonTitle:nil
                                         destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSString *t in @[@"1 hour", @"1 day", @"7 days", @"30 days", @"No expiration"]) [sheet addButtonWithTitle:t];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showInView:NVTopViewController().view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex) { sShare = nil; return; }
    NSArray *seconds = @[@3600, @86400, @604800, @2592000, @0];
    double secs = [seconds[i] doubleValue];
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObject:self.itemID forKey:@"id"];
    if (self.title.length) p[@"description"] = self.title;
    if (secs > 0) p[@"expires"] = @((long long)(([[NSDate date] timeIntervalSince1970] + secs) * 1000));
    [[NVClient shared] request:@"createShare" params:p completion:^(NSDictionary *r, NSError *e) {
        NSString *url = e ? nil : [([NVArray(r[@"shares"][@"share"]) count] ? NVArray(r[@"shares"][@"share"])[0][@"url"] : nil) description];
        if (!url.length) {
            NSString *m = e ? e.localizedDescription : @"The server did not return a link. Is sharing enabled in Navidrome?";
            [[[UIAlertView alloc] initWithTitle:@"Couldn\u2019t create link" message:m delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            sShare = nil;
            return;
        }
        [self presentURL:url];
    }];
}

- (void)presentURL:(NSString *)url {
    UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL URLWithString:url]] applicationActivities:nil];
    UIViewController *top = NVTopViewController();
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.popover = [[UIPopoverController alloc] initWithContentViewController:avc];
        CGRect b = top.view.bounds;
        [self.popover presentPopoverFromRect:CGRectMake(b.size.width / 2, b.size.height / 2, 1, 1) inView:top.view
                    permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        [top presentViewController:avc animated:YES completion:nil];
        sShare = nil;
    }
}

@end
