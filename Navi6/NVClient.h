#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// JSON from Subsonic may give a dict instead of a 1-element array
NSArray *NVArray(id obj);

@interface NVClient : NSObject
+ (instancetype)shared;
- (NSURL *)URLForEndpoint:(NSString *)name params:(NSDictionary *)params;
- (void)request:(NSString *)endpoint params:(NSDictionary *)params
     completion:(void (^)(NSDictionary *response, NSError *error))completion;
- (void)ping:(void (^)(NSError *error))completion;
- (NSURL *)streamURLForSong:(NSDictionary *)song;
- (NSString *)fileExtensionForSong:(NSDictionary *)song;
- (void)scrobbleSongID:(NSString *)songID submission:(BOOL)submission;
@end

@interface NVImageLoader : NSObject
// completion always runs on the main queue (synchronously if the image is in memory)
+ (void)loadCover:(NSString *)coverID size:(CGFloat)points completion:(void (^)(UIImage *image))completion;
+ (void)saveOfflineCover:(NSString *)coverID;
@end
