#import "TMCompat.h"
#import <objc/message.h>
#import <objc/runtime.h>

BOOL TMIsIOS7(void) {
    static BOOL ios7;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ios7 = [[UIDevice currentDevice].systemVersion compare:@"7.0" options:NSNumericSearch] != NSOrderedAscending; });
    return ios7;
}

BOOL TMIsPhone(void) {
    return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone;
}

void TMSetNeedsStatusBarUpdate(UIViewController *vc) {
    SEL sel = NSSelectorFromString(@"setNeedsStatusBarAppearanceUpdate");
    if ([vc respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(vc, sel);
}

void TMDisableAutomaticInsets(UIViewController *vc) {
    if ([vc respondsToSelector:NSSelectorFromString(@"setAutomaticallyAdjustsScrollViewInsets:")]) {
        [vc setValue:@NO forKey:@"automaticallyAdjustsScrollViewInsets"];
    }
}

void TMLabelShrinkToFit(UILabel *label, CGFloat minimumScale) {
    label.adjustsFontSizeToFitWidth = YES;
    if ([label respondsToSelector:NSSelectorFromString(@"setMinimumScaleFactor:")]) {
        [label setValue:@(minimumScale) forKey:@"minimumScaleFactor"];
    } else {
        label.minimumFontSize = floor(label.font.pointSize * minimumScale);
    }
}

static UIFont *named(NSString *name, CGFloat size, BOOL bold) {
    UIFont *f = [UIFont fontWithName:name size:size];
    return f ?: (bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size]);
}

UIImage *TMStretchable(UIImage *image, UIEdgeInsets caps) {
    SEL sel = NSSelectorFromString(@"resizableImageWithCapInsets:resizingMode:"); // iOS 6+
    if ([image respondsToSelector:sel]) {
        return ((UIImage * (*)(id, SEL, UIEdgeInsets, NSInteger)) objc_msgSend)(image, sel, caps, 1 /* UIImageResizingModeStretch */);
    }
    return [image stretchableImageWithLeftCapWidth:(NSInteger)caps.left topCapHeight:(NSInteger)caps.top];
}

UIFont *TMFontRegular(CGFloat size) {
    return [UIFont systemFontOfSize:size];
}

UIFont *TMFontMedium(CGFloat size) {
    return named(@"HelveticaNeue-Medium", size, YES);
}

UIFont *TMFontBold(CGFloat size) {
    return named(@"HelveticaNeue-Bold", size, YES);
}

#pragma mark - Object subscripting on iOS 5

// `array[i]` and `dict[key]` compile to objectAtIndexedSubscript: / objectForKeyedSubscript:, which
// Foundation only has from iOS 6. Apple's toolchain links libarclite to add them on iOS 5; the Linux
// toolchain has no libarclite, so TubeMini adds the four methods itself when they are missing.

static id arrayAt(NSArray *self, SEL _cmd, NSUInteger i) {
    return [self objectAtIndex:i];
}

static void arraySet(NSMutableArray *self, SEL _cmd, id obj, NSUInteger i) {
    if (i == self.count) {
        [self addObject:obj];
    } else {
        [self replaceObjectAtIndex:i withObject:obj];
    }
}

static id dictGet(NSDictionary *self, SEL _cmd, id key) {
    return [self objectForKey:key];
}

static void dictSet(NSMutableDictionary *self, SEL _cmd, id obj, id key) {
    if (obj) {
        [self setObject:obj forKey:key];
    } else {
        [self removeObjectForKey:key];
    }
}

static void addIfMissing(Class cls, SEL sel, IMP imp, const char *types) {
    if (![cls instancesRespondToSelector:sel]) class_addMethod(cls, sel, imp, types);
}

__attribute__((constructor)) static void TMAddSubscripting(void) {
    @autoreleasepool {
        addIfMissing([NSArray class], @selector(objectAtIndexedSubscript:), (IMP)arrayAt, "@@:I");
        addIfMissing([NSMutableArray class], @selector(setObject:atIndexedSubscript:), (IMP)arraySet, "v@:@I");
        addIfMissing([NSDictionary class], @selector(objectForKeyedSubscript:), (IMP)dictGet, "@@:@");
        addIfMissing([NSMutableDictionary class], @selector(setObject:forKeyedSubscript:), (IMP)dictSet, "v@:@@");
    }
}
