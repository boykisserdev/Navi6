#import "NVNowPlayingViewController.h"
#import "NVPlayer.h"
#import "NVClient.h"
#import "NVTheme.h"
#import "NVFavorites.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

static UILabel *NVLabel(UIFont *font, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.font = font; l.textColor = color;
    l.shadowColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.85];
    l.shadowOffset = CGSizeMake(0, -1);
    return l;
}

// Layout follows the iOS 6 iPod/Music "Now Playing" screen:
//  - black translucent nav bar floating over a full-width 320x320 cover,
//  - scrubber strip under the nav bar, tap the cover for repeat / favorite / shuffle,
//  - nav-bar button flips the cover to the track list,
//  - dark control panel with title/artist/album, transport buttons and volume slider.
@interface NVNowPlayingViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIView *artContainer, *scrubber, *extras;
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UITableView *tracks;
@property (nonatomic, strong) NVGlassView *panel;
@property (nonatomic, strong) UILabel *titleLabel, *artistLabel, *albumLabel, *elapsedLabel, *remainingLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) NVTransportButton *prevButton, *playButton, *nextButton, *shuffleButton, *repeatButton, *starButton;
@property (nonatomic, strong) MPVolumeView *volume;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL scrubbing, showingTracks;
@property (nonatomic, copy) NSString *shownSongID;
@end

@implementation NVNowPlayingViewController

