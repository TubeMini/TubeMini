#import "TMListViewController.h"

/// "Đã theo dõi" tab: the subscribed channels (`/tm/v1/subscriptions`). Tap opens the channel page,
/// swipe left unsubscribes.
@interface TMSubscriptionsViewController : TMListViewController
@end

/// "Lịch sử" tab: watched videos, most recent first, with how far each was watched. Tap opens the
/// video page (its Play button resumes), swipe left removes one, "Xoá hết" clears the history.
@interface TMHistoryViewController : TMListViewController
/// Same as confirming "Xoá hết" (debug commands).
- (void)clearAll;
@end
