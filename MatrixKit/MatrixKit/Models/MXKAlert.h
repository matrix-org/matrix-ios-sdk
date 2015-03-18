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

/**
 UIAlertView and UIActionSheet are deprecated in iOS 8. To create and manage alerts and action sheets in iOS 8 and later,
 we must use UIAlertController with a preferredStyle.
 
 `MXKAlert` class has been defined to handle alerts and action sheets independently of the iOS version.
 */

typedef enum : NSUInteger {
    MXKAlertActionStyleDefault = 0,
    MXKAlertActionStyleCancel,
    MXKAlertActionStyleDestructive
} MXKAlertActionStyle;

typedef enum : NSUInteger {
    MXKAlertStyleActionSheet = 0,
    MXKAlertStyleAlert
} MXKAlertStyle;

@interface MXKAlert : NSObject <UIActionSheetDelegate> {
}

typedef void (^blockMXKAlert_onClick)(MXKAlert *alert);
typedef void (^blockMXKAlert_textFieldHandler)(UITextField *textField);

@property(nonatomic) NSInteger cancelButtonIndex; // required to dismiss cusmtomAlert on iOS < 8 (default is -1).
@property(nonatomic, weak) UIView *sourceView;

- (id)initWithTitle:(NSString *)title message:(NSString *)message style:(MXKAlertStyle)style;

// Adds a button with the title. returns the index (0 based) of where it was added.
- (NSInteger)addActionWithTitle:(NSString *)title style:(MXKAlertActionStyle)style handler:(blockMXKAlert_onClick)handler;

// Adds a text field to an alert (Note: You can add a text field only if the style property is set to MXKAlertStyleAlert).
- (void)addTextFieldWithConfigurationHandler:(blockMXKAlert_textFieldHandler)configurationHandler;

- (void)showInViewController:(UIViewController*)viewController;

- (void)dismiss:(BOOL)animated;

- (UITextField *)textFieldAtIndex:(NSInteger)textFieldIndex;

@end
