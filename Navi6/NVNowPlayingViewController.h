#import <UIKit/UIKit.h>

@interface NVNowPlayingViewController : UIViewController
@end

@interface UIViewController (NVNowPlaying)
- (void)nv_openNowPlaying;
- (void)nv_updateNowPlayingButton;   // shows a "Now Playing" bar button while something is loaded
@end
