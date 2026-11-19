#import <UIKit/UIKit.h>

/// iOS 26-style alerts and action sheets, drawn by TubeMini so they look the same on iOS 5–8 (the
/// system ones are glossy blue on iOS 5/6). Alerts: a rounded glass card with capsule buttons. Sheets: a
/// card of choices sliding up from the bottom, with a separate "Huỷ" capsule; tapping outside cancels.
/// Shown on the root view controller's view (it rotates with the interface on iOS 5/6), or on the
/// topmost presented controller (the video player).
@interface TMAlert : UIView

/// Handler index: the position in `buttons`; sheets also report -1 when cancelled.
typedef void (^TMAlertHandler)(NSInteger index);

/// One "OK"-style button (`button`, default "OK").
+ (void)showTitle:(NSString *)title message:(NSString *)message button:(NSString *)button;
/// Buttons side by side when there are two, stacked otherwise. `cancelIndex` is drawn plain (grey),
/// `destructiveIndex` red, the others in the accent colour; -1 = none.
+ (void)showTitle:(NSString *)title
          message:(NSString *)message
          buttons:(NSArray *)buttons
      cancelIndex:(NSInteger)cancelIndex
 destructiveIndex:(NSInteger)destructiveIndex
          handler:(TMAlertHandler)handler;
/// Choices sheet (with a "Huỷ" capsule underneath).
+ (void)sheetWithTitle:(NSString *)title buttons:(NSArray *)buttons destructiveIndex:(NSInteger)destructiveIndex handler:(TMAlertHandler)handler;

/// Closes every alert / sheet on screen as if cancelled (debug commands); logs their text.
+ (void)dismissAll;
@end
