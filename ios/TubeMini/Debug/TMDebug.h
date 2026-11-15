#import <Foundation/Foundation.h>

/// Debug-build-only remote control so tests can run over SSH without touching the screen.
/// Write commands (one per line) to Documents/TubeMini-cmd.txt; the app polls it, runs them in order
/// and deletes the file. Output goes to Documents/TubeMini.log, screenshots to Documents/TubeMini-shots/.
///
///   wait <seconds>      delay the remaining commands
///   shot <name>         screenshot (includes video frames) → TubeMini-shots/<name>.png
///   net <url>           fetch with NSURLConnection (iOS TLS stack), log status/bytes/type/time
///   play <url>          open MPMoviePlayerViewController with the URL and autoplay
///   status              log player state (playback/load state, size, position, access/error log)
///   frame <name>        save the decoded video frame at the current position → TubeMini-shots/<name>.jpg
///   seek <seconds>      jump the player to a position
///   stop                close the player
///   mark <text>         write a marker line to the log
@interface TMDebug : NSObject
+ (void)start;
@end
