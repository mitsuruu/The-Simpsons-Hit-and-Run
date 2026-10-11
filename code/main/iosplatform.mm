//=============================================================================
// File:        iosplatform.mm
//
// Description: iOS specific platform support
//=============================================================================

#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#include <SDL.h>
#include <radcontroller.hpp>

#include <main/iosplatform.h>

void iOSInitializeAudioSession()
{
    //
    // The default category is muted by the silent mode switch, use the
    // playback category so the game is heard like other games
    //
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    [session setActive:YES error:nil];
}

//=============================================================================
// Touch controls
//=============================================================================
//
// The touch controls are our own views that drive the game's virtual buttons
// and axes, so they all look alike. They're hidden while a physical gamepad
// is connected.
//

@class SRR2StickView;
static SRR2StickView* s_RightStick = nil;
static SRR2StickView* s_LeftStick = nil;

// Buttons have to stay pressed long enough for the game to see them
static const NSTimeInterval MIN_PRESS_TIME = 0.1;

// The sizes and distances below are for an iPad mini. Smaller screens shrink
// the buttons by this factor, see ScaleTouchControls.
static CGFloat s_Scale = 1.0;
static CGFloat Scaled( CGFloat value )
{
    return value * s_Scale;
}

@interface SRR2ButtonTarget : NSObject
@property (nonatomic) NSTimeInterval pressTime;
@property (nonatomic) const char* name;
@property (nonatomic) BOOL isAxis;
- (void)set:(bool)down;
@end

@implementation SRR2ButtonTarget
- (void)set:(bool)down
{
    if( self.isAxis )
    {
        radControllerSetVirtualAxis( self.name, down ? 1.0f : 0.0f );
    }
    else
    {
        radControllerSetVirtualButton( self.name, down );
    }
}

- (void)pressed
{
    self.pressTime = [NSDate timeIntervalSinceReferenceDate];
    [self set:true];
}

- (void)released
{
    NSTimeInterval pressTime = self.pressTime;
    NSTimeInterval held = [NSDate timeIntervalSinceReferenceDate] - pressTime;
    NSTimeInterval delay = held < MIN_PRESS_TIME ? MIN_PRESS_TIME - held : 0.0;
    dispatch_after( dispatch_time( DISPATCH_TIME_NOW, (int64_t)( delay * NSEC_PER_SEC ) ), dispatch_get_main_queue(), ^{
        // Unless it was pressed again in the meantime
        if( self.pressTime == pressTime )
        {
            [self set:false];
        }
    } );
}
@end

// Presses just outside the button count too, so thumbs don't have to be exact.
// Not so much that neighbouring buttons overlap.
static const CGFloat BUTTON_TOUCH_MARGIN = 8.0;

@interface SRR2Button : UIButton
@end

@implementation SRR2Button
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event
{
    return CGRectContainsPoint( CGRectInset( self.bounds, -BUTTON_TOUCH_MARGIN, -BUTTON_TOUCH_MARGIN ), point );
}
@end

static NSMutableArray< UIButton* >* s_Buttons = nil;
static NSMutableArray< SRR2ButtonTarget* >* s_ButtonTargets = nil;

static bool IsPhysicalGamepadConnected()
{
    for( GCController* controller in [GCController controllers] )
    {
        if( controller.extendedGamepad != nil )
        {
            return true;
        }
    }
    return false;
}

// This view drives one of the game's sticks.
static const CGFloat STICK_SIZE = 170.0;
static const CGFloat STICK_KNOB_SIZE = 48.0;

@interface SRR2StickView : UIView
@property (nonatomic, strong) UIView* knob;
@property (nonatomic, assign) const char* axisX;
@property (nonatomic, assign) const char* axisY;
@property (nonatomic, assign) CGPoint origin;
@end

