#import "NVImageViewerController.h"
#import "NVClient.h"
#import "NVTheme.h"

@interface NVImageViewerController () <UIScrollViewDelegate>
@property (nonatomic, copy) NSString *coverID, *titleText;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation NVImageViewerController

+ (void)presentCoverID:(NSString *)cid placeholder:(UIImage *)ph title:(NSString *)title {
    NVImageViewerController *v = [[NVImageViewerController alloc] init];
    v.coverID = cid; v.image = ph; v.titleText = title;
    v.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [NVTopViewController() presentViewController:v animated:YES completion:nil];
}

- (BOOL)shouldAutorotate { return YES; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scroll.delegate = self;
    self.scroll.minimumZoomScale = 1; self.scroll.maximumZoomScale = 4;
    self.scroll.showsHorizontalScrollIndicator = NO; self.scroll.showsVerticalScrollIndicator = NO;
    self.scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scroll];
    self.imageView = [[UIImageView alloc] initWithImage:self.image];
    [self.scroll addSubview:self.imageView];

    self.caption = [[UILabel alloc] init];
    self.caption.backgroundColor = [UIColor clearColor];
    self.caption.textColor = [UIColor colorWithWhite:.85 alpha:1];
    self.caption.font = [UIFont boldSystemFontOfSize:14];
    self.caption.textAlignment = NSTextAlignmentCenter;
    self.caption.shadowColor = [UIColor blackColor]; self.caption.shadowOffset = CGSizeMake(0, -1);
    self.caption.text = self.titleText;
    self.caption.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.caption];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    self.spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:self.spinner];
    [self.spinner startAnimating];

    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapped:)];
    dbl.numberOfTapsRequired = 2;
    UITapGestureRecognizer *single = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    [single requireGestureRecognizerToFail:dbl];
    [self.scroll addGestureRecognizer:dbl];
    [self.scroll addGestureRecognizer:single];

    [NVImageLoader loadFullCover:self.coverID maxPixels:1200 completion:^(UIImage *img) {
        [self.spinner stopAnimating];
        if (!img) return;
        self.image = img;
        self.imageView.image = img;
        self.scroll.zoomScale = 1;
        [self fitImage];
    }];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.caption.frame = CGRectMake(10, self.view.bounds.size.height - 36, self.view.bounds.size.width - 20, 20);
    self.spinner.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
    if (self.scroll.zoomScale <= 1.01) [self fitImage];
}

- (void)fitImage {
    CGSize b = self.scroll.bounds.size, i = self.image.size;
    if (i.width <= 0 || i.height <= 0) return;
    CGFloat s = MIN(b.width / i.width, b.height / i.height);
    self.imageView.frame = CGRectMake((b.width - i.width * s) / 2, (b.height - i.height * s) / 2, i.width * s, i.height * s);
    self.scroll.contentSize = b;
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)sv { return self.imageView; }

- (void)scrollViewDidZoom:(UIScrollView *)sv {
    CGSize b = sv.bounds.size; CGRect f = self.imageView.frame;
    f.origin.x = f.size.width < b.width ? (b.width - f.size.width) / 2 : 0;
    f.origin.y = f.size.height < b.height ? (b.height - f.size.height) / 2 : 0;
    self.imageView.frame = f;
}

- (void)doubleTapped:(UITapGestureRecognizer *)g {
    if (self.scroll.zoomScale > 1.01) { [self.scroll setZoomScale:1 animated:YES]; return; }
    CGPoint p = [g locationInView:self.imageView];
    CGSize b = self.scroll.bounds.size;
    CGFloat z = 2.5;
    [self.scroll zoomToRect:CGRectMake(p.x - b.width / (2 * z), p.y - b.height / (2 * z), b.width / z, b.height / z) animated:YES];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

@end
