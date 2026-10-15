#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NSArray *NVArray(id obj);
NSString *NVURLEscape(NSString *s);

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

+ (void)loadCover:(NSString *)coverID size:(CGFloat)points completion:(void (^)(UIImage *image))completion;
+ (void)saveOfflineCover:(NSString *)coverID;
+ (void)clearMemoryCache;

+ (void)loadFullCover:(NSString *)coverID maxPixels:(int)px completion:(void (^)(UIImage *image))completion;
@end