@implementation SRR2StickView
- (instancetype)initWithAxisX:(const char*)axisX axisY:(const char*)axisY label:(NSString*)label
{
    self = [super initWithFrame:CGRectMake( 0.0, 0.0, STICK_SIZE, STICK_SIZE )];
    self.axisX = axisX;
    self.axisY = axisY;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.userInteractionEnabled = NO;
    self.alpha = 0.0;
    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    self.layer.cornerRadius = STICK_SIZE * 0.5;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    self.accessibilityLabel = label;

    self.knob = [[UIView alloc] initWithFrame:CGRectMake( 0.0, 0.0, STICK_KNOB_SIZE, STICK_KNOB_SIZE )];
    self.knob.userInteractionEnabled = NO;
    self.knob.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self.knob.layer.cornerRadius = STICK_KNOB_SIZE * 0.5;
    [self addSubview:self.knob];
    [self moveTo:CGPointZero];
    return self;
}

// Position is in the range -1 to 1, with y up
- (void)moveTo:(CGPoint)position
{
    const CGFloat travel = ( STICK_SIZE - STICK_KNOB_SIZE ) * 0.5;
    self.knob.center = CGPointMake( STICK_SIZE * 0.5 + position.x * travel,
                                    STICK_SIZE * 0.5 - position.y * travel );
    // Down is the positive direction of the game's Y axis
    radControllerSetVirtualAxis( self.axisX, position.x );
    radControllerSetVirtualAxis( self.axisY, -position.y );
}

// The stick appears under the finger. Points are in the coordinates of the
// view that covers the screen.
- (void)beginAt:(CGPoint)point
{
    const CGFloat half = STICK_SIZE * 0.5;
    CGSize area = self.superview.bounds.size;
    point.x = MIN( MAX( point.x, half ), area.width - half );
    point.y = MIN( MAX( point.y, half ), area.height - half );
    self.origin = point;
    self.alpha = 1.0;
    self.transform = CGAffineTransformMakeTranslation( point.x - self.center.x, point.y - self.center.y );
    [self moveTo:CGPointZero];
}

- (void)dragTo:(CGPoint)point
{
    const CGFloat radius = ( STICK_SIZE - STICK_KNOB_SIZE ) * 0.5;
    CGFloat x = ( point.x - self.origin.x ) / radius;
    CGFloat y = ( self.origin.y - point.y ) / radius;
    CGFloat length = hypot( x, y );
    if( length > 1.0 )
    {
        x /= length;
        y /= length;
    }
    [self moveTo:CGPointMake( x, y )];
}

// Out of sight again
- (void)end
{
    self.alpha = 0.0;
    self.transform = CGAffineTransformIdentity;
    [self moveTo:CGPointZero];
}
@end

// Covers the screen behind the buttons. A touch on the left half drives the
// left stick and one on the right half drives the right stick.
@interface SRR2StickZone : UIView
@property (nonatomic, strong) NSMapTable< UITouch*, SRR2StickView* >* sticks;
@end

@implementation SRR2StickZone
- (instancetype)init
{
    self = [super initWithFrame:CGRectZero];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.multipleTouchEnabled = YES;
    self.sticks = [NSMapTable strongToStrongObjectsMapTable];
    return self;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    for( UITouch* touch in touches )
    {
        CGPoint point = [touch locationInView:self];
        SRR2StickView* stick = point.x < self.bounds.size.width * 0.5 ? s_LeftStick : s_RightStick;
        // One finger per stick
        if( [[self.sticks objectEnumerator].allObjects containsObject:stick] )
        {
            continue;
        }
        [self.sticks setObject:stick forKey:touch];
        [stick beginAt:point];
    }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    for( UITouch* touch in touches )
    {
        [[self.sticks objectForKey:touch] dragTo:[touch locationInView:self]];
    }
}

- (void)finish:(NSSet<UITouch*>*)touches
{
    for( UITouch* touch in touches )
    {
        [[self.sticks objectForKey:touch] end];
        [self.sticks removeObjectForKey:touch];
    }
}

- (void)cancelAll
{
    [self finish:[NSSet setWithArray:[self.sticks keyEnumerator].allObjects]];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self finish:touches]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self finish:touches]; }
@end

