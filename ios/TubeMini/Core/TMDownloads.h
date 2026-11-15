#import <Foundation/Foundation.h>
#import "TMModels.h"

/// Posted (main thread) when a download is added, progresses, finishes, fails or is removed.
/// userInfo: @"videoID" (absent when the whole list changed).
extern NSString *const TMDownloadsDidChangeNotification;

typedef NS_ENUM(NSInteger, TMDownloadState) {
    TMDownloadWaiting,
    TMDownloadRunning,
    TMDownloadDone,
    TMDownloadFailed,
};

/// One saved (or saving) video: the 360p MP4 from `<tm:download>`, or an HLS level (720p / 1080p, or
/// 360p with the original audio) saved as segments + local playlists, played through TMLocalServer.
@interface TMDownload : NSObject
@property (nonatomic, copy) NSString *videoID, *title, *author, *authorID;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, assign) NSInteger quality;           // 360 / 720 / 1080 (real height once known)
@property (nonatomic, assign) BOOL hls;
@property (nonatomic, assign) TMDownloadState state;
@property (nonatomic, assign) long long received, total;   // bytes; total 0 = unknown (HLS: estimate)
@property (nonatomic, assign) NSInteger segmentsDone, segmentsTotal; // HLS
@property (nonatomic, copy) NSString *error;               // when failed
@property (nonatomic, assign) BOOL dubbed;                  // audio is an AI dub (D23)
@property (nonatomic, assign) NSInteger position;           // last watch position (offline resume)
@property (nonatomic, strong) NSDate *added;
/// What to play: the MP4, or the HLS master playlist.
- (NSString *)filePath;
- (TMVideo *)video;
/// "Đang tải 45% · 720p · 150 / 345 MB", "720p · 345 MB", "Lỗi: …".
- (NSString *)statusText;
@end

/// Downloads for offline viewing, one video at a time.
/// - MP4: resumed with HTTP Range after a drop or a restart.
/// - HLS: the server's filtered master for that level, then the googlevideo media playlists; every video
///   and audio segment is saved (3 at a time), existing ones are skipped on resume.
/// Either way a fresh link comes from `streams?fresh=1` when googlevideo refuses an expired one. Keeps
/// going for a few minutes in the background. Files: Documents/TubeMini-Downloads (no iCloud backup).
@interface TMDownloads : NSObject
+ (instancetype)shared;
/// Newest first.
@property (nonatomic, readonly) NSArray *items;
- (TMDownload *)itemFor:(NSString *)videoID;
/// 360p MP4.
- (void)add:(TMVideo *)video;
/// `hls` = segments of the HLS level `quality`; `estimate` (bytes, 0 = unknown) is checked against the free space.
- (void)add:(TMVideo *)video quality:(NSInteger)quality hls:(BOOL)hls estimate:(long long)estimate;
- (void)retry:(NSString *)videoID;
/// Cancels if running and deletes the files.
- (void)remove:(NSString *)videoID;
/// Starts the next waiting download (at launch, back in the foreground).
- (void)resume;
/// Bytes used by finished and partial downloads.
- (long long)bytesUsed;
+ (NSString *)megabytes:(long long)bytes;
@end
