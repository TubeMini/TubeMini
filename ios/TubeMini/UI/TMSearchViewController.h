#import "TMListViewController.h"

/// Search tab (the round button at the right of the tab bar): a capsule search field and Video / Kênh
/// chips on top of a TMListViewController.
@interface TMSearchViewController : TMListViewController <UITextFieldDelegate>
/// scope 0 = videos, 1 = channels.
- (void)runSearch:(NSString *)query scope:(NSInteger)scope;
@end