static SRR2StickZone* s_StickZone = nil;

// A cross that presses the d-pad buttons. Sliding the finger changes direction,
// and near a diagonal it presses two.
static CGFloat DPAD_SIZE = 200.0;
static CGFloat DPAD_ARM_WIDTH = 72.0;

@interface SRR2DPadView : UIView
@property (nonatomic, assign) BOOL up;
@property (nonatomic, assign) BOOL down;
@property (nonatomic, assign) BOOL left;
@property (nonatomic, assign) BOOL right;
@end

@implementation SRR2DPadView
- (instancetype)init
{
    self = [super initWithFrame:CGRectMake( 0.0, 0.0, DPAD_SIZE, DPAD_SIZE )];
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.multipleTouchEnabled = NO;
    self.accessibilityLabel = @"D-pad";

    const CGFloat c = DPAD_SIZE * 0.5;
    const CGFloat h = DPAD_ARM_WIDTH * 0.5;
    UIBezierPath* cross = [UIBezierPath bezierPath];
    const CGPoint points[] = {
        { c - h, 0.0 }, { c + h, 0.0 }, { c + h, c - h }, { DPAD_SIZE, c - h },
        { DPAD_SIZE, c + h }, { c + h, c + h }, { c + h, DPAD_SIZE }, { c - h, DPAD_SIZE },
        { c - h, c + h }, { 0.0, c + h }, { 0.0, c - h }, { c - h, c - h }
    };
    [cross moveToPoint:points[0]];
    for( int i = 1; i < 12; i++ )
    {
        [cross addLineToPoint:points[i]];
    }
    [cross closePath];

    CAShapeLayer* shape = [CAShapeLayer layer];
    shape.path = cross.CGPath;
    shape.fillColor = [UIColor colorWithWhite:0.0 alpha:0.35].CGColor;
    shape.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    shape.lineWidth = 1.5;
    shape.lineJoin = kCALineJoinRound;
    [self.layer addSublayer:shape];

    // An arrow in each arm, drawn pointing up and then turned
    UIBezierPath* arrows = [UIBezierPath bezierPath];
    const CGFloat edge = ( c - h ) * 0.5;
    for( int i = 0; i < 4; i++ )
    {
        UIBezierPath* arrow = [UIBezierPath bezierPath];
        [arrow moveToPoint:CGPointMake( c, edge - Scaled( 9.0 ) )];
        [arrow addLineToPoint:CGPointMake( c + Scaled( 11.0 ), edge + Scaled( 7.0 ) )];
        [arrow addLineToPoint:CGPointMake( c - Scaled( 11.0 ), edge + Scaled( 7.0 ) )];
        [arrow closePath];
        CGAffineTransform turn = CGAffineTransformTranslate( CGAffineTransformMakeRotation( i * M_PI_2 ), 0.0, 0.0 );
        // Rotate around the centre of the view
        turn = CGAffineTransformConcat( CGAffineTransformMakeTranslation( -c, -c ), turn );
        turn = CGAffineTransformConcat( turn, CGAffineTransformMakeTranslation( c, c ) );
        [arrow applyTransform:turn];
        [arrows appendPath:arrow];
    }
    CAShapeLayer* arrowLayer = [CAShapeLayer layer];
    arrowLayer.path = arrows.CGPath;
    arrowLayer.fillColor = [UIColor colorWithWhite:1.0 alpha:0.5].CGColor;
    [self.layer addSublayer:arrowLayer];
    return self;
}

// The corners between the arms are empty, leave them to the sticks
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event
{
    const CGFloat reach = DPAD_ARM_WIDTH * 0.5 + BUTTON_TOUCH_MARGIN;
    const CGFloat c = DPAD_SIZE * 0.5;
    CGRect area = CGRectInset( self.bounds, -BUTTON_TOUCH_MARGIN, -BUTTON_TOUCH_MARGIN );
    return CGRectContainsPoint( area, point ) && ( fabs( point.x - c ) <= reach || fabs( point.y - c ) <= reach );
}

