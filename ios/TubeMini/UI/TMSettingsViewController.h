#import <UIKit/UIKit.h>

/// Settings in iOS 26 cards: server address (typed, or found on the network with Bonjour), access token
/// and "Kiểm tra kết nối" (`/tm/v1/ping`); default quality; "Phát qua máy chủ" (proxy); theme; app
/// update; the Telegram group.
@interface TMSettingsViewController : UITableViewController <UITextFieldDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
/// Runs the connection test (debug commands use it too).
- (void)testConnection;
/// Looks for `_tubemini._tcp` servers for a few seconds (debug commands use it too).
- (void)discover;
/// Refills the fields from the saved settings (they may change elsewhere).
- (void)reloadFields;
@end
