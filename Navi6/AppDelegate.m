#import "AppDelegate.h"
#import "NVBrowserViewController.h"
#import "NVFavoritesViewController.h"
#import "NVAlbumGridViewController.h"
#import "NVDownloadsViewController.h"
#import "NVSettingsViewController.h"
#import "NVNowPlayingViewController.h"
#import "NVMiniPlayerView.h"
#import "NVFavorites.h"
#import "NVSettings.h"
#import "NVClient.h"
#import "NVTheme.h"
#import "NVPlayer.h"
#import "NVDownloadManager.h"
#import "NVOffline.h"
#import "NVLog.h"

#define MINI_H 48

static void NVUncaughtException(NSException *e) {
    NVLog(@"EXCEPTION %@: %@", e.name, e.reason);
    NSArray *syms = [e callStackSymbols];
    for (NSUInteger i = 0; i < syms.count && i < 14; i++) NVLog(@"  %@", syms[i]);
    NVLog(@"[crashed]");
}

static UINavigationController *NVActiveNav(UIViewController *selected) {
    UINavigationController *n = [selected isKindOfClass:[UINavigationController class]] ? (UINavigationController *)selected : nil;
    if ([n.topViewController isKindOfClass:[UINavigationController class]]) n = (UINavigationController *)n.topViewController;
    return n;
}

static NSString * const NVTabOrderKey = @"tabOrder";

static void NVSaveTabOrder(NSArray *controllers) {
    if (!controllers.count) return;
    NSMutableArray *tags = [NSMutableArray array];
    for (UIViewController *v in controllers) [tags addObject:@(v.tabBarItem.tag)];
    [[NSUserDefaults standardUserDefaults] setObject:tags forKey:NVTabOrderKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL NVStackHidesBar(UINavigationController *nav, UIViewController *top) {
    NSArray *stack = nav.viewControllers;
    NSUInteger idx = [stack indexOfObject:top];
    if (idx == NSNotFound) return top.hidesBottomBarWhenPushed;
    for (NSUInteger i = 0; i <= idx; i++) if ([stack[i] hidesBottomBarWhenPushed]) return YES;
    return NO;
}

@interface NVRootTabBarController : UITabBarController <UITabBarControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NVMiniPlayerView *mini;
@property (nonatomic) BOOL topHidesBar;
@property (nonatomic) BOOL transitionPending;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation NVRootTabBarController

- (BOOL)canBecomeFirstResponder { return YES; }
- (void)remoteControlReceivedWithEvent:(UIEvent *)event { [[NVPlayer shared] handleRemoteEvent:event]; }

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.delegate = self;
    self.mini = [[NVMiniPlayerView alloc] initWithFrame:CGRectMake(0, 0, 320, MINI_H)];
    self.mini.hidden = YES;
    __weak NVRootTabBarController *weakSelf = self;
    self.mini.onTap = ^{
        UINavigationController *nav = NVActiveNav(weakSelf.selectedViewController);
        [nav.topViewController nv_openNowPlaying];
    };
    [self.view addSubview:self.mini];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshMini) name:NVPlayerChangedNotification object:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tickMini) userInfo:nil repeats:YES];
}

- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }

- (void)refreshMini {
    BOOL show = [NVPlayer shared].currentSong != nil && !self.topHidesBar && !self.transitionPending;
    self.mini.hidden = !show;
    if (show) [self.mini refresh];
    [self.view setNeedsLayout];
}

- (void)tickMini { if (!self.mini.hidden) [self.mini refresh]; }

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGFloat tabH = self.tabBar.frame.size.height;
    BOOL show = !self.mini.hidden;
    self.mini.frame = CGRectMake(0, h - tabH - MINI_H, w, MINI_H);
    for (UIView *v in self.view.subviews) {
        if (v == self.tabBar || v == self.mini) continue;
        v.frame = CGRectMake(0, 0, w, (self.topHidesBar || self.transitionPending) ? h : h - tabH - (show ? MINI_H : 0));
        break;
    }
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    UIViewController *sel = self.selectedViewController;
    if (nav == sel || sel == self.moreNavigationController) {
        BOOL hides = NVStackHidesBar(nav, vc);
        self.topHidesBar = hides;
        self.transitionPending = !hides && animated;
        [self refreshMini];
    }
}

- (void)navigationController:(UINavigationController *)nav didShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    if (!self.transitionPending) return;
    self.transitionPending = NO;
    [self refreshMini];
    if (!self.mini.hidden) {
        self.mini.alpha = 0;
        [UIView animateWithDuration:0.25 animations:^{ self.mini.alpha = 1; }];
    }
}

