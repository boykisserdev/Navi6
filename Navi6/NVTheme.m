#import "NVTheme.h"
#import <QuartzCore/QuartzCore.h>

#define RGBA(r,g,b,a) [UIColor colorWithRed:(r) green:(g) blue:(b) alpha:(a)]

NSString * const NVPlayerChangedNotification    = @"NVPlayerChanged";
NSString * const NVDownloadsChangedNotification = @"NVDownloadsChanged";
NSString * const NVDownloadProgressNotification = @"NVDownloadProgress";
NSString * const NVFavoritesChangedNotification = @"NVFavoritesChanged";

// NOTE: only pass colors made with colorWithRed:... (getRed: fails on grayscale colors in iOS 6)
static void NVFillGradient(CGContextRef c, CGRect r, UIColor *top, UIColor *bot) {
    CGFloat t[4], b[4];
    [top getRed:&t[0] green:&t[1] blue:&t[2] alpha:&t[3]];
    [bot getRed:&b[0] green:&b[1] blue:&b[2] alpha:&b[3]];
    CGFloat comps[8] = { t[0], t[1], t[2], t[3], b[0], b[1], b[2], b[3] };
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, NULL, 2);
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
}

static UIBezierPath *NVStarPath(CGFloat cx, CGFloat cy, CGFloat R, CGFloat r) {
    UIBezierPath *p = [UIBezierPath bezierPath];
    for (int i = 0; i < 10; i++) {
        CGFloat a = -M_PI_2 + i * M_PI / 5, rad = (i % 2) ? r : R;
        CGPoint pt = CGPointMake(cx + cos(a) * rad, cy + sin(a) * rad);
        if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
    }
    [p closePath];
    return p;
}

@implementation NVTheme

+ (void)applyAppearance {
    UIColor *graphite = [self barTint];
    [[UINavigationBar appearance] setTintColor:graphite];
    [[UISearchBar appearance] setTintColor:graphite];
    [[UIToolbar appearance] setTintColor:graphite];
}

// Procedurally generated linen texture (no image assets needed)
+ (UIColor *)linenColor {
    static UIColor *color; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(64, 64), YES, 0);
        CGContextRef g = UIGraphicsGetCurrentContext();
        [RGBA(0.17, 0.17, 0.18, 1) setFill];
        CGContextFillRect(g, CGRectMake(0, 0, 64, 64));
        srand(42);
        for (int i = 0; i < 64; i++) {
            CGFloat a = (rand() % 100) / 100.0 * 0.10;
            [(i % 2 ? RGBA(1, 1, 1, a) : RGBA(0, 0, 0, a * 1.6)) setFill];
            CGContextFillRect(g, CGRectMake(0, i, 64, 1));
            a = (rand() % 100) / 100.0 * 0.10;
            [(i % 2 ? RGBA(0, 0, 0, a * 1.6) : RGBA(1, 1, 1, a)) setFill];
            CGContextFillRect(g, CGRectMake(i, 0, 1, 64));
        }
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        color = [UIColor colorWithPatternImage:img];
    });
    return color;
}

