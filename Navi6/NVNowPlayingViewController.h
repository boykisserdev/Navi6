#import <UIKit/UIKit.h>

@interface NVNowPlayingViewController : UIViewController
@end

@interface UIViewController (NVNowPlaying)
- (void)nv_openNowPlaying;
- (void)nv_updateNowPlayingButton;
@end
