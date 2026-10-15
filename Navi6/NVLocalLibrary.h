#import <Foundation/Foundation.h>

@interface NVLocalLibrary : NSObject
+ (NSArray *)songs;
+ (NSArray *)albums;
+ (NSArray *)artists;
+ (NSArray *)genres;
+ (NSArray *)songsForAlbumID:(NSString *)albumID;
+ (NSArray *)albumsForArtistID:(NSString *)artistID;
+ (NSArray *)albumsForGenre:(NSString *)genre;
+ (NSArray *)songsFiltered:(NSString *)query;
+ (NSSet *)albumKeys;
+ (NSSet *)artistKeys;
@end
