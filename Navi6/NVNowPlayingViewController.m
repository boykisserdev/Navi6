#import "NVNowPlayingViewController.h"
#import "NVPlayer.h"
#import "NVClient.h"
#import "NVTheme.h"
#import "NVFavorites.h"
#import "NVLyrics.h"
#import "NVBrowserViewController.h"
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

@interface NVLyricsView : UIView <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onSeek)(NSTimeInterval t);
- (void)showMessage:(NSString *)message;
- (void)setLines:(NSArray *)lines times:(NSArray *)times;
- (void)updateTime:(NSTimeInterval)t;
@end

@implementation NVLyricsView {
    UITableView *_table;
    NSArray *_lines, *_times;
    NSString *_message;
    NSInteger _current, _shownChars;
    double _holdUntil;
    BOOL _pendingScroll;
}

- (id)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:.07 alpha:1];
        _table = [[UITableView alloc] initWithFrame:self.bounds style:UITableViewStylePlain];
        _table.dataSource = self; _table.delegate = self;
        _table.backgroundColor = [UIColor clearColor];
        _table.separatorStyle = UITableViewCellSeparatorStyleNone;
        _table.showsVerticalScrollIndicator = NO;
        _table.contentInset = UIEdgeInsetsMake(10, 0, 160, 0);
        [self addSubview:_table];
        _current = -1; _shownChars = -1;
        for (int i = 0; i < 2; i++) {
            UISwipeGestureRecognizer *sw = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped)];
            sw.direction = i ? UISwipeGestureRecognizerDirectionLeft : UISwipeGestureRecognizerDirectionRight;
            [_table addGestureRecognizer:sw];
        }
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat top = 104;
    _table.frame = CGRectMake(0, top, self.bounds.size.width, MAX(0, self.bounds.size.height - top));
    _table.contentInset = UIEdgeInsetsMake(10, 0, _table.frame.size.height / 2, 0);
}
- (void)swiped { if (self.onClose) self.onClose(); }

- (void)showMessage:(NSString *)m {
    _holdUntil = 0; _pendingScroll = NO;
    _message = [m copy]; _lines = nil; _times = nil; _current = -1; _shownChars = -1;
    [_table reloadData];
}

- (void)setLines:(NSArray *)lines times:(NSArray *)times {
    _holdUntil = 0; _pendingScroll = NO;
    _message = nil; _lines = lines; _times = times; _current = -1; _shownChars = -1;
    [_table reloadData];
    [_table setContentOffset:CGPointMake(0, -_table.contentInset.top) animated:NO];
}

- (NSAttributedString *)karaoke:(NSString *)text chars:(NSInteger)n {
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    ps.alignment = NSTextAlignmentCenter;
    NSMutableAttributedString *a = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:18],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:.50 alpha:1],
        NSParagraphStyleAttributeName: ps }];
    if (n > 0) [a addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, MIN((NSUInteger)n, text.length))];
    return a;
}

