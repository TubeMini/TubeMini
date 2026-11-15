#import <UIKit/UIKit.h>

/// Server address, access token, default quality, and a "Kiểm tra kết nối" button (`/tm/v1/ping`).
@interface TMSettingsViewController : UITableViewController <UITextFieldDelegate>
/// Runs the connection test (debug commands use it too).
- (void)testConnection;
/// Refills the fields from the saved settings (they may change elsewhere).
- (void)reloadFields;
@end
