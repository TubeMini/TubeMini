#import <UIKit/UIKit.h>

/// Posted (main thread) when the check finishes or the download progresses / fails.
extern NSString *const TMUpdaterDidChangeNotification;

/// OTA updates of the app itself. Reads https://tubemini.github.io/update.json (the Cydia repo's latest
/// TubeMini package: version, URL, SHA-256, notes), downloads the .deb, checks its SHA-256, and hands it to
/// /usr/libexec/tubemini/tmupdate (setuid root), which runs dpkg -i and resprings.
@interface TMUpdater : NSObject <UIAlertViewDelegate>
+ (instancetype)shared;
/// Version of the running app (CFBundleShortVersionString).
+ (NSString *)currentVersion;
/// -1 / 0 / 1 like compare: "0.5.10" > "0.5.9".
+ (NSInteger)compareVersion:(NSString *)a with:(NSString *)b;
@property (nonatomic, readonly) NSString *latestVersion, *notes;
@property (nonatomic, readonly) BOOL updateAvailable;
@property (nonatomic, readonly) BOOL busy;      // checking, downloading or installing
@property (nonatomic, readonly) NSString *status; // "Đang tải 45%", "Đang cài…", or nil
/// At launch: at most once a day, in the background; asks the user when a newer version exists.
- (void)checkQuietly;
/// Settings button: always checks; `done(error)` (nil = checked fine, see updateAvailable).
- (void)check:(void (^)(NSString *error))done;
/// Asks "Có TubeMini x.y.z — Cập nhật?" (then install).
- (void)offer;
/// Downloads, verifies and installs the latest version (the app is closed by the respring).
- (void)install;
/// Testing: another update.json (nil = the default).
@property (nonatomic, copy) NSString *feedURL;
@end
