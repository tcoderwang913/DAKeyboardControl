//
//  DAKeyboardControl.m
//  DAKeyboardControlExample
//
//  Created by Daniel Amitay on 7/14/12.
//  Copyright (c) 2012 Daniel Amitay. All rights reserved.
//

#import "DAKeyboardControl.h"
#import <objc/runtime.h>


static inline UIViewAnimationOptions AnimationOptionsForCurve(UIViewAnimationCurve curve) {
	switch (curve) {
		case UIViewAnimationCurveEaseInOut:
			return UIViewAnimationOptionCurveEaseInOut;
			break;
		case UIViewAnimationCurveEaseIn:
			return UIViewAnimationOptionCurveEaseIn;
			break;
		case UIViewAnimationCurveEaseOut:
			return UIViewAnimationOptionCurveEaseOut;
			break;
		case UIViewAnimationCurveLinear:
			return UIViewAnimationOptionCurveLinear;
			break;
		default:
			return UIViewAnimationOptionCurveEaseInOut;
			break;
	}
}

static int reassignActiveViewCount;
static char UIViewKeyboardTriggerOffset;
static char UIViewKeyboardHeight;
static char UIViewKeyboardDidMoveBlock;
static char UIViewKeyboardActiveInput;
static char UIViewKeyboardActiveView;
static char UIViewGestureView;
static char UIViewKeyboardPanRecognizer;
static char UIViewPreviousKeyboardRect;
static char UIViewIsPanning;
static char UIViewIsReassigningFirstResponder;

@interface UIView (DAKeyboardControl_Internal) <UIGestureRecognizerDelegate>

@property (nonatomic) DAKeyboardDidMoveBlock keyboardDidMoveBlock;
@property (nonatomic) DAKeyboardDidMoveBlock keyboardWillFinishAnimatingBlock;
@property (nonatomic, assign) BOOL isReassigningFirstResponder;
@property (nonatomic, strong) UIPanGestureRecognizer *keyboardPanRecognizer;
@property (nonatomic) CGRect previousKeyboardRect;
@property (nonatomic, getter = isPanning) BOOL panning;

@end

@implementation UIView (DAKeyboardControl)
@dynamic keyboardTriggerOffset;

#pragma mark - Public Methods

- (void)addKeyboardWillFinishAnimationActionHandler:(DAKeyboardDidMoveBlock)actionHandler {
    self.keyboardWillFinishAnimatingBlock = actionHandler;
}

- (void)addKeyboardPanningWithActionHandler:(DAKeyboardDidMoveBlock)actionHandler {
    [self addKeyboardControl:YES actionHandler:actionHandler];
}

- (void)addKeyboardNonpanningWithActionHandler:(DAKeyboardDidMoveBlock)actionHandler {
    [self addKeyboardControl:NO actionHandler:actionHandler];
}

- (void)addKeyboardControl:(BOOL)panning actionHandler:(DAKeyboardDidMoveBlock)actionHandler {
    self.panning = panning;
    self.keyboardDidMoveBlock = actionHandler;
    
    [self addKeyboardNotifications];
}

- (void)addKeyboardNotifications {
    // Register for text input notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(responderDidBecomeActive:) name:UITextFieldTextDidBeginEditingNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(responderDidBecomeActive:) name:UITextViewTextDidBeginEditingNotification object:nil];
    
    // Register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputKeyboardDidShow) name:UIKeyboardDidShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(inputKeyboardDidHide) name:UIKeyboardDidHideNotification object:nil];
}

- (CGRect)keyboardFrameInView {
    if (self.keyboardActiveView){
        return [self convertRect:self.keyboardActiveView.frame fromView:self.keyboardActiveView.window];
    } else {
        return CGRectMake(0.0f, [[UIScreen mainScreen] bounds].size.height, 0.0f, 0.0f);
    }
}

- (void)removeKeyboardNotifications {
    // Unregister for text input notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidBeginEditingNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextViewTextDidBeginEditingNotification object:nil];
    
    // Unregister for keyboard notifications
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidHideNotification object:nil];
}

