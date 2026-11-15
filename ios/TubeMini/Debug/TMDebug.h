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
///   avplay <url>        play the URL in a headless AVPlayer (to inspect tracks)
///   avstatus            log the AVPlayer item: status, position, size, video/audio tracks, access log
///   avstop              stop the AVPlayer
///   seek <seconds>      jump the player to a position
///   stop                close the player
///   mark <text>         write a marker line to the log
/// UI automation (drives the real screens):
///   server <url>        set the server address        quality <360|720|1080> default quality
///   tab <n>             select tab (0 home, 1 search, 2 subscriptions, 3 history, 4 downloads, 5 settings)
///   search <q>          search videos ("search ch:<q>" for channels)
///   open <row>          tap row <row> of the list on screen
///   playbtn             tap Play on the video screen   section <0|1>  related / comments (video page),
///                                                                     videos / playlists (channel page)
///   subbtn              tap Subscribe (video or channel page)          channel <id>  open a channel page
///   homesource subs|popular   home feed                refresh       home refresh button / pull to refresh
///   delrow <row>        swipe row <row> away (subscriptions, history)  clearhistory  "Xoá hết" (history)
///   listenbtn / dlbtn   tap "Chỉ nghe" / "Tải về" on the video page    downloads     log the downloads
///   dlq <quality>       download the open video at 360 / 720 / 1080 (no choice sheet)
///   dldel <video id>    delete a download
///   opendl <row>        tap a row of "Đã tải"                          nowplaying    log the lock screen info
///   proxy on|off        "Phát qua máy chủ"                             bonjour       "Tìm máy chủ trong mạng"
///   audio [status|toggle|seek <s>|skip <s>|stop]   the "Chỉ nghe" player behind the mini bar
///   update [status|check|install|feed <url>]        OTA app update (feed: another update.json for tests)
///   scrollend           scroll the list to the bottom (loads the next page)
///   back                pop the current screen          pingtest      run "Kiểm tra kết nối"
///   dismissalert        log and close visible alerts    ui            log the current screen
///   mem                 log the app's resident memory
///   theme dark|light    switch the colour theme         homemode grid|list   home layout
@interface TMDebug : NSObject
+ (void)start;
@end