- (id)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) { self.hidesBottomBarWhenPushed = YES; self.wantsFullScreenLayout = YES; self.title = @"Now Playing"; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *v = self.view;
    v.backgroundColor = [UIColor blackColor];

    self.artContainer = [[UIView alloc] init];
    self.artContainer.backgroundColor = [UIColor blackColor];
    [v addSubview:self.artContainer];

    self.artView = [[UIImageView alloc] init];
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.userInteractionEnabled = YES;
    [self.artView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleExtras)]];
    [self.artContainer addSubview:self.artView];

    self.tracks = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tracks.dataSource = self; self.tracks.delegate = self;
    self.tracks.backgroundColor = [UIColor colorWithWhite:.07 alpha:1];
    self.tracks.separatorColor = [UIColor colorWithWhite:.20 alpha:1];
    self.tracks.rowHeight = 44;
    self.tracks.hidden = YES;
    [self.artContainer addSubview:self.tracks];

    // scrubber strip
    self.scrubber = [[UIView alloc] init];
    self.scrubber.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    [v addSubview:self.scrubber];
    self.elapsedLabel   = NVLabel([UIFont boldSystemFontOfSize:12], [UIColor whiteColor]);
    self.remainingLabel = NVLabel([UIFont boldSystemFontOfSize:12], [UIColor whiteColor]);
    self.remainingLabel.textAlignment = NSTextAlignmentRight;
    [self.scrubber addSubview:self.elapsedLabel]; [self.scrubber addSubview:self.remainingLabel];
    self.slider = [[UISlider alloc] init];
    [self.slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [self.slider addTarget:self action:@selector(scrubChanged) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.scrubber addSubview:self.slider];

    // extra controls (shown when the cover is tapped)
    self.extras = [[UIView alloc] init];
    self.extras.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    self.extras.alpha = 0;
    [v addSubview:self.extras];
    self.repeatButton  = [[NVTransportButton alloc] initWithGlyph:NVGlyphRepeat];
    self.starButton    = [[NVTransportButton alloc] initWithGlyph:NVGlyphStar];
    self.shuffleButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphShuffle];
    [self.repeatButton addTarget:self action:@selector(repeatTap) forControlEvents:UIControlEventTouchUpInside];
    [self.starButton addTarget:self action:@selector(starTap) forControlEvents:UIControlEventTouchUpInside];
    [self.shuffleButton addTarget:self action:@selector(shuffleTap) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *b in @[self.repeatButton, self.starButton, self.shuffleButton]) [self.extras addSubview:b];

    // bottom panel
    self.panel = [[NVGlassView alloc] init];
    [v addSubview:self.panel];
    self.titleLabel  = NVLabel([UIFont boldSystemFontOfSize:15 * (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 1.25 : 1)], [UIColor whiteColor]);
    self.artistLabel = NVLabel([UIFont boldSystemFontOfSize:13 * (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 1.25 : 1)], [UIColor colorWithWhite:.78 alpha:1]);
    self.albumLabel  = NVLabel([UIFont systemFontOfSize:13 * (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 1.25 : 1)], [UIColor colorWithWhite:.58 alpha:1]);
    for (UILabel *l in @[self.titleLabel, self.artistLabel, self.albumLabel]) { l.textAlignment = NSTextAlignmentCenter; [self.panel addSubview:l]; }

    self.prevButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphPrev];
    self.playButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphPlay];
    self.nextButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphNext];
    [self.prevButton addTarget:self action:@selector(prevTap) forControlEvents:UIControlEventTouchUpInside];
    [self.playButton addTarget:self action:@selector(playTap) forControlEvents:UIControlEventTouchUpInside];
    [self.nextButton addTarget:self action:@selector(nextTap) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *b in @[self.prevButton, self.playButton, self.nextButton]) [self.panel addSubview:b];
    self.volume = [[MPVolumeView alloc] init];
    [self.panel addSubview:self.volume];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[NVTheme listIcon]
        style:UIBarButtonItemStyleBordered target:self action:@selector(toggleTracks)];
    [self reloadTrack];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    BOOL pad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    CGFloat k = pad ? 1.3f : 1.0f;
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    BOOL land = W > H;                                   // only possible on iPad
    CGFloat panelW = land ? 380 : W;
    CGFloat artW = land ? W - panelW : W;                // cover / track list area
    CGFloat artH = land ? H : W;                         // square in portrait, full height in landscape
    self.artContainer.frame = CGRectMake(0, 0, artW, artH);
    self.artView.frame = self.artContainer.bounds;
    self.tracks.frame = self.artContainer.bounds;
    self.tracks.contentInset = UIEdgeInsetsMake(104, 0, 0, 0);
    self.tracks.scrollIndicatorInsets = UIEdgeInsetsMake(104, 0, 0, 0);

    self.scrubber.frame = CGRectMake(0, 64, artW, 40);
    self.elapsedLabel.frame   = CGRectMake(8, 10, 44, 20);
    self.remainingLabel.frame = CGRectMake(artW - 52, 10, 44, 20);
    self.slider.frame = CGRectMake(54, 8, artW - 108, 24);
    self.extras.frame = CGRectMake(0, 104, artW, 44);
    self.repeatButton.frame  = CGRectMake(0, 0, 60, 44); self.repeatButton.center  = CGPointMake(artW * .2, 22);
    self.starButton.frame    = CGRectMake(0, 0, 60, 44); self.starButton.center    = CGPointMake(artW * .5, 22);
    self.shuffleButton.frame = CGRectMake(0, 0, 60, 44); self.shuffleButton.center = CGPointMake(artW * .8, 22);

    CGFloat pw = panelW, ph = land ? H : H - W;
    self.panel.frame = land ? CGRectMake(artW, 0, pw, H) : CGRectMake(0, W, W, ph);
    CGFloat ly, ty, vy, lh = pad ? 22 : 18;
    if (land) { ly = ph * .20f; ty = ph * .46f; vy = ph * .64f; }
    else { CGFloat extra = MAX(0, ph - 160); ly = 10 + extra * .2f; ty = 96 + extra * .45f; vy = ph - 38; }
    self.titleLabel.frame  = CGRectMake(14, ly,              pw - 28, lh);
    self.artistLabel.frame = CGRectMake(14, ly + lh,         pw - 28, lh - 2);
    self.albumLabel.frame  = CGRectMake(14, ly + 2 * lh - 2, pw - 28, lh - 2);
    self.playButton.frame = CGRectMake(0, 0, 80 * k, 56 * k); self.playButton.center = CGPointMake(pw / 2, ty);
    self.prevButton.frame = CGRectMake(0, 0, 66 * k, 48 * k); self.prevButton.center = CGPointMake(pw / 2 - 88 * k, ty);
    self.nextButton.frame = CGRectMake(0, 0, 66 * k, 48 * k); self.nextButton.center = CGPointMake(pw / 2 + 88 * k, ty);
    self.volume.frame = CGRectMake(28, vy, pw - 56, 30);
}

#pragma mark Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.barStyle = UIBarStyleBlackTranslucent;
    bar.tintColor = nil;
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:animated];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reloadTrack) name:NVPlayerChangedNotification object:nil];
    [nc addObserver:self selector:@selector(reloadState) name:NVFavoritesChangedNotification object:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self reloadTrack];
    [self tick];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    UINavigationBar *bar = self.navigationController.navigationBar;
    bar.barStyle = UIBarStyleDefault;
    bar.tintColor = [NVTheme barTint];
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.timer invalidate]; self.timer = nil;
}

#pragma mark Updating

- (void)reloadTrack {
    NVPlayer *p = [NVPlayer shared];
    NSDictionary *s = p.currentSong;
    self.titleLabel.text  = s[@"title"] ?: @"Not Playing";
    self.artistLabel.text = s[@"artist"];
    self.albumLabel.text  = s[@"album"];
    self.navigationItem.title = p.queue.count ? [NSString stringWithFormat:@"%d of %d", (int)p.index + 1, (int)p.queue.count] : @"Now Playing";
    NSString *sid = s[@"id"];
    if (![sid isEqual:self.shownSongID] || !self.artView.image) {
        self.shownSongID = sid;
        self.artView.image = [NVTheme placeholder];
        NSString *cid = s[@"coverArt"];
        if (cid.length) {
            [NVImageLoader loadCover:cid size:320 completion:^(UIImage *img) {
                if (img && [self.shownSongID isEqual:sid]) self.artView.image = img;
            }];
        }
    }
    if (self.showingTracks) [self.tracks reloadData];
    [self reloadState];
}

