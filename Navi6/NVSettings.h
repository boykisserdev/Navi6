#import <Foundation/Foundation.h>

NSString *NVMusicDirectory(void);

@interface NVSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic) NSInteger transcodeBitrate;
@property (nonatomic) NSInteger maxConcurrentDownloads;
@property (nonatomic) NSInteger lyricsSource;
@property (nonatomic) BOOL offlineMode;
@property (nonatomic, readonly) BOOL isConfigured;
@end
