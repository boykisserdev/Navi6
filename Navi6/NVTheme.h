#import <UIKit/UIKit.h>

extern NSString * const NVPlayerChangedNotification;
extern NSString * const NVDownloadsChangedNotification;
extern NSString * const NVDownloadProgressNotification;
extern NSString * const NVFavoritesChangedNotification;
extern NSString * const NVPlaylistsChangedNotification;

UIViewController *NVTopViewController(void);

@interface NVTheme : NSObject
+ (void)applyAppearance;
+ (UIColor *)linenColor;
+ (UIImage *)placeholder;
+ (UIColor *)barTint;
+ (UIImage *)tabIconNamed:(NSString *)name;
+ (UIImage *)tintedTabIcon:(NSString *)name color:(UIColor *)color;
+ (UIImage *)shuffleRowIcon;
+ (UIImage *)speakerIcon;
+ (UIImage *)blankSpeakerIcon;
+ (UIImage *)volumeIconMax:(BOOL)max;
+ (UIImage *)cloudOfflineIcon;
+ (UIImage *)listIcon;
+ (NSString *)timeString:(NSTimeInterval)t;
+ (NSString *)sizeString:(long long)bytes;
@end

typedef NS_ENUM(NSInteger, NVButtonStyle) { NVButtonStyleBlue, NVButtonStyleGraphite, NVButtonStyleRed };
@interface NVGlossyButton : UIButton
@property (nonatomic) NVButtonStyle style;
+ (instancetype)buttonWithTitle:(NSString *)title style:(NVButtonStyle)style;
@end

typedef NS_ENUM(NSInteger, NVGlyph) { NVGlyphPlay, NVGlyphPause, NVGlyphPrev, NVGlyphNext, NVGlyphShuffle, NVGlyphRepeat, NVGlyphRepeatOne, NVGlyphStar, NVGlyphQueue, NVGlyphLyrics };
@interface NVTransportButton : UIButton
@property (nonatomic) NVGlyph glyph;
@property (nonatomic) BOOL active;
- (id)initWithGlyph:(NVGlyph)glyph;
@end

@interface NVGlassView : UIView @end

@interface NVHeaderView : UIView @end

typedef NS_ENUM(NSInteger, NVHeaderIcon) { NVHeaderIconStar, NVHeaderIconShare };
@interface NVHeaderIconButton : UIButton
@property (nonatomic) NVHeaderIcon icon;
@property (nonatomic) BOOL on;
+ (instancetype)buttonWithIcon:(NVHeaderIcon)icon;
@end