+ (UIImage *)placeholder {
    static UIImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGRect r = CGRectMake(0, 0, 44, 44);
        UIGraphicsBeginImageContextWithOptions(r.size, YES, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        NVFillGradient(c, r, RGBA(.80, .81, .83, 1), RGBA(.58, .60, .64, 1));
        [RGBA(1, 1, 1, .9) setFill];
        CGContextSetShadowWithColor(c, CGSizeMake(0, -1), 0, RGBA(0, 0, 0, .35).CGColor);
        [@"\u266B" drawInRect:CGRectMake(0, 7, 44, 34) withFont:[UIFont boldSystemFontOfSize:26]
                lineBreakMode:NSLineBreakByClipping alignment:NSTextAlignmentCenter];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

+ (UIColor *)barTint { return RGBA(0.20, 0.23, 0.29, 1); }

// 30x30 template icons (alpha masks, like the stock tab bar art): UIKit tints them gray / blue.
+ (UIImage *)tabIconNamed:(NSString *)name {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(30, 30), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    [[UIColor blackColor] setFill];
    [[UIColor blackColor] setStroke];
    CGContextSetLineWidth(c, 2.2);

    if ([name isEqualToString:@"songs"]) {
        CGContextFillEllipseInRect(c, CGRectMake(6, 18.5, 11, 8));
        CGContextFillRect(c, CGRectMake(14.6, 5, 2.4, 17.5));
        UIBezierPath *flag = [UIBezierPath bezierPath];
        [flag moveToPoint:CGPointMake(17, 5)];
        [flag addCurveToPoint:CGPointMake(24, 16) controlPoint1:CGPointMake(17.5, 11) controlPoint2:CGPointMake(24, 10)];
        [flag addLineToPoint:CGPointMake(22, 16)];
        [flag addCurveToPoint:CGPointMake(17, 11) controlPoint1:CGPointMake(21.5, 13) controlPoint2:CGPointMake(19, 12.5)];
        [flag closePath]; [flag fill];
    } else if ([name isEqualToString:@"playlists"]) {
        for (int i = 0; i < 3; i++) {
            CGFloat y = 8.5 + i * 6.5;
            CGContextFillEllipseInRect(c, CGRectMake(4, y - 1.7, 3.4, 3.4));
            CGContextMoveToPoint(c, 11, y); CGContextAddLineToPoint(c, 26, y); CGContextStrokePath(c);
        }
    } else if ([name isEqualToString:@"artists"]) {
        CGContextFillEllipseInRect(c, CGRectMake(10, 3.5, 10, 10.5));
        CGContextSaveGState(c);
        CGContextClipToRect(c, CGRectMake(0, 0, 30, 25.5));
        CGContextFillEllipseInRect(c, CGRectMake(5, 16, 20, 22));
        CGContextRestoreGState(c);
    } else if ([name isEqualToString:@"albums"]) {
        CGContextStrokeEllipseInRect(c, CGRectMake(4.5, 4.5, 21, 21));
        CGContextSetLineWidth(c, 1.4);
        CGContextStrokeEllipseInRect(c, CGRectMake(9, 9, 12, 12));
        CGContextFillEllipseInRect(c, CGRectMake(12.7, 12.7, 4.6, 4.6));
    } else if ([name isEqualToString:@"favorites"]) {
        [NVStarPath(15, 15.5, 12.5, 5.4) fill];
    } else if ([name isEqualToString:@"more"]) {
        for (int i = 0; i < 3; i++) CGContextFillEllipseInRect(c, CGRectMake(4.4 + i * 8.6, 12.4, 5.2, 5.2));
    } else if ([name isEqualToString:@"downloads"]) {
        CGContextMoveToPoint(c, 5, 17); CGContextAddLineToPoint(c, 5, 24); CGContextAddLineToPoint(c, 25, 24); CGContextAddLineToPoint(c, 25, 17);
        CGContextStrokePath(c);
        CGContextSetLineWidth(c, 2.8);
        CGContextMoveToPoint(c, 15, 4.5); CGContextAddLineToPoint(c, 15, 15); CGContextStrokePath(c);
        UIBezierPath *tri = [UIBezierPath bezierPath];
        [tri moveToPoint:CGPointMake(8.8, 13)]; [tri addLineToPoint:CGPointMake(21.2, 13)]; [tri addLineToPoint:CGPointMake(15, 20)]; [tri closePath];
        [tri fill];
    } else {   // settings: gear
        CGContextFillEllipseInRect(c, CGRectMake(6.5, 6.5, 17, 17));
        for (int i = 0; i < 8; i++) {
            CGContextSaveGState(c);
            CGContextTranslateCTM(c, 15, 15);
            CGContextRotateCTM(c, i * M_PI / 4);
            CGContextFillRect(c, CGRectMake(-2.4, -13, 4.8, 6));
            CGContextRestoreGState(c);
        }
        CGContextSetBlendMode(c, kCGBlendModeClear);
        CGContextFillEllipseInRect(c, CGRectMake(11.2, 11.2, 7.6, 7.6));
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)tintedTabIcon:(NSString *)name color:(UIColor *)color {
    UIImage *mask = [self tabIconNamed:name];
    UIGraphicsBeginImageContextWithOptions(mask.size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [mask drawAtPoint:CGPointZero];
    CGContextSetBlendMode(c, kCGBlendModeSourceIn);
    [color setFill];
    CGContextFillRect(c, CGRectMake(0, 0, mask.size.width, mask.size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (UIImage *)shuffleRowIcon {
    static UIImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(26, 20), NO, 0);
        UIColor *col = RGBA(.36, .40, .50, 1);
        [col setStroke]; [col setFill];
        UIBezierPath *p = [UIBezierPath bezierPath];
        p.lineWidth = 2.2; p.lineCapStyle = kCGLineCapRound;
        [p moveToPoint:CGPointMake(2, 5)];  [p addCurveToPoint:CGPointMake(19, 15) controlPoint1:CGPointMake(10, 5)  controlPoint2:CGPointMake(11, 15)];
        [p moveToPoint:CGPointMake(2, 15)]; [p addCurveToPoint:CGPointMake(19, 5)  controlPoint1:CGPointMake(10, 15) controlPoint2:CGPointMake(11, 5)];
        [p stroke];
        UIBezierPath *a = [UIBezierPath bezierPath];
        [a moveToPoint:CGPointMake(18, 1.5)];  [a addLineToPoint:CGPointMake(25, 5)];  [a addLineToPoint:CGPointMake(18, 8.5)];  [a closePath];
        [a moveToPoint:CGPointMake(18, 11.5)]; [a addLineToPoint:CGPointMake(25, 15)]; [a addLineToPoint:CGPointMake(18, 18.5)]; [a closePath];
        [a fill];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

+ (UIImage *)speakerIcon {
    static UIImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(18, 14), NO, 0);
        UIColor *col = RGBA(.35, .65, 1, 1);
        [col setFill]; [col setStroke];
        UIBezierPath *sp = [UIBezierPath bezierPath];
        [sp moveToPoint:CGPointMake(1, 5)]; [sp addLineToPoint:CGPointMake(4, 5)]; [sp addLineToPoint:CGPointMake(8, 1.5)];
        [sp addLineToPoint:CGPointMake(8, 12.5)]; [sp addLineToPoint:CGPointMake(4, 9)]; [sp addLineToPoint:CGPointMake(1, 9)];
        [sp closePath]; [sp fill];
        for (int i = 0; i < 2; i++) {
            UIBezierPath *w = [UIBezierPath bezierPathWithArcCenter:CGPointMake(8.5, 7) radius:3.4 + i * 2.8 startAngle:-0.9 endAngle:0.9 clockwise:YES];
            w.lineWidth = 1.4; w.lineCapStyle = kCGLineCapRound; [w stroke];
        }
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

+ (UIImage *)blankSpeakerIcon {
    static UIImage *img; static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(18, 14), NO, 0);
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

// Nav-bar button icon. iOS 6 draws bar-item images as-is on some bar styles, so it is white (with the usual
// 1px dark drop shadow) instead of a black template that vanishes on the black translucent bar.
+ (UIImage *)listIcon {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(22, 19), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 0, RGBA(0, 0, 0, .55).CGColor);
    [[UIColor whiteColor] setFill]; [[UIColor whiteColor] setStroke];
    CGContextSetLineWidth(c, 2);
    for (int i = 0; i < 3; i++) {
        CGFloat y = 3 + i * 6;
        CGContextFillEllipseInRect(c, CGRectMake(1, y - 1.6, 3.2, 3.2));
        CGContextMoveToPoint(c, 7, y); CGContextAddLineToPoint(c, 21, y); CGContextStrokePath(c);
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

+ (NSString *)timeString:(NSTimeInterval)t {
    NSInteger s = (NSInteger)round(t);
    if (s < 0) s = 0;
    return [NSString stringWithFormat:@"%d:%02d", (int)(s / 60), (int)(s % 60)];
}

+ (NSString *)sizeString:(long long)bytes {
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@end


#pragma mark - Glossy button

@implementation NVGlossyButton

+ (instancetype)buttonWithTitle:(NSString *)title style:(NVButtonStyle)style {
    NVGlossyButton *b = [NVGlossyButton buttonWithType:UIButtonTypeCustom];
    b.style = style;
    b.backgroundColor = [UIColor clearColor];
    b.opaque = NO;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleShadowColor:RGBA(0, 0, 0, .55) forState:UIControlStateNormal];
    b.titleLabel.shadowOffset = CGSizeMake(0, -1);
    return b;
}

- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectMake(0.5, 0.5, self.bounds.size.width - 1, self.bounds.size.height - 2);
    CGFloat rad = 8;
    UIColor *top, *bot, *edge;
    switch (self.style) {
        case NVButtonStyleBlue:
            top = RGBA(.47, .64, .88, 1); bot = RGBA(.10, .31, .68, 1); edge = RGBA(.05, .17, .40, 1); break;
        case NVButtonStyleRed:
            top = RGBA(.92, .45, .42, 1); bot = RGBA(.64, .08, .06, 1); edge = RGBA(.38, .04, .03, 1); break;
        default:
            top = RGBA(.62, .65, .70, 1); bot = RGBA(.22, .25, .31, 1); edge = RGBA(.10, .12, .16, 1); break;
    }
    [RGBA(1, 1, 1, .55) setFill];   // bottom bevel highlight
    [[UIBezierPath bezierPathWithRoundedRect:CGRectOffset(r, 0, 1) cornerRadius:rad] fill];
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:rad];
    CGContextSaveGState(c);
    [body addClip];
    NVFillGradient(c, r, top, bot);
    NVFillGradient(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, r.size.height / 2), RGBA(1, 1, 1, .55), RGBA(1, 1, 1, .12));
    if (self.highlighted) { [RGBA(0, 0, 0, .28) setFill]; UIRectFill(r); }
    CGContextRestoreGState(c);
    [edge setStroke];
    body.lineWidth = 1;
    [body stroke];
}

@end


#pragma mark - Transport button

@implementation NVTransportButton

- (id)initWithGlyph:(NVGlyph)glyph {
    self = [super initWithFrame:CGRectZero];
    if (self) { _glyph = glyph; self.backgroundColor = [UIColor clearColor]; self.opaque = NO; }
    return self;
}
- (void)setGlyph:(NVGlyph)g { if (_glyph == g) return; _glyph = g; [self setNeedsDisplay]; }
- (void)setActive:(BOOL)a { if (_active == a) return; _active = a; [self setNeedsDisplay]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }

static void NVTri(UIBezierPath *p, CGFloat x0, CGFloat y0, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    [p moveToPoint:CGPointMake(x0, y0)]; [p addLineToPoint:CGPointMake(x1, y1)];
    [p addLineToPoint:CGPointMake(x2, y2)]; [p closePath];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    CGFloat s = MIN(b.size.width, b.size.height) * 0.36;
    CGFloat cx = CGRectGetMidX(b), cy = CGRectGetMidY(b);
    BOOL small = self.glyph >= NVGlyphShuffle;

    if (!small) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        switch (self.glyph) {
            case NVGlyphPlay:  NVTri(p, cx - .6*s, cy - s, cx + .9*s, cy, cx - .6*s, cy + s); break;
            case NVGlyphPause:
                [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cx - .8*s, cy - s, .55*s, 2*s)]];
                [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cx + .25*s, cy - s, .55*s, 2*s)]];
                break;
            default: {
                CGFloat d = (self.glyph == NVGlyphNext) ? 1 : -1;
                for (int i = 0; i < 2; i++) {
                    CGFloat base = cx - d*s + d*i*s, tip = base + d*s;
                    NVTri(p, base, cy - .8*s, tip, cy, base, cy + .8*s);
                }
            }
        }
        // 1) dark drop shadow  2) silver gradient clipped to the glyph
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 2, RGBA(0, 0, 0, .9).CGColor);
        [RGBA(0, 0, 0, 1) setFill];
        [p fill];
        CGContextRestoreGState(c);
        CGContextSaveGState(c);
        [p addClip];
        if (self.highlighted) NVFillGradient(c, b, RGBA(.65, .78, 1, 1), RGBA(.25, .45, .85, 1));
        else                  NVFillGradient(c, b, RGBA(1, 1, 1, 1), RGBA(.58, .60, .64, 1));
        CGContextRestoreGState(c);
        return;
    }

    UIColor *line = self.active ? RGBA(.40, .68, 1, 1) : RGBA(.72, .72, .76, 1);
    if (self.highlighted) line = RGBA(1, 1, 1, 1);
    [line setStroke]; [line setFill];
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 1, RGBA(0, 0, 0, .9).CGColor);
    UIBezierPath *p = [UIBezierPath bezierPath];
    p.lineWidth = 2.4;
    if (self.glyph == NVGlyphStar) {
        UIBezierPath *st = NVStarPath(cx, cy + .05*s, 1.25*s, .55*s);
        st.lineWidth = 2.2; st.lineJoinStyle = kCGLineJoinRound;
        if (self.active) { [RGBA(1, .82, .20, 1) setFill]; [st fill]; [RGBA(.75, .50, 0, 1) setStroke]; [st stroke]; }
        else             { [st stroke]; }
    } else if (self.glyph == NVGlyphQueue) {
        for (int i = -1; i <= 1; i++) {
            CGFloat y = cy + i * .75*s;
            CGContextFillRect(c, CGRectMake(cx - s, y - .13*s, .26*s, .26*s));
            CGContextFillRect(c, CGRectMake(cx - .45*s, y - .13*s, 1.45*s, .26*s));
        }
    } else if (self.glyph == NVGlyphShuffle) {
        [p moveToPoint:CGPointMake(cx - s, cy - .6*s)];
        [p addCurveToPoint:CGPointMake(cx + .6*s, cy + .6*s) controlPoint1:CGPointMake(cx, cy - .6*s) controlPoint2:CGPointMake(cx, cy + .6*s)];
        [p moveToPoint:CGPointMake(cx - s, cy + .6*s)];
        [p addCurveToPoint:CGPointMake(cx + .6*s, cy - .6*s) controlPoint1:CGPointMake(cx, cy + .6*s) controlPoint2:CGPointMake(cx, cy - .6*s)];
        [p stroke];
        UIBezierPath *a = [UIBezierPath bezierPath];
        NVTri(a, cx + .5*s, cy + .6*s - .38*s, cx + s, cy + .6*s, cx + .5*s, cy + .6*s + .38*s);
        NVTri(a, cx + .5*s, cy - .6*s - .38*s, cx + s, cy - .6*s, cx + .5*s, cy - .6*s + .38*s);
        [a fill];
    } else {
        UIBezierPath *rr = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - s, cy - .55*s, 2*s, 1.1*s) cornerRadius:.5*s];
        rr.lineWidth = 2.4; [rr stroke];
        UIBezierPath *a = [UIBezierPath bezierPath];
        NVTri(a, cx + .2*s, cy - .55*s - .4*s, cx + .75*s, cy - .55*s, cx + .2*s, cy - .55*s + .4*s);
        [a fill];
        if (self.glyph == NVGlyphRepeatOne) {
            [@"1" drawInRect:CGRectMake(cx - s, cy - .52*s, 2*s, s) withFont:[UIFont boldSystemFontOfSize:s * .85]
               lineBreakMode:NSLineBreakByClipping alignment:NSTextAlignmentCenter];
        }
    }
}

@end


#pragma mark - Glass panel / header

@implementation NVGlassView
- (id)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (self) { self.opaque = YES; self.backgroundColor = [UIColor blackColor]; }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    NVFillGradient(c, b, RGBA(.30, .30, .33, 1), RGBA(.06, .06, .07, 1));
    NVFillGradient(c, CGRectMake(0, 0, b.size.width, b.size.height * .42), RGBA(1, 1, 1, .13), RGBA(1, 1, 1, .02));
    [RGBA(1, 1, 1, .35) setFill];
    UIRectFill(CGRectMake(0, 0, b.size.width, 1));
    [RGBA(0, 0, 0, .8) setFill];
    UIRectFill(CGRectMake(0, 1, b.size.width, 1));
}
@end

@implementation NVHeaderView
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    NVFillGradient(c, b, RGBA(.97, .97, .98, 1), RGBA(.80, .81, .84, 1));
    [RGBA(.55, .56, .60, 1) setFill];
    UIRectFill(CGRectMake(0, b.size.height - 1, b.size.width, 1));
}
@end