- (void)setDirectionsFrom:(CGPoint)point
{
    const CGFloat c = DPAD_SIZE * 0.5;
    CGFloat x = point.x - c;
    CGFloat y = point.y - c;
    CGFloat length = hypot( x, y );
    BOOL centred = length < Scaled( 14.0 );
    // Within 22.5 degrees of an axis only presses that direction
    const CGFloat threshold = 0.38;
    BOOL up = !centred && -y > threshold * length;
    BOOL down = !centred && y > threshold * length;
    BOOL left = !centred && -x > threshold * length;
    BOOL right = !centred && x > threshold * length;
    if( up != self.up )
    {
        self.up = up;
        radControllerSetVirtualButton( "DPadUp", up );
    }
    if( down != self.down )
    {
        self.down = down;
        radControllerSetVirtualButton( "DPadDown", down );
    }
    if( left != self.left )
    {
        self.left = left;
        radControllerSetVirtualButton( "DPadLeft", left );
    }
    if( right != self.right )
    {
        self.right = right;
        radControllerSetVirtualButton( "DPadRight", right );
    }
}

- (void)releaseAll
{
    [self setDirectionsFrom:CGPointMake( DPAD_SIZE * 0.5, DPAD_SIZE * 0.5 )];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self setDirectionsFrom:[touches.anyObject locationInView:self]]; }
- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self setDirectionsFrom:[touches.anyObject locationInView:self]]; }
- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self releaseAll]; }
- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event { [self releaseAll]; }
@end

static SRR2DPadView* s_DPad = nil;

static void UpdateTouchControls()
{
    bool hasGamepad = IsPhysicalGamepadConnected();
    for( UIButton* button in s_Buttons )
    {
        button.hidden = hasGamepad;
    }
    s_RightStick.hidden = hasGamepad;
    s_LeftStick.hidden = hasGamepad;
    s_StickZone.hidden = hasGamepad;
    s_DPad.hidden = hasGamepad;
    if( hasGamepad )
    {
        [s_StickZone cancelAll];
        [s_DPad releaseAll];
    }
}

static UIButton* MakeButton( UIView* view, NSString* title, const char* name, bool isAxis, CGFloat width, CGFloat height )
{
    SRR2ButtonTarget* target = [[SRR2ButtonTarget alloc] init];
    target.name = name;
    target.isAxis = isAxis;

    UIButton* button = [SRR2Button buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:MAX( 11.0, Scaled( 15.0 ) ) weight:UIFontWeightSemibold];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.9] forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.5] forState:UIControlStateHighlighted];
    button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    button.layer.cornerRadius = height * 0.5;
    button.layer.borderWidth = 1.5;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    button.accessibilityLabel = title.capitalizedString;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:target action:@selector(pressed) forControlEvents:UIControlEventTouchDown];
    [button addTarget:target action:@selector(released)
     forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:width],
        [button.heightAnchor constraintEqualToConstant:height]
    ]];
    [s_Buttons addObject:button];
    [s_ButtonTargets addObject:target];
    return button;
}

static CGFloat ROUND_BUTTON_SIZE = 72.0;

//
// The in-game prompts show PlayStation buttons, draw the face buttons as
// cross, circle, square and triangle instead of A, B, X and Y. The glyph is
// the outline of a stroke so it can be filled.
//
static UIBezierPath* MakeGlyph( void ( ^draw )( CGMutablePathRef path, CGFloat size ) )
{
    const CGFloat size = Scaled( 22.0 );
    CGMutablePathRef line = CGPathCreateMutable();
    draw( line, size );
    CGPathRef outline = CGPathCreateCopyByStrokingPath( line, NULL, Scaled( 2.0 ), kCGLineCapRound, kCGLineJoinRound, 0.0 );
    UIBezierPath* glyph = [UIBezierPath bezierPathWithCGPath:outline];

    // The system scales the path to fill the button, so changing the size of
    // the glyph does nothing. Empty segments at the corners of a larger square
    // make the glyph fill only part of the button.
    const CGFloat extent = size * 0.75;
    [glyph moveToPoint:CGPointMake( -extent, -extent )];
    [glyph addLineToPoint:CGPointMake( -extent, -extent )];
    [glyph moveToPoint:CGPointMake( extent, extent )];
    [glyph addLineToPoint:CGPointMake( extent, extent )];
    CGPathRelease( outline );
    CGPathRelease( line );
    return glyph;
}

