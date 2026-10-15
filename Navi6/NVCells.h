#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NVItemType) {
    NVItemArtist, NVItemAlbum, NVItemPlaylist,
    NVItemSong,
    NVItemSongNumbered,
    NVItemGenre
};

@interface NVCells : NSObject
+ (UITableViewCell *)cellForTableView:(UITableView *)tv item:(NSDictionary *)item type:(NVItemType)type;
+ (UITableViewCell *)messageCellForTableView:(UITableView *)tv text:(NSString *)text;
+ (UITableViewCell *)shuffleCellForTableView:(UITableView *)tv count:(NSInteger)count;
+ (void)showActionsForSong:(NSDictionary *)song;
@end