- (void)scrollToCurrent {
    if (_current >= 0 && _current < (NSInteger)_lines.count)
        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_current inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { _holdUntil = DBL_MAX; }
- (void)scrollViewDidEndDragging:(UIScrollView *)sv willDecelerate:(BOOL)decelerate { if (!decelerate) _holdUntil = CACurrentMediaTime() + 4; }
- (void)scrollViewDidEndDecelerating:(UIScrollView *)sv { _holdUntil = CACurrentMediaTime() + 4; }

- (void)updateTime:(NSTimeInterval)t {
    if (!_times.count || _message) return;
    NSInteger idx = -1;
    for (NSInteger i = 0; i < (NSInteger)_times.count; i++) {
        if ([_times[i] doubleValue] <= t + 0.05) idx = i; else break;
    }
    if (idx != _current) {
        NSInteger old = _current;
        _current = idx; _shownChars = -1;
        NSMutableArray *ips = [NSMutableArray array];
        if (old >= 0 && old < (NSInteger)_lines.count) [ips addObject:[NSIndexPath indexPathForRow:old inSection:0]];
        if (idx >= 0) [ips addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
        [_table reloadRowsAtIndexPaths:ips withRowAnimation:UITableViewRowAnimationNone];
        if (idx >= 0) {
            if (CACurrentMediaTime() >= _holdUntil) [self scrollToCurrent];
            else _pendingScroll = YES;
        }
    }
    if (_pendingScroll && idx >= 0 && CACurrentMediaTime() >= _holdUntil) { _pendingScroll = NO; [self scrollToCurrent]; }
    if (idx < 0) return;

    NSTimeInterval start = [_times[idx] doubleValue];
    NSTimeInterval end = (idx + 1 < (NSInteger)_times.count) ? [_times[idx + 1] doubleValue] : start + 5;
    NSTimeInterval span = MAX(0.6, (end - start) * 0.9);
    NSString *text = _lines[idx];
    NSInteger n = (NSInteger)round(MIN(1.0, MAX(0.0, (t - start) / span)) * text.length);
    if (n == _shownChars) return;
    _shownChars = n;
    UITableViewCell *cell = [_table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:idx inSection:0]];
    cell.textLabel.attributedText = [self karaoke:text chars:n];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _message ? 1 : (NSInteger)_lines.count; }

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *text = _message ?: _lines[ip.row];
    CGSize sz = [text sizeWithFont:[UIFont boldSystemFontOfSize:18] constrainedToSize:CGSizeMake(tv.bounds.size.width - 40, 2000)
                     lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(36, sz.height + 14);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"ly"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ly"];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
        cell.textLabel.backgroundColor = [UIColor clearColor];
    }
    if (_message) {
        cell.textLabel.text = _message;
        cell.textLabel.textColor = [UIColor colorWithWhite:.6 alpha:1];
    } else if (_times.count && ip.row == _current) {
        cell.textLabel.attributedText = [self karaoke:_lines[ip.row] chars:MAX(0, _shownChars)];
    } else {
        cell.textLabel.text = _lines[ip.row];
        cell.textLabel.textColor = _times.count ? [UIColor colorWithWhite:.42 alpha:1] : [UIColor colorWithWhite:.88 alpha:1];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:NO];
    if (_message || !_times.count || !self.onSeek) return;
    _holdUntil = 0;
    self.onSeek([_times[ip.row] doubleValue]);
}

@end

@interface NVBarFace : UIView
@end
@implementation NVBarFace
- (id)initWithFrame:(CGRect)f { self = [super initWithFrame:f]; if (self) { self.backgroundColor = [UIColor clearColor]; } return self; }
- (void)drawRect:(CGRect)rect {
    CGRect r = CGRectInset(self.bounds, 0.5, 0.5);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:5];
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    [p addClip];
    CGFloat comps[8] = { .42, .43, .47, 1,  .16, .16, .19, 1 };
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(0, self.bounds.size.height), 0);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    [[UIColor colorWithWhite:1 alpha:.12] setFill];
    UIRectFill(CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height / 2));
    CGContextRestoreGState(c);
    [[UIColor colorWithWhite:0 alpha:.75] setStroke];
    [p stroke];
    UIImage *icon = [NVTheme listIcon];
    [icon drawAtPoint:CGPointMake((self.bounds.size.width - icon.size.width) / 2, (self.bounds.size.height - icon.size.height) / 2)];
}
@end

@interface NVFlipButton : UIView
- (id)initWithTarget:(id)target action:(SEL)action;
- (void)setCoverImage:(UIImage *)img;
- (void)setShowsCover:(BOOL)cover animated:(BOOL)animated;
@end

@implementation NVFlipButton {
    UIView *_faces;
    NVBarFace *_listFace;
    UIImageView *_coverFace;
    BOOL _showsCover;
}

- (id)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithFrame:CGRectMake(0, 0, 36, 30)];
    if (self) {
        _faces = [[UIView alloc] initWithFrame:self.bounds];
        _listFace = [[NVBarFace alloc] initWithFrame:_faces.bounds];
        _coverFace = [[UIImageView alloc] initWithFrame:CGRectInset(_faces.bounds, 3, 0)];
        _coverFace.frame = CGRectMake(3, 0, 30, 30);
        _coverFace.contentMode = UIViewContentModeScaleAspectFill;
        _coverFace.clipsToBounds = YES;
        _coverFace.layer.cornerRadius = 4;
        _coverFace.layer.borderWidth = 1; _coverFace.layer.borderColor = [UIColor colorWithWhite:.9 alpha:.9].CGColor;
        _coverFace.image = [NVTheme placeholder];
        _coverFace.hidden = YES;
        [_faces addSubview:_listFace]; [_faces addSubview:_coverFace];
        [self addSubview:_faces];
        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.frame = self.bounds;
        [hit addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:hit];
    }
    return self;
}

- (void)setCoverImage:(UIImage *)img { _coverFace.image = img ?: [NVTheme placeholder]; }

