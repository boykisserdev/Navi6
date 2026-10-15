#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NVBrowseKind) {
    NVBrowseArtists, NVBrowseAlbums, NVBrowsePlaylists,
    NVBrowseArtistAlbums, NVBrowseAlbumSongs, NVBrowsePlaylistSongs,
    NVBrowseSongs,
    NVBrowseGenres, NVBrowseGenreAlbums
};

@interface NVBrowserViewController : UITableViewController
- (id)initRootKind:(NVBrowseKind)kind;
- (id)initWithKind:(NVBrowseKind)kind itemID:(NSString *)itemID title:(NSString *)title coverArt:(NSString *)coverArt;
@end