- (void)reloadState {
    NVPlayer *p = [NVPlayer shared];
    self.playButton.glyph = p.isPlaying ? NVGlyphPause : NVGlyphPlay;
    self.shuffleButton.active = p.shuffle;
    self.repeatButton.glyph = (p.repeatMode == 2) ? NVGlyphRepeatOne : NVGlyphRepeat;
    self.repeatButton.active = p.repeatMode > 0;
    self.starButton.active = [[NVFavorites shared] isStarred:p.currentSong[@"id"]];
}

- (void)tick {
    NVPlayer *p = [NVPlayer shared];
    NSTimeInterval dur = p.duration;
    NSTimeInterval t = self.scrubbing ? self.slider.value : p.currentTime;
    self.slider.maximumValue = MAX(dur, 1);
    if (!self.scrubbing) self.slider.value = MIN(t, self.slider.maximumValue);
    self.elapsedLabel.text = [NVTheme timeString:t];
    self.remainingLabel.text = dur > 0 ? [@"-" stringByAppendingString:[NVTheme timeString:MAX(dur - t, 0)]] : @"--:--";
    [self reloadState];
}

#pragma mark Actions

- (void)toggleExtras {
    BOOL show = self.extras.alpha < .5;
    [UIView animateWithDuration:.25 animations:^{ self.extras.alpha = show ? 1 : 0; }];
}

- (void)toggleTracks {
    self.showingTracks = !self.showingTracks;
    UIView *from = self.showingTracks ? self.artView : self.tracks;
    UIView *to   = self.showingTracks ? self.tracks : self.artView;
    if (self.showingTracks) {
        [self.tracks reloadData];
        NVPlayer *p = [NVPlayer shared];
        if (p.index >= 0 && p.index < (NSInteger)p.queue.count)
            [self.tracks scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:p.index inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    [UIView transitionFromView:from toView:to duration:0.7
        options:(self.showingTracks ? UIViewAnimationOptionTransitionFlipFromRight : UIViewAnimationOptionTransitionFlipFromLeft) | UIViewAnimationOptionShowHideTransitionViews
        completion:nil];
}

- (void)scrubBegan   { self.scrubbing = YES; }
- (void)scrubChanged { [self tick]; }
- (void)scrubEnded   { [[NVPlayer shared] seekToTime:self.slider.value]; self.scrubbing = NO; }
- (void)prevTap { [[NVPlayer shared] previous]; }
- (void)playTap { [[NVPlayer shared] togglePlayPause]; }
- (void)nextTap { [[NVPlayer shared] next]; }
- (void)shuffleTap { [NVPlayer shared].shuffle = ![NVPlayer shared].shuffle; }
- (void)repeatTap  { [NVPlayer shared].repeatMode = ([NVPlayer shared].repeatMode + 1) % 3; }
- (void)starTap { NSDictionary *s = [NVPlayer shared].currentSong; if (s) [[NVFavorites shared] toggleSong:s]; }

#pragma mark Track list (back side of the cover)

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [NVPlayer shared].queue.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"trk"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"trk"];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:.65 alpha:1];
    }
    NSDictionary *s = [NVPlayer shared].queue[ip.row];
    BOOL current = ip.row == [NVPlayer shared].index;
    cell.textLabel.text = [NSString stringWithFormat:@"%d. %@", (int)ip.row + 1, s[@"title"] ?: @""];
    cell.imageView.image = current ? [NVTheme speakerIcon] : [NVTheme blankSpeakerIcon];
    cell.textLabel.textColor = current ? [UIColor colorWithRed:.35 green:.65 blue:1 alpha:1] : [UIColor whiteColor];
    cell.detailTextLabel.text = [NVTheme timeString:[s[@"duration"] doubleValue]];
    return cell;
}

- (void)tableView:(UITableView *)tv willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)ip {
    cell.backgroundColor = (ip.row % 2) ? [UIColor colorWithWhite:.11 alpha:1] : [UIColor colorWithWhite:.07 alpha:1];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [[NVPlayer shared] jumpToIndex:ip.row];
}

@end


@implementation UIViewController (NVNowPlaying)

- (void)nv_openNowPlaying {
    if ([self.navigationController.topViewController isKindOfClass:[NVNowPlayingViewController class]]) return;
    [self.navigationController pushViewController:[[NVNowPlayingViewController alloc] init] animated:YES];
}

// Kept for compatibility: the mini player replaced the "Now Playing" bar button.
- (void)nv_updateNowPlayingButton {}

@end
