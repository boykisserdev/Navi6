#import <Foundation/Foundation.h>

@interface NVFavorites : NSObject
+ (instancetype)shared;
@property (nonatomic, strong, readonly) NSArray *songs;
@property (nonatomic, strong, readonly) NSArray *albums;
@property (nonatomic, strong, readonly) NSArray *artists;
- (void)refresh;
- (BOOL)isStarred:(NSString *)songID;
- (BOOL)isAlbumStarred:(NSString *)albumID;
- (BOOL)isArtistStarred:(NSString *)artistID;
- (void)toggleSong:(NSDictionary *)song;
- (void)toggleAlbum:(NSDictionary *)album;
- (void)toggleArtist:(NSDictionary *)artist;
@end
