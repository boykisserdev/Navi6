#import <UIKit/UIKit.h>

@interface NVPlaylists : NSObject
+ (void)promptCreateWithSongs:(NSArray *)songIDs completion:(void (^)(BOOL ok))completion;
+ (void)presentPickerForSongs:(NSArray *)songIDs;
+ (void)removeIndex:(NSInteger)index fromPlaylistID:(NSString *)pid completion:(void (^)(BOOL ok))completion;
+ (void)deletePlaylistID:(NSString *)pid completion:(void (^)(BOOL ok))completion;
@end
