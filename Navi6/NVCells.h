#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NVItemType) {
    NVItemArtist, NVItemAlbum, NVItemPlaylist,
    NVItemSong,          // with cover thumbnail
    NVItemSongNumbered   // album track list: "3. Title", no thumbnail
};

@interface NVCells : NSObject
+ (UITableViewCell *)cellForTableView:(UITableView *)tv item:(NSDictionary *)item type:(NVItemType)type;
+ (UITableViewCell *)messageCellForTableView:(UITableView *)tv text:(NSString *)text;
+ (UITableViewCell *)shuffleCellForTableView:(UITableView *)tv count:(NSInteger)count;   // iOS 6 style "Shuffle" row
+ (void)showActionsForSong:(NSDictionary *)song;      // Play Next / Add to Queue / Download / Remove
@end
