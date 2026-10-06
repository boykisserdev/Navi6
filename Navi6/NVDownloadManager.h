#import <Foundation/Foundation.h>

@interface NVDownloadManager : NSObject
+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray *pending;              // first item = currently downloading
@property (nonatomic, readonly) float currentProgress;         // 0..1
@property (nonatomic, copy, readonly) NSString *lastError;

- (void)enqueueSongs:(NSArray *)songs;
- (BOOL)isDownloaded:(NSString *)songID;
- (BOOL)isPending:(NSString *)songID;
- (NSURL *)localURLForSongID:(NSString *)songID;
- (NSArray *)downloadedSongs;                                  // sorted artist / album / disc / track
- (void)deleteSongID:(NSString *)songID;
- (void)deleteAll;
- (void)cancelPending;
- (long long)totalBytes;
@end
