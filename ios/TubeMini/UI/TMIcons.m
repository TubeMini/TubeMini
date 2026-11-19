#import "TMIcons.h"
#import "TMCompat.h"

#define DEG(d) ((d) * (CGFloat)M_PI / 180)

static void moveLine(CGContextRef c, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextMoveToPoint(c, x1, y1);
    CGContextAddLineToPoint(c, x2, y2);
}

static void addRoundRect(CGContextRef c, CGRect r, CGFloat radius) {
    CGFloat x0 = CGRectGetMinX(r), x1 = CGRectGetMaxX(r), y0 = CGRectGetMinY(r), y1 = CGRectGetMaxY(r);
    CGContextMoveToPoint(c, x0 + radius, y0);
    CGContextAddArcToPoint(c, x1, y0, x1, y1, radius);
    CGContextAddArcToPoint(c, x1, y1, x0, y1, radius);
    CGContextAddArcToPoint(c, x0, y1, x0, y0, radius);
    CGContextAddArcToPoint(c, x0, y0, x1, y0, radius);
    CGContextClosePath(c);
}

/// Arc by points (y grows downwards, so growing angles turn clockwise on screen).
static void addArc(CGContextRef c, CGFloat cx, CGFloat cy, CGFloat r, CGFloat from, CGFloat to, BOOL move) {
    int steps = (int)ceil(fabs(to - from) / DEG(4));
    for (int i = 0; i <= steps; i++) {
        CGFloat t = from + (to - from) * i / steps;
        CGFloat x = cx + r * cos(t), y = cy + r * sin(t);
        if (i == 0 && move) {
            CGContextMoveToPoint(c, x, y);
        } else {
            CGContextAddLineToPoint(c, x, y);
        }
    }
}

static void clearMode(CGContextRef c, BOOL clear) {
    CGContextSetBlendMode(c, clear ? kCGBlendModeClear : kCGBlendModeNormal);
}

static void drawText(NSString *s, CGRect r, UIFont *font) {
    CGSize size = [s sizeWithFont:font];
    CGRect box = CGRectMake(CGRectGetMidX(r) - size.width / 2, CGRectGetMidY(r) - size.height / 2, size.width, size.height);
    [s drawInRect:box withFont:font];
}

static void house(CGContextRef c, BOOL fill) {
    CGContextMoveToPoint(c, 12, 3.6);
    CGContextAddLineToPoint(c, 20, 10.4);
    CGContextAddLineToPoint(c, 20, 19);
    CGContextAddArcToPoint(c, 20, 20.5, 18.5, 20.5, 1.5);
    CGContextAddLineToPoint(c, 14.6, 20.5);
    CGContextAddLineToPoint(c, 14.6, 15);
    CGContextAddLineToPoint(c, 9.4, 15);
    CGContextAddLineToPoint(c, 9.4, 20.5);
    CGContextAddLineToPoint(c, 5.5, 20.5);
    CGContextAddArcToPoint(c, 4, 20.5, 4, 19, 1.5);
    CGContextAddLineToPoint(c, 4, 10.4);
    CGContextClosePath(c);
    fill ? CGContextFillPath(c) : CGContextStrokePath(c);
}

static void screens(CGContextRef c, BOOL fill) {
    moveLine(c, 6.5, 4.2, 17.5, 4.2);
    CGContextStrokePath(c);
    addRoundRect(c, CGRectMake(3, 7.2, 18, 13.3), 2.6);
    fill ? CGContextFillPath(c) : CGContextStrokePath(c);
    if (fill) clearMode(c, YES);
    CGContextMoveToPoint(c, 10, 10.6);
    CGContextAddLineToPoint(c, 10, 17.2);
    CGContextAddLineToPoint(c, 15.4, 13.9);
    CGContextClosePath(c);
    CGContextFillPath(c);
    clearMode(c, NO);
}

static void clockFace(CGContextRef c, BOOL fill) {
    CGRect circle = CGRectMake(3.5, 3.5, 17, 17);
    if (fill) {
        CGContextFillEllipseInRect(c, circle);
        clearMode(c, YES);
    } else {
        CGContextStrokeEllipseInRect(c, circle);
    }
    CGContextMoveToPoint(c, 12, 7.4);
    CGContextAddLineToPoint(c, 12, 12.2);
    CGContextAddLineToPoint(c, 15.2, 14.4);
    CGContextStrokePath(c);
    clearMode(c, NO);
}