- (void)removeKeyboardControl {
    [self removeKeyboardNotifications];
    
    // Unregister any gesture recognizer
    [self removeGestureRecognizer:self.keyboardPanRecognizer];
    
    self.keyboardActiveView.hidden = NO;
    self.keyboardActiveView.userInteractionEnabled = YES;
    
    // Release a few properties
    self.keyboardDidMoveBlock = nil;
    self.keyboardActiveInput = nil;
    self.keyboardActiveView = nil;
    self.keyboardPanRecognizer = nil;
}

- (void)hideKeyboard {
    if (self.keyboardActiveView){
        self.keyboardActiveView.hidden = YES;
        self.keyboardActiveView.userInteractionEnabled = NO;
        [self.keyboardActiveInput resignFirstResponder];
    }
}

#pragma mark - Input Notifications

- (void)responderDidBecomeActive:(NSNotification *)notification {
    // Grab the active input, it will be used to find the keyboard view later on
    self.keyboardActiveInput = notification.object;
    if (self.keyboardActiveInput.inputAccessoryView == nil){
        UITextField *textField = (UITextField *)self.keyboardActiveInput;
        if ([textField respondsToSelector:@selector(setInputAccessoryView:)]){
            UIView *nullView = [[UIView alloc] initWithFrame:CGRectZero];
            nullView.backgroundColor = [UIColor clearColor];
            textField.inputAccessoryView = nullView;
        }
        self.keyboardActiveInput = (UIResponder *)textField;
        // Force the keyboard active view reset
        [self inputKeyboardDidShow];
    }
}

#pragma mark - Keyboard Notifications

- (void)inputKeyboardWillShow:(NSNotification *)notification {
//    [Utility appDelegate].sKeyboardAnimationCurve = [[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16;
//    [Utility appDelegate].sKeyboardAnimationDuration = [[notification.userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] floatValue];
    
    UIViewAnimationOptions curve = [[notification.userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16;
    
    self.isReassigningFirstResponder = NO;
    CGRect keyboardEndFrameWindow;
    [[notification.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] getValue:&keyboardEndFrameWindow];
    
    double keyboardTransitionDuration;
    [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&keyboardTransitionDuration];
    
    UIViewAnimationCurve keyboardTransitionAnimationCurve;
    [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&keyboardTransitionAnimationCurve];
    
    self.keyboardActiveView.hidden = NO;
    
    CGRect keyboardEndFrameView = [self convertRect:keyboardEndFrameWindow fromView:nil];
    
    [UIView animateWithDuration:keyboardTransitionDuration delay:0.0f options:curve animations:^{
        if (self.keyboardDidMoveBlock && !CGRectIsNull(keyboardEndFrameView)){
            self.keyboardDidMoveBlock(keyboardEndFrameView);
        }
    } completion:^(__unused BOOL finished){
        if (self.panning && !self.keyboardPanRecognizer){
            [self addPanGesture];
        }
    }];
}

- (void)addPanGesture {
    // Register for gesture recognizer calls
    self.keyboardPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGestureDidChange:)];
    [self.keyboardPanRecognizer setMinimumNumberOfTouches:1];
    [self.keyboardPanRecognizer setDelegate:self];
    [self.keyboardPanRecognizer setCancelsTouchesInView:NO];
    if (self.gestureView){
        [self.gestureView addGestureRecognizer:self.keyboardPanRecognizer];
    } else {
        [self addGestureRecognizer:self.keyboardPanRecognizer];
    }
}

- (void)inputKeyboardDidShow {
    // Grab the keyboard view
    self.keyboardActiveView = self.keyboardActiveInput.inputAccessoryView.superview;
    self.keyboardActiveView.hidden = NO;
    
    // If the active keyboard view could not be found (UITextViews...), try again
    if (self.keyboardActiveView == nil && reassignActiveViewCount < 3){
        reassignActiveViewCount++;
        // Find the first responder on subviews and look re-assign first responder to it
        [self reAssignFirstResponder];
    }
    self.keyboardActiveView.userInteractionEnabled = YES;
}

