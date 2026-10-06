#import "NVAlbumGridViewController.h"
#import "NVBrowserViewController.h"
#import "NVClient.h"
#import "NVSettings.h"
#import "NVTheme.h"

@interface NVAlbumCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *art;
@property (nonatomic, strong) UILabel *titleLabel, *artistLabel;
@property (nonatomic, copy) NSString *coverID;
@end

@implementation NVAlbumCell
- (id)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) {
        UIView *bezel = [[UIView alloc] initWithFrame:CGRectMake(10, 8, 160, 160)];
        bezel.backgroundColor = [UIColor colorWithRed:.96 green:.96 blue:.94 alpha:1];
        bezel.layer.shadowColor = [UIColor blackColor].CGColor;
        bezel.layer.shadowOpacity = .8; bezel.layer.shadowRadius = 5; bezel.layer.shadowOffset = CGSizeMake(0, 3);
        bezel.layer.shadowPath = [UIBezierPath bezierPathWithRect:bezel.bounds].CGPath;
        [self.contentView addSubview:bezel];
        self.art = [[UIImageView alloc] initWithFrame:CGRectMake(14, 12, 152, 152)];
        self.art.contentMode = UIViewContentModeScaleAspectFill;
        self.art.clipsToBounds = YES;
        [self.contentView addSubview:self.art];
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 176, 172, 18)];
        self.titleLabel.backgroundColor = [UIColor clearColor];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.shadowColor = [UIColor blackColor]; self.titleLabel.shadowOffset = CGSizeMake(0, -1);
        self.artistLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 194, 172, 16)];
        self.artistLabel.backgroundColor = [UIColor clearColor];
        self.artistLabel.textColor = [UIColor colorWithWhite:.65 alpha:1];
        self.artistLabel.font = [UIFont systemFontOfSize:12];
        self.artistLabel.textAlignment = NSTextAlignmentCenter;
        self.artistLabel.shadowColor = [UIColor blackColor]; self.artistLabel.shadowOffset = CGSizeMake(0, -1);
        [self.contentView addSubview:self.titleLabel]; [self.contentView addSubview:self.artistLabel];
    }
    return self;
}
@end


@interface NVAlbumGridViewController ()
@property (nonatomic, strong) NSMutableArray *albums;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic) BOOL loading;
@property (nonatomic) NSInteger generation;
@end

@implementation NVAlbumGridViewController

- (id)init {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(180, 218);
    layout.minimumLineSpacing = 14;
    layout.minimumInteritemSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(20, 16, 20, 16);
    self = [super initWithCollectionViewLayout:layout];
    if (self) { self.title = @"Albums"; _albums = [NSMutableArray array]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.collectionView.backgroundColor = [NVTheme linenColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[NVAlbumCell class] forCellWithReuseIdentifier:@"album"];
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 400, 60)];
    self.statusLabel.backgroundColor = [UIColor clearColor];
    self.statusLabel.textColor = [UIColor colorWithWhite:.7 alpha:1];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.collectionView addSubview:self.statusLabel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.albums.count && !self.loading) [self loadFromOffset:0];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.statusLabel.center = CGPointMake(self.collectionView.bounds.size.width / 2, 160);
}

- (void)loadFromOffset:(NSInteger)offset {
    if (![NVSettings shared].isConfigured) { self.statusLabel.text = @"Set up your server:\nMore \u203A Settings"; self.statusLabel.hidden = NO; return; }
    self.loading = YES;
    if (!offset) { self.statusLabel.text = @"Loading\u2026"; self.statusLabel.hidden = NO; }
    [[NVClient shared] request:@"getAlbumList2" params:@{ @"type": @"alphabeticalByArtist", @"size": @500, @"offset": @(offset) }
                    completion:^(NSDictionary *r, NSError *e) {
        if (e) { self.loading = NO; self.statusLabel.text = [e.localizedDescription stringByAppendingString:@"\nOpen another tab and come back to retry."]; return; }
        NSArray *list = NVArray(r[@"albumList2"][@"album"]);
        [self.albums addObjectsFromArray:list];
        self.statusLabel.hidden = self.albums.count > 0;
        if (!self.albums.count) self.statusLabel.text = @"No albums.";
        [self.collectionView reloadData];
        if (list.count >= 500 && self.albums.count < 3000) [self loadFromOffset:self.albums.count];
        else self.loading = NO;
    }];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return self.albums.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    NVAlbumCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"album" forIndexPath:ip];
    NSDictionary *a = self.albums[ip.item];
    cell.titleLabel.text = a[@"name"] ?: a[@"title"];
    cell.artistLabel.text = a[@"artist"];
    NSString *cid = a[@"coverArt"];
    cell.coverID = cid ?: @"";
    cell.art.image = [NVTheme placeholder];
    if (cid.length) {
        [NVImageLoader loadCover:cid size:152 completion:^(UIImage *img) {
            if (img && [cell.coverID isEqualToString:cid]) cell.art.image = img;
        }];
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *a = self.albums[ip.item];
    NVBrowserViewController *vc = [[NVBrowserViewController alloc] initWithKind:NVBrowseAlbumSongs itemID:a[@"id"]
                                                                          title:a[@"name"] ?: a[@"title"] coverArt:a[@"coverArt"]];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
