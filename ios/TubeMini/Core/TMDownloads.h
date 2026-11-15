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

/// One saved (or saving) video: the 360p MP4 from `<tm:download>`.
@interface TMDownload : NSObject
@property (nonatomic, copy) NSString *videoID, *title, *author, *authorID;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, assign) TMDownloadState state;
@property (nonatomic, assign) long long received, total; // bytes; total 0 = unknown yet
@property (nonatomic, copy) NSString *error;              // when failed
@property (nonatomic, assign) BOOL dubbed;                 // audio is an AI dub (D23)
@property (nonatomic, assign) NSInteger position;          // last watch position (offline resume)
@property (nonatomic, strong) NSDate *added;
- (NSString *)filePath;
- (TMVideo *)video;
/// "Đang tải 45% · 12,3 / 27,1 MB", "27,1 MB", "Lỗi: …".
- (NSString *)statusText;
@end

/// Downloads for offline viewing: one at a time, resumed with HTTP Range after a drop or a restart,
/// with a fresh link from `streams?fresh=1` when googlevideo refuses an expired one. Keeps going for
/// a few minutes in the background. Files: Documents/TubeMini-Downloads/<id>.mp4 (no iCloud backup).
@interface TMDownloads : NSObject
+ (instancetype)shared;
/// Newest first.
@property (nonatomic, readonly) NSArray *items;
- (TMDownload *)itemFor:(NSString *)videoID;
/// Queues the video (a failed one is retried).
- (void)add:(TMVideo *)video;
- (void)retry:(NSString *)videoID;
/// Cancels if running and deletes the file.
- (void)remove:(NSString *)videoID;
/// Starts the next waiting download (at launch, back in the foreground).
- (void)resume;
/// Bytes used by finished and partial files.
- (long long)bytesUsed;
+ (NSString *)megabytes:(long long)bytes;
@end