- (void)inputKeyboardWillChangeFrame:(NSNotification *)notification {
    CGRect keyboardEndFrameWindow;
    [[notification.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] getValue: &keyboardEndFrameWindow];
    
    double keyboardTransitionDuration;
    [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&keyboardTransitionDuration];
    
    UIViewAnimationCurve keyboardTransitionAnimationCurve;
    [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&keyboardTransitionAnimationCurve];
    
    CGRect keyboardEndFrameView = [self convertRect:keyboardEndFrameWindow fromView:nil];
    
    [UIView animateWithDuration:keyboardTransitionDuration delay:0.0f options:AnimationOptionsForCurve(keyboardTransitionAnimationCurve) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (self.keyboardDidMoveBlock && !CGRectIsNull(keyboardEndFrameView)){
             self.keyboardDidMoveBlock(keyboardEndFrameView);
        }
     } completion:nil];
}

- (void)inputKeyboardDidChangeFrame
{
    // Nothing to see here
}

- (void)inputKeyboardWillHide:(NSNotification *)notification
{
    if (self.isReassigningFirstResponder){
        return;
    }
    
    CGRect keyboardEndFrameWindow;
    [[notification.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey] getValue: &keyboardEndFrameWindow];
    
    double keyboardTransitionDuration;
    [[notification.userInfo valueForKey:UIKeyboardAnimationDurationUserInfoKey] getValue:&keyboardTransitionDuration];
    
    UIViewAnimationCurve keyboardTransitionAnimationCurve;
    [[notification.userInfo valueForKey:UIKeyboardAnimationCurveUserInfoKey] getValue:&keyboardTransitionAnimationCurve];
    
    CGRect keyboardEndFrameView = [self convertRect:keyboardEndFrameWindow fromView:nil];
    
    [UIView animateWithDuration:keyboardTransitionDuration delay:0.0f options:AnimationOptionsForCurve(keyboardTransitionAnimationCurve) | UIViewAnimationOptionBeginFromCurrentState animations:^{
        if (self.keyboardDidMoveBlock && !CGRectIsNull(keyboardEndFrameView)){
             self.keyboardDidMoveBlock(keyboardEndFrameView);
        }
    } completion:^(__unused BOOL finished){
         // Remove gesture recognizer when keyboard is not showing
         //[self removeGestureRecognizer:self.keyboardPanRecognizer];
         //self.keyboardPanRecognizer = nil;
    }];
}

- (void)inputKeyboardDidHide {
    self.keyboardActiveView.hidden = NO;
    self.keyboardActiveView.userInteractionEnabled = YES;
    self.keyboardActiveView = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(__unused NSDictionary *)change context:(__unused void *)context {
    if([keyPath isEqualToString:@"frame"] && object == self.keyboardActiveView){
        CGRect keyboardEndFrameWindow = [[object valueForKeyPath:keyPath] CGRectValue];
        CGRect keyboardEndFrameView = [self convertRect:keyboardEndFrameWindow fromView:self.keyboardActiveView.window];

        if (CGRectEqualToRect(keyboardEndFrameView, self.previousKeyboardRect)) {
            return;
        }

        self.previousKeyboardRect = keyboardEndFrameView;
    }
}

#pragma mark - Touches Management

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.keyboardPanRecognizer || otherGestureRecognizer == self.keyboardPanRecognizer){
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.keyboardPanRecognizer){
        if ([touch.view isDescendantOfView:self.keyboardPanRecognizer.view]){
            // Don't allow panning if inside the active input (unless SELF is a UITextView and the receiving view)
            return (![touch.view isFirstResponder] || ([self isKindOfClass:[UITextView class]] && [self isEqual:touch.view]));
        }
        return NO;
    } else {
        return YES;
    }
}

