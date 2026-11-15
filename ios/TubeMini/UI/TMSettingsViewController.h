#import <UIKit/UIKit.h>

/// Server address (typed, or found on the network with Bonjour), access token, default quality,
/// "Phát qua máy chủ" (proxy), theme, and a "Kiểm tra kết nối" button (`/tm/v1/ping`).
@interface TMSettingsViewController : UITableViewController <UITextFieldDelegate, NSNetServiceBrowserDelegate,
                                                             NSNetServiceDelegate, UIActionSheetDelegate>
/// Runs the connection test (debug commands use it too).
- (void)testConnection;
/// Looks for `_tubemini._tcp` servers for a few seconds (debug commands use it too).
- (void)discover;
/// Refills the fields from the saved settings (they may change elsewhere).
- (void)reloadFields;
@end