- (void)tabBarController:(UITabBarController *)tbc didEndCustomizingViewControllers:(NSArray *)vcs changed:(BOOL)changed {
    if (changed) NVSaveTabOrder(vcs);
}

- (void)tabBarController:(UITabBarController *)tbc didSelectViewController:(UIViewController *)vc {
    NVLog(@"tab selected: %@", vc.tabBarItem.title ?: @"More");
    UINavigationController *nav = NVActiveNav(vc);
    self.topHidesBar = nav ? NVStackHidesBar(nav, nav.topViewController) : NO;
    [self refreshMini];
}

@end

@implementation AppDelegate

- (UINavigationController *)navWith:(UIViewController *)root title:(NSString *)title icon:(NSString *)icon tag:(int)tag {
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:root];
    n.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:[NVTheme tabIconNamed:icon] tag:tag];
    return n;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    NVLogStart();
    NSString *crash = NVLogPreviousCrash();
    NVLogInstallCrashHandlers();
    NSSetUncaughtExceptionHandler(&NVUncaughtException);
    NVLog(@"launch %@", [[UIDevice currentDevice] systemVersion]);
    [NVTheme applyAppearance];
    [NVOffline shared];
    [NVPlayer shared];
    [NVDownloadManager shared];

    UIViewController *albums = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        ? (UIViewController *)[[NVAlbumGridViewController alloc] init]
        : [[NVBrowserViewController alloc] initRootKind:NVBrowseAlbums];
    UINavigationController *settings = [self navWith:[[NVSettingsViewController alloc] init] title:@"Settings" icon:@"settings" tag:6];

    NSArray *navs = @[
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowseSongs]     title:@"Songs"     icon:@"songs"     tag:0],
        [self navWith:albums                                                           title:@"Albums"    icon:@"albums"    tag:1],
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowseArtists]   title:@"Artists"   icon:@"artists"   tag:2],
        [self navWith:[[NVFavoritesViewController alloc] init]                         title:@"Favorites" icon:@"favorites" tag:3],
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowsePlaylists] title:@"Playlists" icon:@"playlists" tag:4],
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowseGenres]    title:@"Genres"    icon:@"genres"    tag:7],
        [self navWith:[[NVDownloadsViewController alloc] init]                         title:@"Downloads" icon:@"downloads" tag:5],
        settings ];

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:NVTabOrderKey];
    if (saved.count) {
        NSMutableArray *ordered = [NSMutableArray array], *rest = [navs mutableCopy];
        for (NSNumber *tag in saved) {
            for (UIViewController *n in rest) {
                if (n.tabBarItem.tag == tag.integerValue) { [ordered addObject:n]; [rest removeObject:n]; break; }
            }
        }
        [ordered addObjectsFromArray:rest];
        navs = ordered;
    }

    NVRootTabBarController *tabs = [[NVRootTabBarController alloc] init];
    for (UINavigationController *n in navs) n.delegate = tabs;
    tabs.viewControllers = navs;
    tabs.customizableViewControllers = navs;
    tabs.moreNavigationController.navigationBar.tintColor = [NVTheme barTint];
    if (crash) tabs.selectedIndex = 4;
    else if ([NVSettings shared].isConfigured) tabs.selectedIndex = 0;
    else tabs.selectedViewController = settings;

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];

    NVLog(@"launched, configured=%d", (int)[NVSettings shared].isConfigured);
    if (crash) {
        [UIPasteboard generalPasteboard].string = crash;
        [[[UIAlertView alloc] initWithTitle:@"Navi6 stopped unexpectedly last time"
                                    message:[crash substringFromIndex:crash.length > 900 ? crash.length - 900 : 0]
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
    }
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application { [[NVFavorites shared] refresh]; }

- (void)saveTabOrder {
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;
    if ([tabs isKindOfClass:[UITabBarController class]]) NVSaveTabOrder(tabs.viewControllers);
}
- (void)applicationDidEnterBackground:(UIApplication *)application { NVLog(@"[background]"); [self saveTabOrder]; }
- (void)applicationWillEnterForeground:(UIApplication *)application { NVLog(@"[foreground]"); }
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    NVLog(@"MEMORY WARNING");
    [NVImageLoader clearMemoryCache];
}
- (void)applicationWillTerminate:(UIApplication *)application { NVLog(@"[clean]"); [self saveTabOrder]; }

- (void)remoteControlReceivedWithEvent:(UIEvent *)event { [[NVPlayer shared] handleRemoteEvent:event]; }

@end
