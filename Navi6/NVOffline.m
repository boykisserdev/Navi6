#import "NVOffline.h"
#import "NVSettings.h"
#import "NVTheme.h"
#import "NVLog.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <netinet/in.h>

NSString * const NVOfflineChangedNotification = @"NVOfflineChanged";

@interface NVOffline () <UIAlertViewDelegate>
@property (nonatomic) BOOL networkReachable;
- (void)applyFlags:(SCNetworkReachabilityFlags)flags;
@end

static void NVReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    [[NVOffline shared] applyFlags:flags];
}

@implementation NVOffline {
    SCNetworkReachabilityRef _reach;
    BOOL _lastOffline;
}

+ (instancetype)shared {
    static NVOffline *o; static dispatch_once_t once;
    dispatch_once(&once, ^{ o = [[NVOffline alloc] init]; });
    return o;
}

- (BOOL)reachableFor:(SCNetworkReachabilityFlags)f {
    return (f & kSCNetworkReachabilityFlagsReachable) && !(f & kSCNetworkReachabilityFlagsConnectionRequired);
}

- (id)init {
    self = [super init];
    if (self) {
        _networkReachable = YES;
        struct sockaddr_in zero;
        bzero(&zero, sizeof(zero));
        zero.sin_len = sizeof(zero);
        zero.sin_family = AF_INET;
        _reach = SCNetworkReachabilityCreateWithAddress(NULL, (const struct sockaddr *)&zero);
        if (_reach) {
            SCNetworkReachabilityFlags f;
            if (SCNetworkReachabilityGetFlags(_reach, &f)) _networkReachable = [self reachableFor:f];
            SCNetworkReachabilitySetCallback(_reach, NVReachabilityCallback, NULL);
            SCNetworkReachabilityScheduleWithRunLoop(_reach, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        }
        _lastOffline = self.isOffline;
    }
    return self;
}

- (void)applyFlags:(SCNetworkReachabilityFlags)flags {
    self.networkReachable = [self reachableFor:flags];
    [self checkChange];
}

- (void)checkChange {
    BOOL off = self.isOffline;
    if (off == _lastOffline) return;
    _lastOffline = off;
    NVLog(@"offline=%d", (int)off);
    [[NSNotificationCenter defaultCenter] postNotificationName:NVOfflineChangedNotification object:nil];
}

- (BOOL)isOffline { return self.manualOffline || !self.networkReachable; }
- (BOOL)manualOffline { return [NVSettings shared].offlineMode; }
- (void)setManualOffline:(BOOL)v { [NVSettings shared].offlineMode = v; [self checkChange]; }

- (void)showOfflineAlert {
    NVLog(@"offline alert");
    BOOL manual = self.manualOffline;
    NSString *msg = manual ? @"Offline mode is on. Only downloaded music is shown and nothing is loaded from the server."
                           : @"There is no network connection. Only downloaded music is shown.";
    UIAlertView *av = [[UIAlertView alloc] initWithTitle:@"You\u2019re Offline" message:msg delegate:self
                                       cancelButtonTitle:@"OK" otherButtonTitles:(manual ? @"Go Online" : nil), nil];
    [av show];
}

- (void)alertView:(UIAlertView *)av clickedButtonAtIndex:(NSInteger)i {
    if (i != av.cancelButtonIndex) self.manualOffline = NO;
}

- (UIBarButtonItem *)cloudItem {
    return [[UIBarButtonItem alloc] initWithImage:[NVTheme cloudOfflineIcon] style:UIBarButtonItemStyleBordered
                                           target:self action:@selector(showOfflineAlert)];
}

@end
