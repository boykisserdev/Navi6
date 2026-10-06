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
#import "NVTheme.h"
#import "NVPlayer.h"
#import "NVDownloadManager.h"

#define MINI_H 48

// A tab's navigation controller can also be shown nested inside the system "More" navigation controller.
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

// Tab bar controller: hosts the mini player above the tab bar and receives remote-control events.
// With more than 5 view controllers UIKit creates the standard "More" tab with its "Edit" button, which lets the
// user drag tabs in and out of the bar (same as the stock Music app). iPhone is portrait-only, iPad rotates freely.
@interface NVRootTabBarController : UITabBarController <UITabBarControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) NVMiniPlayerView *mini;
@property (nonatomic) BOOL topHidesBar;
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
    BOOL show = [NVPlayer shared].currentSong != nil && !self.topHidesBar;
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
    for (UIView *v in self.view.subviews) {          // keep list content clear of the mini player
        if (v == self.tabBar || v == self.mini) continue;
        v.frame = CGRectMake(0, 0, w, self.topHidesBar ? h : h - tabH - (show ? MINI_H : 0));
        break;
    }
}

- (void)navigationController:(UINavigationController *)nav willShowViewController:(UIViewController *)vc animated:(BOOL)animated {
    UIViewController *sel = self.selectedViewController;
    if (nav == sel || sel == self.moreNavigationController) {      // also when the tab lives inside "More"
        self.topHidesBar = vc.hidesBottomBarWhenPushed;
        [self refreshMini];
    }
}

- (void)tabBarController:(UITabBarController *)tbc didEndCustomizingViewControllers:(NSArray *)vcs changed:(BOOL)changed {
    if (changed) NVSaveTabOrder(vcs);
}

- (void)tabBarController:(UITabBarController *)tbc didSelectViewController:(UIViewController *)vc {
    UINavigationController *nav = NVActiveNav(vc);
    self.topHidesBar = nav.topViewController.hidesBottomBarWhenPushed;
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
    [NVTheme applyAppearance];
    [NVPlayer shared];
    [NVDownloadManager shared];

    UIViewController *albums = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        ? (UIViewController *)[[NVAlbumGridViewController alloc] init]
        : [[NVBrowserViewController alloc] initRootKind:NVBrowseAlbums];
    UINavigationController *settings = [self navWith:[[NVSettingsViewController alloc] init] title:@"Settings" icon:@"settings" tag:6];

    // Default order = stock Music app: Songs, Albums, Artists, Favorites, More(Playlists, Downloads, Settings).
    // The first four sit in the bar, the rest land in the system More list; "Edit" there rearranges them.
    NSArray *navs = @[
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowseSongs]     title:@"Songs"     icon:@"songs"     tag:0],
        [self navWith:albums                                                           title:@"Albums"    icon:@"albums"    tag:1],
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowseArtists]   title:@"Artists"   icon:@"artists"   tag:2],
        [self navWith:[[NVFavoritesViewController alloc] init]                         title:@"Favorites" icon:@"favorites" tag:3],
        [self navWith:[[NVBrowserViewController alloc] initRootKind:NVBrowsePlaylists] title:@"Playlists" icon:@"playlists" tag:4],
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
    if ([NVSettings shared].isConfigured) tabs.selectedIndex = 0;
    else tabs.selectedViewController = settings;       // first launch: straight to Settings

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application { [[NVFavorites shared] refresh]; }

- (void)saveTabOrder {
    UITabBarController *tabs = (UITabBarController *)self.window.rootViewController;
    if ([tabs isKindOfClass:[UITabBarController class]]) NVSaveTabOrder(tabs.viewControllers);
}
- (void)applicationDidEnterBackground:(UIApplication *)application { [self saveTabOrder]; }
- (void)applicationWillTerminate:(UIApplication *)application { [self saveTabOrder]; }

- (void)remoteControlReceivedWithEvent:(UIEvent *)event { [[NVPlayer shared] handleRemoteEvent:event]; }

@end
