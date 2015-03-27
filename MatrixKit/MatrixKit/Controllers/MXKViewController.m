/*
 Copyright 2015 OpenMarket Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKViewController.h"

NSString *const kMXKViewControllerStartShakingNotification = @"kMXKViewControllerStartShakingNotification";
NSString *const kMXKViewControllerStopShakingNotification = @"kMXKViewControllerStopShakingNotification";

@interface MXKViewController () {
    id mxkViewControllerSessionStateObserver;
}
@end

@implementation MXKViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Add default activity indicator
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _activityIndicator.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
    _activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    
    CGRect frame = _activityIndicator.frame;
    frame.size.width += 30;
    frame.size.height += 30;
    _activityIndicator.bounds = frame;
    [_activityIndicator.layer setCornerRadius:5];
    
    _activityIndicator.center = self.view.center;
    [self.view addSubview:_activityIndicator];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (_mxSession) {
        // Register mxSession observer
        self.mxSession = _mxSession;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [[NSNotificationCenter defaultCenter] removeObserver:mxkViewControllerSessionStateObserver];
    [_activityIndicator stopAnimating];
}

- (void)setView:(UIView *)view {
    [super setView:view];
    
    // Keep the activity indicator (if any)
    if (_activityIndicator) {
        _activityIndicator.center = self.view.center;
        [self.view addSubview:_activityIndicator];
    }
}

#pragma mark -

- (void)setMxSession:(MXSession *)mxSession {
    // Remove potential session observer
    [[NSNotificationCenter defaultCenter] removeObserver:mxkViewControllerSessionStateObserver];
    
    if (mxSession) {
        // Register session state observer
        __weak typeof(self) weakSelf = self;
        mxkViewControllerSessionStateObserver = [[NSNotificationCenter defaultCenter] addObserverForName:MXSessionStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            
            __strong __typeof(weakSelf)strongSelf = weakSelf;
            // Check whether the concerned session is the associated one
            if (notif.object == strongSelf.mxSession) {
                [self didMatrixSessionStateChange];
            }
        }];
    }
    
    _mxSession = mxSession;
    
    // Force update
    [self didMatrixSessionStateChange];
}

- (void)didMatrixSessionStateChange {
    // Retrieve the main navigation controller if the current view controller is embedded inside a split view controller.
    UINavigationController *mainNavigationController = nil;
    if (self.splitViewController) {
        mainNavigationController = self.navigationController;
        UIViewController *parentViewController = self.parentViewController;
        while (parentViewController) {
            if (parentViewController.navigationController) {
                mainNavigationController = parentViewController.navigationController;
                parentViewController = parentViewController.parentViewController;
            } else {
                break;
            }
        }
    }
    
    if (_mxSession) {
        // The navigation bar tintColor depends on matrix homeserver reachability status
        if (_mxSession.state == MXSessionStateHomeserverNotReachable) {
            self.navigationController.navigationBar.barTintColor = [UIColor redColor];
            if (mainNavigationController) {
                mainNavigationController.navigationBar.barTintColor = [UIColor redColor];
            }
        } else {
            // Restore default tintColor
            self.navigationController.navigationBar.barTintColor = nil;
            if (mainNavigationController) {
                mainNavigationController.navigationBar.barTintColor = nil;
            }
        }
        
        // Run activity indicator if need
        if (_mxSession.state == MXSessionStateSyncInProgress || _mxSession.state == MXSessionStateInitialised) {
            [self.view bringSubviewToFront:_activityIndicator];
            [_activityIndicator startAnimating];
        } else {
            [_activityIndicator stopAnimating];
        }
    } else {
        // Hide potential activity indicator
        if (_activityIndicator) {
            [_activityIndicator stopAnimating];
        }
        
        // Restore default tintColor
        self.navigationController.navigationBar.barTintColor = nil;
        if (mainNavigationController) {
            mainNavigationController.navigationBar.barTintColor = nil;
        }
    }
}

#pragma mark - Shake handling

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXKViewControllerStartShakingNotification
                                                            object:self
                                                          userInfo:nil];
    }
}

- (void)motionCancelled:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    [self motionEnded:motion withEvent:event];
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXKViewControllerStopShakingNotification
                                                            object:self
                                                          userInfo:nil];
    }
}

- (BOOL)canBecomeFirstResponder {
    return _postShakeNotification;
}


@end