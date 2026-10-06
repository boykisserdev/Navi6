#import <UIKit/UIKit.h>

extern NSString * const NVPlayerChangedNotification;
extern NSString * const NVDownloadsChangedNotification;
extern NSString * const NVDownloadProgressNotification;
extern NSString * const NVFavoritesChangedNotification;

@interface NVTheme : NSObject
+ (void)applyAppearance;
+ (UIColor *)linenColor;
+ (UIImage *)placeholder;
+ (UIColor *)barTint;
+ (UIImage *)tabIconNamed:(NSString *)name;   // playlists artists albums favorites more downloads settings (template images)
+ (UIImage *)tintedTabIcon:(NSString *)name color:(UIColor *)color;
+ (UIImage *)shuffleRowIcon;
+ (UIImage *)speakerIcon;                 // "now playing" marker in the track list
+ (UIImage *)blankSpeakerIcon;            // same size, transparent (keeps rows aligned)
+ (UIImage *)listIcon;                    // nav-bar "track list" template icon
+ (NSString *)timeString:(NSTimeInterval)t;
+ (NSString *)sizeString:(long long)bytes;
@end

// ---- Glossy iOS 6 style push button ----
typedef NS_ENUM(NSInteger, NVButtonStyle) { NVButtonStyleBlue, NVButtonStyleGraphite, NVButtonStyleRed };
@interface NVGlossyButton : UIButton
@property (nonatomic) NVButtonStyle style;
+ (instancetype)buttonWithTitle:(NSString *)title style:(NVButtonStyle)style;
@end

// ---- Chrome transport buttons drawn with Core Graphics ----
typedef NS_ENUM(NSInteger, NVGlyph) { NVGlyphPlay, NVGlyphPause, NVGlyphPrev, NVGlyphNext, NVGlyphShuffle, NVGlyphRepeat, NVGlyphRepeatOne, NVGlyphStar, NVGlyphQueue };
@interface NVTransportButton : UIButton
@property (nonatomic) NVGlyph glyph;
@property (nonatomic) BOOL active;
- (id)initWithGlyph:(NVGlyph)glyph;
@end

// ---- Dark glass panel (bottom of Now Playing) ----
@interface NVGlassView : UIView @end

// ---- Light brushed header for album/playlist screens ----
@interface NVHeaderView : UIView @end