- (void)panGestureDidChange:(UIPanGestureRecognizer *)gesture {
    if(!self.keyboardActiveView || !self.keyboardActiveInput || self.keyboardActiveView.hidden) {
        [self reAssignFirstResponder];
        return;
    } else {
        self.keyboardActiveView.hidden = NO;
    }
    
    CGFloat keyboardViewHeight = self.keyboardActiveView.bounds.size.height;
    CGFloat keyboardWindowHeight = self.keyboardActiveView.window.bounds.size.height;
    CGPoint touchLocationInKeyboardWindow = [gesture locationInView:self.keyboardActiveView.window];
    
    // If touch is inside trigger offset, then disable keyboard input
    if (touchLocationInKeyboardWindow.y > keyboardWindowHeight - keyboardViewHeight - self.keyboardTriggerOffset){
        self.keyboardActiveView.userInteractionEnabled = NO;
    } else {
        self.keyboardActiveView.userInteractionEnabled = YES;
    }
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        {
            // For the duration of this gesture, do not recognize more touches than
            // it started with
            gesture.maximumNumberOfTouches = gesture.numberOfTouches;
        }
            break;
        case UIGestureRecognizerStateChanged:
        {
            CGRect newKeyboardViewFrame = self.keyboardActiveView.frame;
            newKeyboardViewFrame.origin.y = touchLocationInKeyboardWindow.y + self.keyboardTriggerOffset;
            // Bound the keyboard to the bottom of the screen
            newKeyboardViewFrame.origin.y = MIN(newKeyboardViewFrame.origin.y, keyboardWindowHeight);
            newKeyboardViewFrame.origin.y = MAX(newKeyboardViewFrame.origin.y, keyboardWindowHeight - keyboardViewHeight);
            
            // Only update if the frame has actually changed
            if (newKeyboardViewFrame.origin.y != self.keyboardActiveView.frame.origin.y)
            {                
                [UIView animateWithDuration:0.0f
                                      delay:0.0f
                                    options:UIViewAnimationOptionTransitionNone | UIViewAnimationOptionBeginFromCurrentState
                                 animations:^{
                                     [self.keyboardActiveView setFrame:newKeyboardViewFrame];

                                     CGRect newKeyboardViewFrameInView = [self convertRect:newKeyboardViewFrame fromView:self.keyboardActiveView.window];
                                     if (self.keyboardDidMoveBlock)
                                         self.keyboardDidMoveBlock(newKeyboardViewFrameInView);
                                 }
                                 completion:nil];
            }
        }
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        {
            CGFloat thresholdHeight = keyboardWindowHeight - keyboardViewHeight - self.keyboardTriggerOffset;// + 44.0f;
            CGPoint velocity = [gesture velocityInView:self.keyboardActiveView];
            BOOL shouldRecede;
            
            if (touchLocationInKeyboardWindow.y < thresholdHeight || velocity.y < 0)
                shouldRecede = NO;
            else
                shouldRecede = YES;
            
            // If the keyboard has only been pushed down 44 pixels or has been
            // panned upwards let it pop back up; otherwise, let it drop down
            CGRect newKeyboardViewFrame = self.keyboardActiveView.frame;
            newKeyboardViewFrame.origin.y = (!shouldRecede ? keyboardWindowHeight - keyboardViewHeight : keyboardWindowHeight);
            
            [UIView animateWithDuration:0.25f
                                  delay:0.0f
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{
                                 [self.keyboardActiveView setFrame:newKeyboardViewFrame];

                                 CGRect newKeyboardViewFrameInView = [self convertRect:newKeyboardViewFrame
                                                                              fromView:self.keyboardActiveView.window];
                                 if (self.keyboardDidMoveBlock)
                                     self.keyboardDidMoveBlock(newKeyboardViewFrameInView);
                             }
                             completion:^(__unused BOOL finished){
                                 self.keyboardActiveView.userInteractionEnabled = YES;
                                 if (shouldRecede)
                                 {
                                     [self hideKeyboard];
                                 }
                             }];
            
            // Set the max number of touches back to the default
            gesture.maximumNumberOfTouches = NSUIntegerMax;
        }
            break;
        default:
            break;
    }
}