static void downloadCircle(CGContextRef c, BOOL fill) {
    CGRect circle = CGRectMake(3.5, 3.5, 17, 17);
    if (fill) {
        CGContextFillEllipseInRect(c, circle);
        clearMode(c, YES);
    } else {
        CGContextStrokeEllipseInRect(c, circle);
    }
    moveLine(c, 12, 7.6, 12, 16);
    CGContextMoveToPoint(c, 8.4, 12.6);
    CGContextAddLineToPoint(c, 12, 16.2);
    CGContextAddLineToPoint(c, 15.6, 12.6);
    CGContextStrokePath(c);
    clearMode(c, NO);
}

static void gear(CGContextRef c, BOOL fill) {
    // Eight rounded teeth around a ring, hole in the middle
    for (int i = 0; i < 8; i++) {
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, 12, 12);
        CGContextRotateCTM(c, DEG(45 * i));
        addRoundRect(c, CGRectMake(-1.9, -10, 3.8, 5), 1.1);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
    }
    if (fill) {
        CGContextFillEllipseInRect(c, CGRectMake(4.6, 4.6, 14.8, 14.8));
        clearMode(c, YES);
        CGContextFillEllipseInRect(c, CGRectMake(9, 9, 6, 6));
        clearMode(c, NO);
    } else {
        CGContextSetLineWidth(c, 2.1);
        CGContextStrokeEllipseInRect(c, CGRectMake(5.6, 5.6, 12.8, 12.8));
        CGContextSetLineWidth(c, 1.8);
        CGContextStrokeEllipseInRect(c, CGRectMake(9.4, 9.4, 5.2, 5.2));
    }
}

static void skip(CGContextRef c, BOOL forward) {
    // Open circle (gap top right when forward, top left when back), arrowhead at the top, "15" inside
    CGFloat cx = 12, cy = 12.8, r = 8.3;
    if (forward) {
        addArc(c, cx, cy, r, DEG(-20), DEG(270), YES);
    } else {
        addArc(c, cx, cy, r, DEG(-90), DEG(200), YES);
    }
    CGContextStrokePath(c);
    CGFloat dir = forward ? 1 : -1;
    CGContextMoveToPoint(c, cx + dir * 3.4, cy - r);
    CGContextAddLineToPoint(c, cx - dir * 1.2, cy - r - 3.3);
    CGContextAddLineToPoint(c, cx - dir * 1.2, cy - r + 3.3);
    CGContextClosePath(c);
    CGContextFillPath(c);
    drawText(@"15", CGRectMake(cx - 6, cy - 4.6, 12, 9.6), TMFontBold(7.6));
}

