#import <Foundation/Foundation.h>

/// Logs to NSLog and appends to Documents/TubeMini.log (thread-safe).
void TMLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Documents directory of the app (/var/mobile/Documents for apps in /Applications).
NSString *TMDocumentsDir(void);

/// Path of the log file.
NSString *TMLogPath(void);

/// Hardware model, e.g. "iPad2,5".
NSString *TMDeviceModel(void);
