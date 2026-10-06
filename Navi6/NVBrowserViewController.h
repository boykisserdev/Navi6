#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NVBrowseKind) {
    NVBrowseArtists, NVBrowseAlbums, NVBrowsePlaylists,
    NVBrowseArtistAlbums, NVBrowseAlbumSongs, NVBrowsePlaylistSongs,
    NVBrowseSongs                      // whole library, A-Z with index
};

@interface NVBrowserViewController : UITableViewController
- (id)initRootKind:(NVBrowseKind)kind;   // Artists / Albums / Playlists tab roots (with search bar)
- (id)initWithKind:(NVBrowseKind)kind itemID:(NSString *)itemID title:(NSString *)title coverArt:(NSString *)coverArt;
@end