static void draw(NSString *name, CGContextRef c) {
    BOOL fill = [name hasSuffix:@".fill"];
    NSString *base = fill ? [name substringToIndex:name.length - 5] : name;
    if ([base isEqualToString:@"home"]) {
        house(c, fill);
    } else if ([base isEqualToString:@"subs"]) {
        screens(c, fill);
    } else if ([base isEqualToString:@"history"]) {
        clockFace(c, fill);
    } else if ([base isEqualToString:@"download"]) {
        downloadCircle(c, fill);
    } else if ([base isEqualToString:@"settings"]) {
        gear(c, fill);
    } else if ([base isEqualToString:@"search"]) {
        CGContextSetLineWidth(c, 2.2);
        CGContextStrokeEllipseInRect(c, CGRectMake(4, 4, 13, 13));
        CGContextSetLineWidth(c, 2.6);
        moveLine(c, 15.4, 15.4, 20.4, 20.4);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"back"]) {
        CGContextSetLineWidth(c, 2.5);
        CGContextMoveToPoint(c, 15, 4.5);
        CGContextAddLineToPoint(c, 7.6, 12);
        CGContextAddLineToPoint(c, 15, 19.5);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"chevron.right"]) {
        CGContextSetLineWidth(c, 2.3);
        CGContextMoveToPoint(c, 9, 5);
        CGContextAddLineToPoint(c, 16, 12);
        CGContextAddLineToPoint(c, 9, 19);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"chevron.down"]) {
        CGContextSetLineWidth(c, 2.3);
        CGContextMoveToPoint(c, 5.5, 9);
        CGContextAddLineToPoint(c, 12, 15.5);
        CGContextAddLineToPoint(c, 18.5, 9);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"refresh"]) {
        CGFloat cx = 12, cy = 12.8, r = 7.6;
        CGContextSetLineWidth(c, 2.1);
        addArc(c, cx, cy, r, DEG(-15), DEG(270), YES);
        CGContextStrokePath(c);
        CGContextMoveToPoint(c, cx + 3.6, cy - r);
        CGContextAddLineToPoint(c, cx - 1, cy - r - 3.5);
        CGContextAddLineToPoint(c, cx - 1, cy - r + 3.5);
        CGContextClosePath(c);
        CGContextFillPath(c);
    } else if ([base isEqualToString:@"grid"]) {
        for (int i = 0; i < 4; i++) addRoundRect(c, CGRectMake(3.5 + (i % 2) * 9.5, 3.5 + (i / 2) * 9.5, 7.5, 7.5), 2);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"list"]) {
        for (int i = 0; i < 3; i++) moveLine(c, 9.5, 6.5 + i * 5.5, 20.5, 6.5 + i * 5.5);
        CGContextStrokePath(c); // before the dots: filling an ellipse starts a new path
        for (int i = 0; i < 3; i++) CGContextFillEllipseInRect(c, CGRectMake(3.6, 6.5 + i * 5.5 - 1.4, 2.8, 2.8));
    } else if ([base isEqualToString:@"play"]) {
        CGContextSetLineWidth(c, 2.4);
        CGContextMoveToPoint(c, 7.5, 5);
        CGContextAddLineToPoint(c, 7.5, 19);
        CGContextAddLineToPoint(c, 19, 12);
        CGContextClosePath(c);
        CGContextDrawPath(c, kCGPathFillStroke);
    } else if ([base isEqualToString:@"pause"]) {
        addRoundRect(c, CGRectMake(6, 4.5, 4.2, 15), 1.4);
        addRoundRect(c, CGRectMake(13.8, 4.5, 4.2, 15), 1.4);
        CGContextFillPath(c);
    } else if ([base isEqualToString:@"back15"] || [base isEqualToString:@"fwd15"]) {
        skip(c, [base isEqualToString:@"fwd15"]);
    } else if ([base isEqualToString:@"close"]) {
        CGContextSetLineWidth(c, 2.3);
        moveLine(c, 6.5, 6.5, 17.5, 17.5);
        moveLine(c, 17.5, 6.5, 6.5, 17.5);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"headphones"]) {
        CGContextSetLineWidth(c, 2);
        addArc(c, 12, 13.5, 8.2, DEG(180), DEG(360), YES);
        CGContextStrokePath(c);
        addRoundRect(c, CGRectMake(3.2, 13, 4.8, 7.6), 2);
        addRoundRect(c, CGRectMake(16, 13, 4.8, 7.6), 2);
        CGContextFillPath(c);
    } else if ([base isEqualToString:@"trash"]) {
        moveLine(c, 4, 6.5, 20, 6.5);
        CGContextMoveToPoint(c, 9.3, 6.5);
        CGContextAddLineToPoint(c, 9.8, 3.8);
        CGContextAddLineToPoint(c, 14.2, 3.8);
        CGContextAddLineToPoint(c, 14.7, 6.5);
        CGContextMoveToPoint(c, 6, 6.5);
        CGContextAddLineToPoint(c, 7, 19);
        CGContextAddArcToPoint(c, 7.1, 20.5, 8.6, 20.5, 1.5);
        CGContextAddLineToPoint(c, 15.4, 20.5);
        CGContextAddArcToPoint(c, 16.9, 20.5, 17, 19, 1.5);
        CGContextAddLineToPoint(c, 18, 6.5);
        moveLine(c, 10.2, 10, 10.4, 17);
        moveLine(c, 13.8, 10, 13.6, 17);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"check"]) {
        CGContextSetLineWidth(c, 2.5);
        CGContextMoveToPoint(c, 5, 12.5);
        CGContextAddLineToPoint(c, 9.8, 17.3);
        CGContextAddLineToPoint(c, 19, 6.8);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"plus"]) {
        CGContextSetLineWidth(c, 2.3);
        moveLine(c, 12, 5, 12, 19);
        moveLine(c, 5, 12, 19, 12);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"globe"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(3.5, 3.5, 17, 17));
        CGContextStrokeEllipseInRect(c, CGRectMake(8.2, 3.5, 7.6, 17));
        moveLine(c, 3.8, 12, 20.2, 12);
        moveLine(c, 5.2, 7.8, 18.8, 7.8);
        moveLine(c, 5.2, 16.2, 18.8, 16.2);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"key"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(3, 7.5, 9, 9));
        moveLine(c, 12, 12, 21, 12);
        moveLine(c, 17.2, 12, 17.2, 15.2);
        moveLine(c, 20.2, 12, 20.2, 14.6);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"hd"]) {
        CGContextSetLineWidth(c, 1.7);
        addRoundRect(c, CGRectMake(2.8, 5.5, 18.4, 13), 3);
        CGContextStrokePath(c);
        drawText(@"HD", CGRectMake(3, 6, 18, 12), TMFontBold(8.6));
    } else if ([base isEqualToString:@"antenna"]) {
        CGContextFillEllipseInRect(c, CGRectMake(10, 10, 4, 4));
        addArc(c, 12, 12, 5.5, DEG(-45), DEG(45), YES);
        addArc(c, 12, 12, 5.5, DEG(135), DEG(225), YES);
        addArc(c, 12, 12, 9.3, DEG(-42), DEG(42), YES);
        addArc(c, 12, 12, 9.3, DEG(138), DEG(222), YES);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"moon"]) {
        CGContextFillEllipseInRect(c, CGRectMake(3.5, 3.5, 17, 17));
        clearMode(c, YES);
        CGContextFillEllipseInRect(c, CGRectMake(9, 1, 15, 15));
        clearMode(c, NO);
    } else if ([base isEqualToString:@"wifi"]) {
        CGContextSetLineWidth(c, 2.1);
        addArc(c, 12, 19, 5.2, DEG(-135), DEG(-45), YES);
        addArc(c, 12, 19, 10, DEG(-135), DEG(-45), YES);
        addArc(c, 12, 19, 14.6, DEG(-130), DEG(-50), YES);
        CGContextStrokePath(c);
        CGContextFillEllipseInRect(c, CGRectMake(10.2, 17.2, 3.6, 3.6));
    } else if ([base isEqualToString:@"update"]) {
        addRoundRect(c, CGRectMake(3.5, 3.5, 17, 17), 4.5);
        moveLine(c, 12, 7.5, 12, 15.5);
        CGContextMoveToPoint(c, 8.5, 12.3);
        CGContextAddLineToPoint(c, 12, 15.8);
        CGContextAddLineToPoint(c, 15.5, 12.3);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"paperplane"]) {
        CGContextMoveToPoint(c, 3, 11.2);
        CGContextAddLineToPoint(c, 21, 3.5);
        CGContextAddLineToPoint(c, 14.6, 20.5);
        CGContextAddLineToPoint(c, 11.2, 13);
        CGContextClosePath(c);
        moveLine(c, 11.2, 13, 21, 3.5);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"bolt"]) {
        CGContextSetLineWidth(c, 1.2);
        CGContextMoveToPoint(c, 13.5, 2.5);
        CGContextAddLineToPoint(c, 5, 13.6);
        CGContextAddLineToPoint(c, 11.4, 13.6);
        CGContextAddLineToPoint(c, 10.4, 21.5);
        CGContextAddLineToPoint(c, 19, 10.2);
        CGContextAddLineToPoint(c, 12.6, 10.2);
        CGContextClosePath(c);
        CGContextDrawPath(c, kCGPathFillStroke);
    } else if ([base isEqualToString:@"info"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(3.5, 3.5, 17, 17));
        CGContextFillEllipseInRect(c, CGRectMake(10.8, 6.8, 2.4, 2.4));
        CGContextSetLineWidth(c, 2.2);
        moveLine(c, 12, 11, 12, 17);
        CGContextStrokePath(c);
    } else if ([base isEqualToString:@"person"]) {
        CGContextFillEllipseInRect(c, CGRectMake(8, 3.5, 8, 8));
        addArc(c, 12, 21, 8, DEG(180), DEG(360), YES);
        CGContextClosePath(c);
        CGContextFillPath(c);
    }
}

UIImage *TMIcon(NSString *name, CGFloat size, UIColor *color) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    CGFloat r = 0, g = 0, b = 0, a = 1, w = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a] && [color getWhite:&w alpha:&a]) r = g = b = w;
    NSString *key = [NSString stringWithFormat:@"%@|%.1f|%.3f,%.3f,%.3f,%.3f", name, size, r, g, b, a];
    UIImage *img = [cache objectForKey:key];
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextScaleCTM(c, size / 24, size / 24);
    [color setFill];
    [color setStroke];
    CGContextSetLineWidth(c, 1.9);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    draw(name, c);
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) [cache setObject:img forKey:key];
    return img;
}
