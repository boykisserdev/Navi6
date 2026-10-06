#import <UIKit/UIKit.h>
#import "NVTheme.h"

@interface NVMiniPlayerView : NVGlassView
@property (nonatomic, copy) void (^onTap)(void);
- (void)refresh;
@end
