
/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXCAlert.h"

#import <objc/runtime.h>

@interface MXCAlert()
{
    UIViewController* parentViewController;
    NSMutableArray *actions; // use only for iOS < 8
}

@property(nonatomic, strong) id alert; // alert is kind of UIAlertController for IOS 8 and later, in other cases it's kind of UIAlertView or UIActionSheet.
@end

@implementation MXCAlert

- (void)dealloc {
    // iOS < 8
    if ([_alert isKindOfClass:[UIActionSheet class]] || [_alert isKindOfClass:[UIAlertView class]]) {
        // Dismiss here AlertView or ActionSheet (if any) because its delegate is released
        [self dismiss:NO];
    }
    
    _alert = nil;
    parentViewController = nil;
    actions = nil;
}

- (id)initWithTitle:(NSString *)title message:(NSString *)message style:(MXCAlertStyle)style {
    if (self = [super init]) {
        // Check iOS version
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8) {
            _alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:(UIAlertControllerStyle)style];
        } else {
            // Use legacy objects
            if (style == MXCAlertStyleActionSheet) {
                _alert = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
            } else {
                _alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:self cancelButtonTitle:nil otherButtonTitles:nil];
            }
            
            self.cancelButtonIndex = -1;
        }
    }
    return self;
}


- (NSInteger)addActionWithTitle:(NSString *)title style:(MXCAlertActionStyle)style handler:(blockMXCAlert_onClick)handler {
    NSInteger index = 0;
    if ([_alert isKindOfClass:[UIAlertController class]]) {
        index = [(UIAlertController *)_alert actions].count;
        UIAlertAction* action = [UIAlertAction actionWithTitle:title
                                                         style:(UIAlertActionStyle)style
                                                       handler:^(UIAlertAction * action) {
                                                           if (handler) {
                                                               handler(self);
                                                           }
                                                       }];
        
        [(UIAlertController *)_alert addAction:action];
    } else if ([_alert isKindOfClass:[UIActionSheet class]]) {
        if (actions == nil) {
            actions = [NSMutableArray array];
        }
        index = [(UIActionSheet *)_alert addButtonWithTitle:title];
        if (handler) {
            [actions addObject:handler];
        } else {
            [actions addObject:[NSNull null]];
        }
    } else if ([_alert isKindOfClass:[UIAlertView class]]) {
        if (actions == nil) {
            actions = [NSMutableArray array];
        }
        index = [(UIAlertView *)_alert addButtonWithTitle:title];
        if (handler) {
            [actions addObject:handler];
        } else {
            [actions addObject:[NSNull null]];
        }
    }
    return index;
}

