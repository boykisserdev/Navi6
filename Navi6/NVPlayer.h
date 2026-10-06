#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface NVPlayer : NSObject
+ (instancetype)shared;

@property (nonatomic, strong, readonly) NSArray *queue;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, strong, readonly) NSDictionary *currentSong;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic) BOOL shuffle;
@property (nonatomic) NSInteger repeatMode;      // 0 off, 1 all, 2 one

- (void)playSongs:(NSArray *)songs startIndex:(NSInteger)index;
- (void)playSongs:(NSArray *)songs startIndex:(NSInteger)index shuffled:(BOOL)shuffled;
- (void)play;
- (void)pause;
- (void)togglePlayPause;
- (void)next;
- (void)previous;
- (void)seekToTime:(NSTimeInterval)t;
- (void)addNext:(NSDictionary *)song;
- (void)addToQueue:(NSDictionary *)song;
- (void)jumpToIndex:(NSInteger)index;
- (void)removeQueueIndex:(NSInteger)index;
- (void)handleRemoteEvent:(UIEvent *)event;
@end