- (void)setShowsCover:(BOOL)cover animated:(BOOL)animated {
    if (cover == _showsCover) return;
    _showsCover = cover;
    UIView *from = cover ? (UIView *)_listFace : (UIView *)_coverFace, *to = cover ? (UIView *)_coverFace : (UIView *)_listFace;
    if (!animated) { from.hidden = YES; to.hidden = NO; return; }
    [UIView transitionFromView:from toView:to duration:0.7
        options:(cover ? UIViewAnimationOptionTransitionFlipFromRight : UIViewAnimationOptionTransitionFlipFromLeft) | UIViewAnimationOptionShowHideTransitionViews
        completion:nil];
}
@end

typedef NS_ENUM(NSInteger, NVNPMode) { NVNPModeArt, NVNPModeTracks, NVNPModeLyrics };

@interface NVNowPlayingViewController () <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIView *artContainer, *scrubber, *extras;
@property (nonatomic, strong) UIImageView *artView;
@property (nonatomic, strong) UITableView *tracks;
@property (nonatomic, strong) NVLyricsView *lyricsView;
@property (nonatomic, strong) NVGlassView *panel;
@property (nonatomic, strong) UILabel *titleLabel, *artistLabel, *albumLabel, *elapsedLabel, *remainingLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) NVTransportButton *prevButton, *playButton, *nextButton, *shuffleButton, *repeatButton, *starButton, *lyricsButton;
@property (nonatomic, strong) MPVolumeView *volume;
@property (nonatomic, strong) UIImageView *volMin, *volMax;
@property (nonatomic, strong) NVFlipButton *flipButton;
@property (nonatomic, strong) NSTimer *lyricsTimer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) BOOL scrubbing, presentedModally;
@property (nonatomic, strong) NSDictionary *sheetSong;
@property (nonatomic) NVNPMode mode;
@property (nonatomic, copy) NSString *shownSongID, *lyricsSongID;
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
    BOOL pad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    CGFloat fk = pad ? 1.25f : 1.0f;

    self.artContainer = [[UIView alloc] init];
    self.artContainer.backgroundColor = [UIColor blackColor];
    [v addSubview:self.artContainer];

    self.artView = [[UIImageView alloc] init];
    self.artView.contentMode = UIViewContentModeScaleAspectFill;
    self.artView.clipsToBounds = YES;
    self.artView.userInteractionEnabled = YES;
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapArt)];
    dbl.numberOfTapsRequired = 2;
    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleExtras)];
    [single requireGestureRecognizerToFail:dbl];
    [self.artView addGestureRecognizer:dbl];
    [self.artView addGestureRecognizer:single];
    [self.artContainer addSubview:self.artView];

    self.tracks = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tracks.dataSource = self; self.tracks.delegate = self;
    self.tracks.backgroundColor = [UIColor colorWithWhite:.07 alpha:1];
    self.tracks.separatorColor = [UIColor colorWithWhite:.20 alpha:1];
    self.tracks.rowHeight = 44;
    self.tracks.hidden = YES;
    self.tracks.allowsSelectionDuringEditing = YES;
    [self.tracks setEditing:YES animated:NO];
    [self.artContainer addSubview:self.tracks];

    self.lyricsView = [[NVLyricsView alloc] init];
    self.lyricsView.hidden = YES;
    __weak NVNowPlayingViewController *weakSelf = self;
    self.lyricsView.onClose = ^{ [weakSelf setMode:NVNPModeArt]; };
    self.lyricsView.onSeek = ^(NSTimeInterval t) { [[NVPlayer shared] seekToTime:t]; [weakSelf.lyricsView updateTime:t]; };
    [self.artContainer addSubview:self.lyricsView];

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

    self.extras = [[UIView alloc] init];
    self.extras.backgroundColor = [UIColor colorWithWhite:0 alpha:.55];
    self.extras.alpha = 0;
    [v addSubview:self.extras];
    self.repeatButton  = [[NVTransportButton alloc] initWithGlyph:NVGlyphRepeat];
    self.starButton    = [[NVTransportButton alloc] initWithGlyph:NVGlyphStar];
    self.lyricsButton  = [[NVTransportButton alloc] initWithGlyph:NVGlyphLyrics];
    self.shuffleButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphShuffle];
    [self.repeatButton addTarget:self action:@selector(repeatTap) forControlEvents:UIControlEventTouchUpInside];
    [self.starButton addTarget:self action:@selector(starTap) forControlEvents:UIControlEventTouchUpInside];
    [self.lyricsButton addTarget:self action:@selector(lyricsTap) forControlEvents:UIControlEventTouchUpInside];
    [self.shuffleButton addTarget:self action:@selector(shuffleTap) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *b in @[self.repeatButton, self.starButton, self.lyricsButton, self.shuffleButton]) [self.extras addSubview:b];

    self.panel = [[NVGlassView alloc] init];
    [v addSubview:self.panel];
    self.titleLabel  = NVLabel([UIFont boldSystemFontOfSize:15 * fk], [UIColor whiteColor]);
    self.artistLabel = NVLabel([UIFont boldSystemFontOfSize:13 * fk], [UIColor colorWithWhite:.78 alpha:1]);
    self.albumLabel  = NVLabel([UIFont systemFontOfSize:13 * fk],     [UIColor colorWithWhite:.58 alpha:1]);
    for (UILabel *l in @[self.titleLabel, self.artistLabel, self.albumLabel]) { l.textAlignment = NSTextAlignmentCenter; [self.panel addSubview:l]; }
    self.titleLabel.userInteractionEnabled = YES;
    [self.titleLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(titleTapped)]];

    self.prevButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphPrev];
    self.playButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphPlay];
    self.nextButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphNext];
    [self.prevButton addTarget:self action:@selector(prevTap) forControlEvents:UIControlEventTouchUpInside];
    [self.playButton addTarget:self action:@selector(playTap) forControlEvents:UIControlEventTouchUpInside];
    [self.nextButton addTarget:self action:@selector(nextTap) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *b in @[self.prevButton, self.playButton, self.nextButton]) [self.panel addSubview:b];
    self.volMin = [[UIImageView alloc] initWithImage:[NVTheme volumeIconMax:NO]];
    self.volMax = [[UIImageView alloc] initWithImage:[NVTheme volumeIconMax:YES]];
    [self.panel addSubview:self.volMin]; [self.panel addSubview:self.volMax];
    self.volume = [[MPVolumeView alloc] init];
    [self.panel addSubview:self.volume];

    self.flipButton = [[NVFlipButton alloc] initWithTarget:self action:@selector(toggleTracks)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.flipButton];
    if (self.presentedModally) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleBordered target:self action:@selector(closeModal)];
    }
    [self reloadTrack];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    BOOL pad = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    CGFloat k = pad ? 1.3f : 1.0f;
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    BOOL land = W > H;
    CGFloat panelW = land ? 380 : W;
    CGFloat artW = land ? W - panelW : W;
    CGFloat artH = land ? H : W;
    self.artContainer.frame = CGRectMake(0, 0, artW, artH);
    self.artView.frame = self.artContainer.bounds;
    self.tracks.frame = self.artContainer.bounds;
    self.lyricsView.frame = self.artContainer.bounds;
    self.tracks.contentInset = UIEdgeInsetsMake(104, 0, 0, 0);
    self.tracks.scrollIndicatorInsets = UIEdgeInsetsMake(104, 0, 0, 0);

    self.scrubber.frame = CGRectMake(0, 64, artW, 40);
    self.elapsedLabel.frame   = CGRectMake(8, 10, 44, 20);
    self.remainingLabel.frame = CGRectMake(artW - 52, 10, 44, 20);
    self.slider.frame = CGRectMake(54, 8, artW - 108, 24);
    self.extras.frame = CGRectMake(0, 104, artW, 44);
    NSArray *xs = @[@.14, @.38, @.62, @.86];
    NSArray *btns = @[self.repeatButton, self.starButton, self.lyricsButton, self.shuffleButton];
    for (int i = 0; i < 4; i++) {
        UIView *b = btns[i];
        b.frame = CGRectMake(0, 0, 60, 44);
        b.center = CGPointMake(artW * [xs[i] floatValue], 22);
    }

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
    self.volMin.center = CGPointMake(24, vy + 15);
    self.volMax.center = CGPointMake(pw - 24, vy + 15);
    self.volume.frame = CGRectMake(46, vy, pw - 92, 30);
    for (UIView *sv in self.volume.subviews) {
        if ([sv isKindOfClass:[UISlider class]]) ((UISlider *)sv).minimumTrackTintColor = [UIColor colorWithRed:.35 green:.65 blue:1 alpha:1];
    }
}

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
    [self.lyricsTimer invalidate]; self.lyricsTimer = nil;
}

