#import <UIKit/UIKit.h>
#import "TMModels.h"

/// Posted (main thread) when audio starts / stops, plays / pauses, and about twice a second for the position.
extern NSString *const TMAudioPlayerDidChangeNotification;

/// "Chỉ nghe": an AVPlayer without a screen of its own, so the sound keeps going while the user
/// browses the app (TMAudioBar shows position / seek / play-pause above the tab bar), with the screen
/// locked or in the background. Lock screen: title / artwork, play / pause, ⏮ / ⏭ = −15 s / +15 s
/// (iOS 6 has no scrubber there). Saves the position to the history like the video player.
@interface TMAudioPlayer : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) TMVideo *video;
@property (nonatomic, readonly) BOOL active;   // something is loaded
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) NSTimeInterval position, duration;
- (void)playURL:(NSString *)url video:(TMVideo *)video startAt:(NSInteger)seconds;
- (void)togglePlay;
- (void)seekTo:(NSTimeInterval)seconds;
- (void)skip:(NSTimeInterval)delta;
/// Saves the position and unloads (the bar disappears).
- (void)stop;
- (void)remoteControl:(UIEvent *)event;
@end
