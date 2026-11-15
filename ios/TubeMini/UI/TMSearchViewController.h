#import "TMListViewController.h"

/// Search bar with Video / Kênh scopes on top of a TMListViewController.
@interface TMSearchViewController : TMListViewController <UISearchBarDelegate>
/// scope 0 = videos, 1 = channels.
- (void)runSearch:(NSString *)query scope:(NSInteger)scope;
@end
