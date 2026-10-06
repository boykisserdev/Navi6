#import <Foundation/Foundation.h>

// Documents/Music — offline files, library.plist, covers/
NSString *NVMusicDirectory(void);

@interface NVSettings : NSObject
+ (instancetype)shared;
@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;          // stored in Keychain
@property (nonatomic) NSInteger transcodeBitrate;        // for formats iOS 6 can't play
@property (nonatomic, readonly) BOOL isConfigured;
@end
