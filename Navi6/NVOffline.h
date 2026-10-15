#import <UIKit/UIKit.h>

extern NSString * const NVOfflineChangedNotification;

@interface NVOffline : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL isOffline;
@property (nonatomic, readonly) BOOL networkReachable;
@property (nonatomic) BOOL manualOffline;
- (void)showOfflineAlert;
- (UIBarButtonItem *)cloudItem;
@end
