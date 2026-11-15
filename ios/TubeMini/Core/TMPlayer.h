#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import "TMModels.h"

/// Playback flow: ask `/tm/v1/videos/{id}/streams`, wait out `available_in` (pre-roll ad window,
/// with a countdown), play in MPMoviePlayerViewController, retry once with `fresh=1` on error,
/// then offer 360p. Only one playback at a time.
@interface TMPlayer : NSObject <UIAlertViewDelegate>
+ (instancetype)shared;
- (void)playVideo:(TMVideo *)video quality:(NSInteger)quality from:(UIViewController *)presenter;
/// The movie player while one is on screen (nil otherwise); used by the debug commands.
@property (nonatomic, readonly) MPMoviePlayerController *moviePlayer;
/// Quality actually playing ("360p", "720p (HLS)"), for status text.
@property (nonatomic, readonly, copy) NSString *playingLabel;
@end