#pragma mark - Internal Methods

- (void)reAssignFirstResponder {
    // Find first responder
    UIView *inputView = [self recursiveFindFirstResponder:self];
    if (inputView != nil){
        self.isReassigningFirstResponder = YES;
        // Re assign the focus
        [inputView resignFirstResponder];
        [inputView becomeFirstResponder];
    } else {
        reassignActiveViewCount = 0;
    }
}

- (UIView *)recursiveFindFirstResponder:(UIView *)view {
    if ([view isFirstResponder]){
        return view;
    }
    UIView *found = nil;
    for (UIView *v in view.subviews){
        found = [self recursiveFindFirstResponder:v];
        if (found){
            break;
        }
    }
    return found;
}

- (void)setupWithTextField:(id)field {
    if ([field isKindOfClass:[UITextView class]] || [field isKindOfClass:[UITextField class]]){
        UITextField *textField = (UITextField *)field;
        if ([textField respondsToSelector:@selector(setInputAccessoryView:)]){
            UIView *nullView = [[UIView alloc] initWithFrame:CGRectZero];
            nullView.backgroundColor = [UIColor clearColor];
            textField.inputAccessoryView = nullView;
        }
    }
}

#pragma mark - Property Methods

- (CGRect)previousKeyboardRect {
    id previousRectValue = objc_getAssociatedObject(self, &UIViewPreviousKeyboardRect);
    if (previousRectValue){
        return [previousRectValue CGRectValue];
    }

    return CGRectZero;
}

-(void)setPreviousKeyboardRect:(CGRect)previousKeyboardRect {
    [self willChangeValueForKey:@"previousKeyboardRect"];
    objc_setAssociatedObject(self,
                             &UIViewPreviousKeyboardRect,
                             [NSValue valueWithCGRect:previousKeyboardRect],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"previousKeyboardRect"];
}

- (DAKeyboardDidMoveBlock)keyboardDidMoveBlock
{
    return objc_getAssociatedObject(self,
                                    &UIViewKeyboardDidMoveBlock);
}

- (void)setKeyboardDidMoveBlock:(DAKeyboardDidMoveBlock)keyboardDidMoveBlock
{
    [self willChangeValueForKey:@"keyboardDidMoveBlock"];
    objc_setAssociatedObject(self,
                             &UIViewKeyboardDidMoveBlock,
                             keyboardDidMoveBlock,
                             OBJC_ASSOCIATION_COPY);
    [self didChangeValueForKey:@"keyboardDidMoveBlock"];
}

- (CGFloat)keyboardTriggerOffset
{
    NSNumber *keyboardTriggerOffsetNumber = objc_getAssociatedObject(self,
                                                                     &UIViewKeyboardTriggerOffset);
    return [keyboardTriggerOffsetNumber floatValue];
}

- (void)setKeyboardTriggerOffset:(CGFloat)keyboardTriggerOffset
{
    [self willChangeValueForKey:@"keyboardTriggerOffset"];
    objc_setAssociatedObject(self,
                             &UIViewKeyboardTriggerOffset,
                             [NSNumber numberWithFloat:keyboardTriggerOffset],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"keyboardTriggerOffset"];
}

- (CGFloat)keyboardHeight
{
    NSNumber *keyboardHeight = objc_getAssociatedObject(self,
                                                                     &UIViewKeyboardHeight);
    return [keyboardHeight floatValue];
}

- (void)setKeyboardHeight:(CGFloat)keyboardHeight
{
    [self willChangeValueForKey:@"keyboardHeight"];
    objc_setAssociatedObject(self,
                             &UIViewKeyboardHeight,
                             [NSNumber numberWithFloat:keyboardHeight],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"keyboardHeight"];
}

