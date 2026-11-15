#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "TMModels.h"

/// Playback flow: ask `/tm/v1/videos/{id}/streams`, wait out `available_in` (pre-roll ad window,
/// with a countdown), play in MPMoviePlayerViewController, retry once with `fresh=1` on error,
/// then offer 360p. Only one playback at a time. The watch position goes to `/tm/v1/history` every
/// 15 seconds, when the player closes and when the app goes to the background.
@interface TMPlayer : NSObject <UIAlertViewDelegate>
+ (instancetype)shared;
- (void)playVideo:(TMVideo *)video quality:(NSInteger)quality from:(UIViewController *)presenter;
/// `seconds` > 0 resumes there.
- (void)playVideo:(TMVideo *)video quality:(NSInteger)quality startAt:(NSInteger)seconds from:(UIViewController *)presenter;
/// Audio only (`<tm:audio>`, falls back to 360p video): handed to TMAudioPlayer, which keeps playing
/// while the user browses, with the screen locked or in the background (mini bar above the tab bar).
- (void)playAudioOf:(TMVideo *)video startAt:(NSInteger)seconds from:(UIViewController *)presenter;
/// A downloaded file (offline).
- (void)playFile:(NSString *)path video:(TMVideo *)video startAt:(NSInteger)seconds from:(UIViewController *)presenter;
/// Lock screen / headphone remote events (forwarded by the app delegate).
- (void)remoteControl:(UIEvent *)event;
/// The movie player while one is on screen (nil otherwise); used by the debug commands.
@property (nonatomic, readonly) MPMoviePlayerController *moviePlayer;
/// Quality actually playing ("360p", "720p (HLS)"), for status text.
@property (nonatomic, readonly, copy) NSString *playingLabel;
@end
