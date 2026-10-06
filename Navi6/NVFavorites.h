#import <Foundation/Foundation.h>

// Starred items from the server (Subsonic star / unstar / getStarred2)
@interface NVFavorites : NSObject
+ (instancetype)shared;
@property (nonatomic, strong, readonly) NSArray *songs;
@property (nonatomic, strong, readonly) NSArray *albums;
@property (nonatomic, strong, readonly) NSArray *artists;
- (void)refresh;
- (BOOL)isStarred:(NSString *)songID;
- (void)toggleSong:(NSDictionary *)song;     // optimistic, reverts if the server call fails
@end