- (BOOL)isPanning
{
    NSNumber *keyboardTriggerOffsetNumber = objc_getAssociatedObject(self,
                                                                     &UIViewIsPanning);
    return [keyboardTriggerOffsetNumber boolValue];
}

- (void)setPanning:(BOOL)panning
{
    [self willChangeValueForKey:@"panning"];
    objc_setAssociatedObject(self,
                             &UIViewIsPanning,
                             @(panning),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"panning"];
}

- (UIResponder *)keyboardActiveInput
{
    return objc_getAssociatedObject(self,
                                    &UIViewKeyboardActiveInput);
}

- (void)setKeyboardActiveInput:(UIResponder *)keyboardActiveInput
{
    [self willChangeValueForKey:@"keyboardActiveInput"];
    objc_setAssociatedObject(self,
                             &UIViewKeyboardActiveInput,
                             keyboardActiveInput,
                             OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:@"keyboardActiveInput"];
}

- (UIView *)keyboardActiveView
{
    return objc_getAssociatedObject(self,
                                    &UIViewKeyboardActiveView);
}

- (void)setGestureView:(UIView *)gestureView
{
    [self willChangeValueForKey:@"gestureView"];
    objc_setAssociatedObject(self,
                             &UIViewGestureView,
                             gestureView,
                             OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:@"gestureView"];
}

- (UIView *)gestureView
{
    return objc_getAssociatedObject(self, &UIViewGestureView);
}

- (void)setKeyboardActiveView:(UIView *)keyboardActiveView
{
    [self willChangeValueForKey:@"keyboardActiveView"];
    [self.keyboardActiveView removeObserver:self
                                 forKeyPath:@"frame"];
    if (keyboardActiveView)
    {
        [keyboardActiveView addObserver:self
                             forKeyPath:@"frame"
                                options:0
                                context:NULL];
    }
    objc_setAssociatedObject(self,
                             &UIViewKeyboardActiveView,
                             keyboardActiveView,
                             OBJC_ASSOCIATION_ASSIGN);
    [self didChangeValueForKey:@"keyboardActiveView"];
}

- (UIPanGestureRecognizer *)keyboardPanRecognizer
{
    return objc_getAssociatedObject(self,
                                    &UIViewKeyboardPanRecognizer);
}

- (void)setKeyboardPanRecognizer:(UIPanGestureRecognizer *)keyboardPanRecognizer
{
    [self willChangeValueForKey:@"keyboardPanRecognizer"];
    objc_setAssociatedObject(self,
                             &UIViewKeyboardPanRecognizer,
                             keyboardPanRecognizer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"keyboardPanRecognizer"];
}

- (BOOL)isReassigningFirstResponder {
    NSNumber *isReassigningFirstResponderNumber = objc_getAssociatedObject(self,
                                                                     &UIViewIsReassigningFirstResponder);
    return [isReassigningFirstResponderNumber boolValue];
}

- (void)setIsReassigningFirstResponder:(BOOL)isReassigningFirstResponder
{
    [self willChangeValueForKey:@"isReassigningFirstResponder"];
    objc_setAssociatedObject(self,
                             &UIViewIsReassigningFirstResponder,
                             @(isReassigningFirstResponder),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self didChangeValueForKey:@"isReassigningFirstResponder"];
}

- (BOOL)keyboardWillRecede
{
    CGFloat keyboardViewHeight = self.keyboardActiveView.bounds.size.height;
    CGFloat keyboardWindowHeight = self.keyboardActiveView.window.bounds.size.height;
    CGPoint touchLocationInKeyboardWindow = [self.keyboardPanRecognizer locationInView:self.keyboardActiveView.window];
    
    CGFloat thresholdHeight = keyboardWindowHeight - keyboardViewHeight - self.keyboardTriggerOffset + 44.0f;
    CGPoint velocity = [self.keyboardPanRecognizer velocityInView:self.keyboardActiveView];
    
    return touchLocationInKeyboardWindow.y >= thresholdHeight && velocity.y >= 0;
}

@end
