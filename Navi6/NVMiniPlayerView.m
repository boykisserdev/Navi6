#import "NVMiniPlayerView.h"
#import "NVPlayer.h"
#import "NVClient.h"

static UILabel *NVMiniLabel(UIFont *font, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.backgroundColor = [UIColor clearColor];
    l.font = font; l.textColor = color;
    l.shadowColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.85];
    l.shadowOffset = CGSizeMake(0, -1);
    return l;
}

@interface NVMiniPlayerView () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *titleLabel, *artistLabel;
@property (nonatomic, strong) NVTransportButton *playButton, *nextButton;
@property (nonatomic, strong) UIView *progress;
@property (nonatomic, copy) NSString *shownID;
@end

@implementation NVMiniPlayerView

- (id)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        self.art = [[UIImageView alloc] init];
        self.art.contentMode = UIViewContentModeScaleAspectFill;
        self.art.clipsToBounds = YES;
        self.art.layer.borderColor = [UIColor colorWithWhite:.92 alpha:1].CGColor;
        self.art.layer.borderWidth = 1.5;
        [self addSubview:self.art];

        self.titleLabel  = NVMiniLabel([UIFont boldSystemFontOfSize:14], [UIColor whiteColor]);
        self.artistLabel = NVMiniLabel([UIFont systemFontOfSize:12], [UIColor colorWithWhite:.70 alpha:1]);
        [self addSubview:self.titleLabel]; [self addSubview:self.artistLabel];

        self.progress = [[UIView alloc] init];
        self.progress.backgroundColor = [UIColor colorWithRed:.30 green:.62 blue:1 alpha:1];
        [self addSubview:self.progress];

        self.playButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphPlay];
        self.nextButton = [[NVTransportButton alloc] initWithGlyph:NVGlyphNext];
        [self.playButton addTarget:self action:@selector(playTap) forControlEvents:UIControlEventTouchUpInside];
        [self.nextButton addTarget:self action:@selector(nextTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.playButton]; [self addSubview:self.nextButton];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    return ![t.view isKindOfClass:[UIControl class]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    self.art.frame = CGRectMake(8, 6, 36, 36);
    self.titleLabel.frame  = CGRectMake(52, 6,  w - 52 - 108, 19);
    self.artistLabel.frame = CGRectMake(52, 25, w - 52 - 108, 16);
    self.playButton.frame = CGRectMake(w - 108, 0, 54, h);
    self.nextButton.frame = CGRectMake(w - 54,  0, 54, h);
}

- (void)tapped { if (self.onTap) self.onTap(); }
- (void)playTap { [[NVPlayer shared] togglePlayPause]; }
- (void)nextTap { [[NVPlayer shared] next]; }

- (void)refresh {
    NVPlayer *p = [NVPlayer shared];
    NSDictionary *s = p.currentSong;
    self.titleLabel.text = s[@"title"];
    self.artistLabel.text = s[@"artist"];
    NSString *sid = s[@"id"];
    if (![sid isEqual:self.shownID]) {
        self.shownID = sid;
        self.art.image = [NVTheme placeholder];
        NSString *cid = s[@"coverArt"];
        if (cid.length) {
            [NVImageLoader loadCover:cid size:36 completion:^(UIImage *img) {
                if (img && [self.shownID isEqual:sid]) self.art.image = img;
            }];
        }
    }
    self.playButton.glyph = p.isPlaying ? NVGlyphPause : NVGlyphPlay;
    NSTimeInterval d = p.duration;
    CGFloat frac = d > 0 ? MIN(1, p.currentTime / d) : 0;
    self.progress.frame = CGRectMake(0, 2, self.bounds.size.width * frac, 2);
}

@end