- (void)addTextFieldWithConfigurationHandler:(blockMXCAlert_textFieldHandler)configurationHandler {
    if ([_alert isKindOfClass:[UIAlertController class]]) {
        [(UIAlertController *)_alert addTextFieldWithConfigurationHandler:configurationHandler];
    } else if ([_alert isKindOfClass:[UIAlertView class]]) {
        UIAlertView *alertView = (UIAlertView *)_alert;
        // Check the current style
        if (alertView.alertViewStyle == UIAlertViewStyleDefault) {
            // Add the first text fields
            alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
            
            if (configurationHandler) {
                // Store the callback
                UITextField *textField = [alertView textFieldAtIndex:0];
                objc_setAssociatedObject(textField, "configurationHandler", [configurationHandler copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else if (alertView.alertViewStyle != UIAlertViewStyleLoginAndPasswordInput) {
            // Add a second text field
            alertView.alertViewStyle = UIAlertViewStyleLoginAndPasswordInput;
            
            if (configurationHandler) {
                // Store the callback
                UITextField *textField = [alertView textFieldAtIndex:1];
                objc_setAssociatedObject(textField, "configurationHandler", [configurationHandler copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        // CAUTION 1: only 2 text fields are supported fro iOS < 8
        // CAUTION 2: alert style "UIAlertViewStyleSecureTextInput" is not supported, use the configurationHandler to handle secure text field
    }
}

- (void)showInViewController:(UIViewController*)viewController {
    if ([_alert isKindOfClass:[UIAlertController class]]) {
        if (viewController) {
            parentViewController = viewController;
            if (self.sourceView) {
                [_alert popoverPresentationController].sourceView = self.sourceView;
                [_alert popoverPresentationController].sourceRect = self.sourceView.bounds;
            }
            [viewController presentViewController:(UIAlertController *)_alert animated:YES completion:nil];
        }
    } else if ([_alert isKindOfClass:[UIActionSheet class]]) {
        [(UIActionSheet *)_alert showInView:[[UIApplication sharedApplication] keyWindow]];
    } else if ([_alert isKindOfClass:[UIAlertView class]]) {
        UIAlertView *alertView = (UIAlertView *)_alert;
        if (alertView.alertViewStyle != UIAlertViewStyleDefault) {
            // Call here textField handlers
            UITextField *textField = [alertView textFieldAtIndex:0];
            blockMXCAlert_textFieldHandler configurationHandler = objc_getAssociatedObject(textField, "configurationHandler");
            if (configurationHandler) {
                configurationHandler (textField);
            }
            if (alertView.alertViewStyle == UIAlertViewStyleLoginAndPasswordInput) {
                textField = [alertView textFieldAtIndex:1];
                blockMXCAlert_textFieldHandler configurationHandler = objc_getAssociatedObject(textField, "configurationHandler");
                if (configurationHandler) {
                    configurationHandler (textField);
                }
            }
        }
        [alertView show];
    }
}

- (void)dismiss:(BOOL)animated {
    if ([_alert isKindOfClass:[UIAlertController class]]) {
        // only dismiss it if it is presented
        if (parentViewController.presentedViewController == _alert) {
            [parentViewController dismissViewControllerAnimated:animated completion:nil];
        }
    } else if ([_alert isKindOfClass:[UIActionSheet class]]) {
        [((UIActionSheet *)_alert) dismissWithClickedButtonIndex:self.cancelButtonIndex animated:animated];
    } else if ([_alert isKindOfClass:[UIAlertView class]]) {
        [((UIAlertView *)_alert) dismissWithClickedButtonIndex:self.cancelButtonIndex animated:animated];
    }
    _alert = nil;
}

- (UITextField *)textFieldAtIndex:(NSInteger)textFieldIndex{
    if ([_alert isKindOfClass:[UIAlertController class]]) {
        return [((UIAlertController*)_alert).textFields objectAtIndex:textFieldIndex];
    } else if ([_alert isKindOfClass:[UIAlertView class]]) {
        return [((UIAlertView*)_alert) textFieldAtIndex:textFieldIndex];
    }
    return nil;
}

#pragma mark - UIAlertViewDelegate (iOS < 8)

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    // sanity check
    // the user could have forgotten to set the cancel button index
    if (buttonIndex < actions.count) {
        // Retrieve the callback
        blockMXCAlert_onClick block = [actions objectAtIndex:buttonIndex];
        if ([block isEqual:[NSNull null]] == NO) {
            // And call it
            dispatch_async(dispatch_get_main_queue(), ^{
                block(self);
            });
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Release alert reference
            _alert = nil;
        });
    }
}

#pragma mark - UIActionSheetDelegate (iOS < 8)

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    // sanity check
    // the user could have forgotten to set the cancel button index
    if (buttonIndex < actions.count) {
        // Retrieve the callback
        blockMXCAlert_onClick block = [actions objectAtIndex:buttonIndex];
        if ([block isEqual:[NSNull null]] == NO) {
            // And call it
            dispatch_async(dispatch_get_main_queue(), ^{
                block(self);
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            // Release _alert reference
            _alert = nil;
        });
    }
}

@end