static UIImage* MakeFaceGlyphImage( UIBezierPath* glyph, UIColor* color )
{
    // The path is centred on the origin, with y pointing up
    const CGFloat scale = 1.5;
    const CGRect bounds = glyph.bounds;
    const CGFloat extent = MAX( bounds.size.width, bounds.size.height ) * scale;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake( extent, extent )];
    UIImage* image = [renderer imageWithActions:^( UIGraphicsImageRendererContext* context ) {
        CGContextTranslateCTM( context.CGContext, extent * 0.5, extent * 0.5 );
        CGContextScaleCTM( context.CGContext, scale, -scale );
        [color setFill];
        [glyph fill];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// A stick glyph: a ring around the letter of the stick. R3 does nothing in the
// game, so the right one presses Black, which toggles the camera.
static UIButton* MakeRoundButton( UIView* view, NSString* label, const char* name, UIImage* image )
{
    UIButton* button = MakeButton( view, @"", name, false, ROUND_BUTTON_SIZE, ROUND_BUTTON_SIZE );
    button.layer.cornerRadius = ROUND_BUTTON_SIZE * 0.5;
    button.accessibilityLabel = label;
    [button setImage:image forState:UIControlStateNormal];
    button.imageView.alpha = 0.9;
    return button;
}

// The path is relative to the centre of the button, with y pointing up
static UIButton* MakeFaceButton( UIView* view, NSString* label, const char* name, UIColor* color,
                                 void ( ^draw )( CGMutablePathRef path, CGFloat size ) )
{
    return MakeRoundButton( view, label, name, MakeFaceGlyphImage( MakeGlyph( draw ), color ) );
}

static UIButton* MakeThumbButton( UIView* view, NSString* letter, const char* name )
{
    const CGFloat size = ROUND_BUTTON_SIZE * 0.72;
    UIGraphicsImageRenderer* renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake( size, size )];
    UIImage* glyph = [renderer imageWithActions:^( UIGraphicsImageRendererContext* context ) {
        [[UIColor whiteColor] setStroke];
        UIBezierPath* ring = [UIBezierPath bezierPathWithOvalInRect:CGRectMake( Scaled( 3.0 ), Scaled( 3.0 ), size - Scaled( 6.0 ), size - Scaled( 6.0 ) )];
        ring.lineWidth = Scaled( 5.0 );
        [ring stroke];
        NSDictionary* attributes = @{ NSFontAttributeName : [UIFont systemFontOfSize:size * 0.54 weight:UIFontWeightBold],
                                      NSForegroundColorAttributeName : [UIColor whiteColor] };
        CGSize textSize = [letter sizeWithAttributes:attributes];
        [letter drawAtPoint:CGPointMake( ( size - textSize.width ) * 0.5, ( size - textSize.height ) * 0.5 )
             withAttributes:attributes];
    }];
    return MakeRoundButton( view, [letter stringByAppendingString:@"3"], name,
                            [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] );
}

// Shrinks the controls on screens smaller than an iPad mini's, so they don't
// cover the game on an iPhone. The iPad mini and bigger screens keep the sizes.
static void ScaleTouchControls( UIView* view )
{
    const CGFloat IPAD_MINI_HEIGHT = 744.0;
    const CGFloat MIN_SCALE = 0.7;
    const CGFloat shortSide = MIN( view.bounds.size.width, view.bounds.size.height );
    s_Scale = MIN( 1.0, MAX( MIN_SCALE, shortSide / IPAD_MINI_HEIGHT ) );
    DPAD_SIZE = Scaled( 200.0 );
    DPAD_ARM_WIDTH = Scaled( 72.0 );
    ROUND_BUTTON_SIZE = Scaled( 72.0 );
}

static void CreateStartButton( SDL_Window* window )
{
    UIWindow* uiWindow = (__bridge UIWindow*)SDL_GetPointerProperty( SDL_GetWindowProperties( window ),
                                                                     SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL );
    UIView* view = uiWindow.rootViewController.view;
    if( view == nil )
    {
        SDL_Log( "Touch controls: No view to add the Start button to" );
        return;
    }
    ScaleTouchControls( view );

    // Behind everything else, so the buttons get their touches first
    s_StickZone = [[SRR2StickZone alloc] init];
    [view addSubview:s_StickZone];
    [NSLayoutConstraint activateConstraints:@[
        [s_StickZone.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [s_StickZone.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [s_StickZone.topAnchor constraintEqualToAnchor:view.topAnchor],
        [s_StickZone.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];

    s_Buttons = [NSMutableArray array];
    s_ButtonTargets = [NSMutableArray array];
    UILayoutGuide* safeArea = view.safeAreaLayoutGuide;

    UIButton* startButton = MakeButton( view, @"START", "Start", false, Scaled( 84.0 ), Scaled( 36.0 ) );
    UIButton* backButton = MakeButton( view, @"BACK", "Back", false, Scaled( 84.0 ), Scaled( 36.0 ) );
    UIButton* leftThumb = MakeThumbButton( view, @"L", "LeftThumb" );
    UIButton* rightThumb = MakeThumbButton( view, @"R", "Black" );

    // Cross, circle, square and triangle in a diamond at the bottom right
    UIButton* crossButton = MakeFaceButton( view, @"Cross", "A", [UIColor colorWithRed:0.42 green:0.62 blue:0.84 alpha:1.0],
        ^( CGMutablePathRef path, CGFloat size ) {
        const CGFloat h = size * 0.5;
        CGPathMoveToPoint( path, NULL, -h, -h );
        CGPathAddLineToPoint( path, NULL, h, h );
        CGPathMoveToPoint( path, NULL, h, -h );
        CGPathAddLineToPoint( path, NULL, -h, h );
    } );
    UIButton* circleButton = MakeFaceButton( view, @"Circle", "B", [UIColor colorWithRed:0.90 green:0.35 blue:0.40 alpha:1.0],
        ^( CGMutablePathRef path, CGFloat size ) {
        CGPathAddEllipseInRect( path, NULL, CGRectMake( -size * 0.5, -size * 0.5, size, size ) );
    } );
    UIButton* squareButton = MakeFaceButton( view, @"Square", "X", [UIColor colorWithRed:0.85 green:0.55 blue:0.75 alpha:1.0],
        ^( CGMutablePathRef path, CGFloat size ) {
        CGPathAddRect( path, NULL, CGRectMake( -size * 0.5, -size * 0.5, size, size ) );
    } );
    UIButton* triangleButton = MakeFaceButton( view, @"Triangle", "Y", [UIColor colorWithRed:0.30 green:0.76 blue:0.62 alpha:1.0],
        ^( CGMutablePathRef path, CGFloat size ) {
        const CGFloat h = size * 0.5;
        const CGFloat base = -size * 0.4;
        CGPathMoveToPoint( path, NULL, 0.0, size * 0.47 );
        CGPathAddLineToPoint( path, NULL, h, base );
        CGPathAddLineToPoint( path, NULL, -h, base );
        CGPathCloseSubpath( path );
    } );
    // Neighbours are 1.41 * 64 apart, a bit more than a button
    const CGFloat spacing = 2.0 * Scaled( 64.0 );
    UILayoutGuide* diamond = [[UILayoutGuide alloc] init];
    [view addLayoutGuide:diamond];
    [NSLayoutConstraint activateConstraints:@[
        [diamond.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-Scaled( 40.0 )],
        [diamond.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 40.0 )],
        [diamond.widthAnchor constraintEqualToConstant:spacing + ROUND_BUTTON_SIZE],
        [diamond.heightAnchor constraintEqualToConstant:spacing + ROUND_BUTTON_SIZE],
        [triangleButton.centerXAnchor constraintEqualToAnchor:diamond.centerXAnchor],
        [triangleButton.topAnchor constraintEqualToAnchor:diamond.topAnchor],
        [crossButton.centerXAnchor constraintEqualToAnchor:diamond.centerXAnchor],
        [crossButton.bottomAnchor constraintEqualToAnchor:diamond.bottomAnchor],
        [squareButton.leadingAnchor constraintEqualToAnchor:diamond.leadingAnchor],
        [squareButton.centerYAnchor constraintEqualToAnchor:diamond.centerYAnchor],
        [circleButton.trailingAnchor constraintEqualToAnchor:diamond.trailingAnchor],
        [circleButton.centerYAnchor constraintEqualToAnchor:diamond.centerYAnchor]
    ]];

    // Mirrors the face buttons at the bottom left
    s_DPad = [[SRR2DPadView alloc] init];
    [view addSubview:s_DPad];
    [NSLayoutConstraint activateConstraints:@[
        [s_DPad.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:Scaled( 40.0 )],
        [s_DPad.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 40.0 )],
        [s_DPad.widthAnchor constraintEqualToConstant:DPAD_SIZE],
        [s_DPad.heightAnchor constraintEqualToConstant:DPAD_SIZE]
    ]];

    // Back and Start at the bottom centre, either side of the middle
    [NSLayoutConstraint activateConstraints:@[
        [backButton.trailingAnchor constraintEqualToAnchor:safeArea.centerXAnchor constant:-Scaled( 8.0 )],
        [backButton.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 24.0 )],
        [startButton.leadingAnchor constraintEqualToAnchor:safeArea.centerXAnchor constant:Scaled( 8.0 )],
        [startButton.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 24.0 )],
        // Stick clicks at the bottom, beside the sticks and face buttons
        [leftThumb.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:Scaled( 300.0 )],
        [rightThumb.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-Scaled( 300.0 )],
        [leftThumb.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 24.0 )],
        [rightThumb.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-Scaled( 24.0 )]
    ]];

    // Above the face buttons, at the right edge
    s_RightStick = [[SRR2StickView alloc] initWithAxisX:"RightStickX" axisY:"RightStickY" label:@"Right stick"];
    [view addSubview:s_RightStick];
    [NSLayoutConstraint activateConstraints:@[
        [s_RightStick.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor constant:-40.0],
        [s_RightStick.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-350.0],
        [s_RightStick.widthAnchor constraintEqualToConstant:STICK_SIZE],
        [s_RightStick.heightAnchor constraintEqualToConstant:STICK_SIZE]
    ]];

    // Bottom left, where the virtual controller's own stick used to be
    s_LeftStick = [[SRR2StickView alloc] initWithAxisX:"LeftStickX" axisY:"LeftStickY" label:@"Left stick"];
    [view addSubview:s_LeftStick];
    [NSLayoutConstraint activateConstraints:@[
        [s_LeftStick.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor constant:40.0],
        [s_LeftStick.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-40.0],
        [s_LeftStick.widthAnchor constraintEqualToConstant:STICK_SIZE],
        [s_LeftStick.heightAnchor constraintEqualToConstant:STICK_SIZE]
    ]];
}

void iOSInitializeTouchControls( SDL_Window* window )
{
    if( s_Buttons != nil )
    {
        return;
    }

    CreateStartButton( window );

    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    void ( ^onChange )( NSNotification* ) = ^( NSNotification* notification )
    {
        UpdateTouchControls();
    };
    [center addObserverForName:GCControllerDidConnectNotification object:nil
                         queue:[NSOperationQueue mainQueue] usingBlock:onChange];
    [center addObserverForName:GCControllerDidDisconnectNotification object:nil
                         queue:[NSOperationQueue mainQueue] usingBlock:onChange];

    UpdateTouchControls();
}
