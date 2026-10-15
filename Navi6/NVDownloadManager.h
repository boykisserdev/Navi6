#import <Foundation/Foundation.h>

@interface NVDownloadManager : NSObject
+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray *pending;
@property (nonatomic, copy, readonly) NSString *lastError;

- (void)enqueueSongs:(NSArray *)songs;
- (BOOL)isDownloaded:(NSString *)songID;
- (BOOL)isPending:(NSString *)songID;
- (BOOL)isActive:(NSString *)songID;
- (float)progressForSongID:(NSString *)songID;
- (NSInteger)activeCount;
- (void)kick;
- (NSURL *)localURLForSongID:(NSString *)songID;
- (NSArray *)downloadedSongs;
- (void)deleteSongID:(NSString *)songID;
- (void)deleteAll;
- (void)cancelPending;
- (long long)totalBytes;
@end
