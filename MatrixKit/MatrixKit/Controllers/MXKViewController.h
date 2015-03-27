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

#import <UIKit/UIKit.h>

#import <MatrixSDK/MatrixSDK.h>

/**
 Posted when the user starts shaking the device on this view controller.
 The notification object is the view controller itself. The `userInfo` dictionary is nil.
 */
extern NSString *const kMXKViewControllerStartShakingNotification;

/**
 Posted when the user stops shaking the device on this view controller.
 The notification object is the view controller itself. The `userInfo` dictionary is nil.
 */
extern NSString *const kMXKViewControllerStopShakingNotification;

/**
 MXKViewController extends UIViewController to handle requirements for
 any matrixKit view controllers.
 
 It manages the following points:
 - stop/start activity indicator according to associated matrix session state.
 - update view appearance on matrix session state change.
 */

@interface MXKViewController : UIViewController

/**
 Associated matrix session (nil by default).
 This property is used to update view appearance according to the session state.
 */
@property (nonatomic) MXSession *mxSession;

/**
 NO by default.
 When this property value is YES, the view controller posts a notification when the user starts or stops
 shaking the device while the view controller is displayed (see kMXKViewControllerStartShakingNotification/
 kMXKViewControllerStopShakingNotification notifications).
 */
@property (nonatomic) BOOL postShakeNotification;

/**
 Activity indicator view.
 By default this activity indicator is centered inside the view controller view. It is automatically
 start on the following matrix session states: `MXSessionStateInitialised` and `MXSessionStateSyncInProgress`.
 It is stopped on other states.
 Set nil to disable activity indicator animation.
 */
@property (nonatomic) UIActivityIndicatorView *activityIndicator;

/**
 Update view controller appearance according to the state of its associated matrix session.
 This method is called on session state change (see `MXSessionStateDidChangeNotification`).
 
 The default implementation:
 - switches in red the navigation bar tintColor on `MXSessionStateHomeserverNotReachable`
 - starts activity indicator on `MXSessionStateInitialised` and `MXSessionStateSyncInProgress`.
 
 Override it to customize view appearance according to session state.
  */
- (void)didMatrixSessionStateChange;

@end