- (void)reloadTrack {
    NVPlayer *p = [NVPlayer shared];
    NSDictionary *s = p.currentSong;
    self.titleLabel.text  = s[@"title"] ?: @"Not Playing";
    self.artistLabel.text = s[@"artist"];
    self.albumLabel.text  = s[@"album"];
    self.navigationItem.title = p.queue.count ? [NSString stringWithFormat:@"%d of %d", (int)p.index + 1, (int)p.queue.count] : @"Now Playing";
    NSString *sid = s[@"id"];
    if (![sid isEqual:self.shownSongID] || !self.artView.image) {
        BOOL songChanged = ![sid isEqual:self.shownSongID];
        self.shownSongID = sid;
        self.artView.image = [NVTheme placeholder];
        NSString *cid = s[@"coverArt"];
        [self.flipButton setCoverImage:nil];
        if (cid.length) {
            [NVImageLoader loadCover:cid size:320 completion:^(UIImage *img) {
                if (img && [self.shownSongID isEqual:sid]) self.artView.image = img;
            }];
            [NVImageLoader loadCover:cid size:30 completion:^(UIImage *img) {
                if (img && [self.shownSongID isEqual:sid]) [self.flipButton setCoverImage:img];
            }];
        }
        if (songChanged && self.mode == NVNPModeLyrics) [self loadLyrics];
    }
    if (self.mode == NVNPModeTracks) [self.tracks reloadData];
    [self reloadState];
}

