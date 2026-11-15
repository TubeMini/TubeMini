#import <UIKit/UIKit.h>
#import "TMListViewController.h"

/// Grid of video tiles (UICollectionView, iOS 6+): 3 columns in portrait, 4 in landscape on the
/// iPad, infinite scroll, footer with loading / error state (tap to retry).
@interface TMGridViewController : UICollectionViewController
- (instancetype)initWithFirstPage:(TMFirstPageBlock)firstPage;
@property (nonatomic, copy) NSString *emptyMessage;
@property (nonatomic, readonly) NSArray *items;
- (void)reload;
/// Same as tapping item `index` (debug commands).
- (void)selectItem:(NSInteger)index;
@end