- (void)reloadState {
    NVPlayer *p = [NVPlayer shared];
    self.playButton.glyph = p.isPlaying ? NVGlyphPause : NVGlyphPlay;
    self.shuffleButton.active = p.shuffle;
    self.repeatButton.glyph = (p.repeatMode == 2) ? NVGlyphRepeatOne : NVGlyphRepeat;
    self.repeatButton.active = p.repeatMode > 0;
    self.starButton.active = [[NVFavorites shared] isStarred:p.currentSong[@"id"]];
    self.lyricsButton.active = self.mode == NVNPModeLyrics;
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

- (UIView *)viewForMode:(NVNPMode)m {
    return m == NVNPModeTracks ? (UIView *)self.tracks : (m == NVNPModeLyrics ? (UIView *)self.lyricsView : (UIView *)self.artView);
}

- (void)setMode:(NVNPMode)m {
    if (m == _mode) return;
    UIView *from = [self viewForMode:_mode], *to = [self viewForMode:m];
    _mode = m;
    if (m == NVNPModeTracks) {
        [self.tracks reloadData];
        NVPlayer *p = [NVPlayer shared];
        if (p.index >= 0 && p.index < (NSInteger)p.queue.count)
            [self.tracks scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:p.index inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    }
    if (m == NVNPModeLyrics) [self loadLyrics];
    if (m != NVNPModeArt) {
        [UIView animateWithDuration:.2 animations:^{ self.extras.alpha = 0; }];
    }
    [UIView transitionFromView:from toView:to duration:0.7
        options:(m == NVNPModeArt ? UIViewAnimationOptionTransitionFlipFromLeft : UIViewAnimationOptionTransitionFlipFromRight) | UIViewAnimationOptionShowHideTransitionViews
        completion:nil];
    [self.flipButton setShowsCover:(m != NVNPModeArt) animated:YES];
    [self.lyricsTimer invalidate]; self.lyricsTimer = nil;
    if (m == NVNPModeLyrics) self.lyricsTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(lyricsTick) userInfo:nil repeats:YES];
    [self reloadState];
}

- (void)loadLyrics {
    NSDictionary *s = [NVPlayer shared].currentSong;
    if (!s) { [self.lyricsView showMessage:@"Nothing is playing."]; return; }
    NSString *sid = s[@"id"];
    if ([sid isEqualToString:self.lyricsSongID]) return;
    self.lyricsSongID = sid;
    [self.lyricsView showMessage:@"Loading lyrics\u2026"];
    [NVLyrics fetchForSong:s completion:^(NSArray *lines, NSArray *times, NSString *err) {
        if (![self.lyricsSongID isEqualToString:sid]) return;
        if (lines.count) {
            [self.lyricsView setLines:lines times:times];
        } else {
            [self.lyricsView showMessage:err ?: @"No lyrics found."];
            self.lyricsSongID = nil;
        }
    }];
}

- (void)closeModal { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }

- (void)titleTapped {
    NSDictionary *s = [NVPlayer shared].currentSong;
    if (!s) return;
    BOOL hasAlbum = [[s[@"albumId"] description] length] > 0, hasArtist = [[s[@"artistId"] description] length] > 0;
    if (!hasAlbum && !hasArtist) return;
    self.sheetSong = s;
    NSString *head = [s[@"artist"] length] ? [NSString stringWithFormat:@"%@ \u2014 %@", s[@"title"] ?: @"", s[@"artist"]] : (s[@"title"] ?: @"");
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:head delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    if (hasAlbum) [sheet addButtonWithTitle:@"Go to Album"];
    if (hasArtist) [sheet addButtonWithTitle:@"Go to Artist"];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"Cancel"];
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex || !self.sheetSong) return;
    NSString *t = [sheet buttonTitleAtIndex:i];
    NSDictionary *s = self.sheetSong;
    NVBrowserViewController *vc = nil;
    if ([t isEqualToString:@"Go to Album"]) {
        vc = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:[s[@"albumId"] description]
                                                     title:[s[@"album"] description] ?: @"Album" coverArt:s[@"coverArt"]];
    } else if ([t isEqualToString:@"Go to Artist"]) {
        vc = [[NVBrowserViewController alloc] initWithKind:NVBrowseArtistAlbums itemID:[s[@"artistId"] description]
                                                     title:[s[@"artist"] description] ?: @"Artist" coverArt:nil];
    }
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

- (void)toggleExtras {
    if (self.mode != NVNPModeArt) return;
    BOOL show = self.extras.alpha < .5;
    [UIView animateWithDuration:.25 animations:^{ self.extras.alpha = show ? 1 : 0; }];
}

- (void)lyricsTick { [self.lyricsView updateTime:[NVPlayer shared].currentTime]; }

- (void)doubleTapArt { [self setMode:NVNPModeTracks]; }
- (void)toggleTracks { [self setMode:self.mode == NVNPModeArt ? NVNPModeTracks : NVNPModeArt]; }
- (void)lyricsTap    { [self setMode:self.mode == NVNPModeLyrics ? NVNPModeArt : NVNPModeLyrics]; }

- (void)scrubBegan   { self.scrubbing = YES; }
- (void)scrubChanged { [self tick]; }
- (void)scrubEnded   { [[NVPlayer shared] seekToTime:self.slider.value]; self.scrubbing = NO; }
- (void)prevTap { [[NVPlayer shared] previous]; }
- (void)playTap { [[NVPlayer shared] togglePlayPause]; }
- (void)nextTap { [[NVPlayer shared] next]; }
- (void)shuffleTap { [NVPlayer shared].shuffle = ![NVPlayer shared].shuffle; }
- (void)repeatTap  { [NVPlayer shared].repeatMode = ([NVPlayer shared].repeatMode + 1) % 3; }
- (void)starTap { NSDictionary *s = [NVPlayer shared].currentSong; if (s) [[NVFavorites shared] toggleSong:s]; }

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

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv editingStyleForRowAtIndexPath:(NSIndexPath *)ip { return UITableViewCellEditingStyleDelete; }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    if (style == UITableViewCellEditingStyleDelete) [[NVPlayer shared] removeQueueIndex:ip.row];
}

- (void)tableView:(UITableView *)tv moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    NVPlayer *p = [NVPlayer shared];
    [p moveQueueIndex:from.row toIndex:to.row];
    self.navigationItem.title = [NSString stringWithFormat:@"%d of %d", (int)p.index + 1, (int)p.queue.count];
    [NSObject cancelPreviousPerformRequestsWithTarget:self.tracks selector:@selector(reloadData) object:nil];
    [self.tracks performSelector:@selector(reloadData) withObject:nil afterDelay:0.45];
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
    UINavigationController *nav = self.navigationController;
    if ([nav.topViewController isKindOfClass:[NVNowPlayingViewController class]]) return;
    UIViewController *top = NVTopViewController();
    if ([top isKindOfClass:[UINavigationController class]] && [((UINavigationController *)top).topViewController isKindOfClass:[NVNowPlayingViewController class]]) return;
    UITabBarController *tbc = self.tabBarController;
    BOOL inMore = nav && (nav == tbc.moreNavigationController || [nav.parentViewController isKindOfClass:[UINavigationController class]]);
    NVNowPlayingViewController *np = [[NVNowPlayingViewController alloc] init];
    if (inMore) {
        np.presentedModally = YES;
        UINavigationController *wrap = [[UINavigationController alloc] initWithRootViewController:np];
        wrap.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        [top presentViewController:wrap animated:YES completion:nil];
    } else {
        [nav pushViewController:np animated:YES];
    }
}

- (void)nv_updateNowPlayingButton {}

@end
