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

#import <Foundation/Foundation.h>

#import "MXKCellData.h"

@protocol MXKCellRenderingDelegate;

/**
 `MXKCellRendering` defines a protocol a view must conform to display a cell.

 A cell is a generic term. It can be a UITableViewCell or a UICollectionViewCell or any object
 expected by the end view controller.
 */
@protocol MXKCellRendering <NSObject>

/**
 Configure the cell in order to display the passed data.
 
 The object implementing the `MXKCellRendering` protocol should be able to cast the past object
 into its original class.
 
 @param cellData the data object to render.
 */
- (void)render:(MXKCellData*)cellData;

/**
 Compute the height of the cell to display the passed data.
 
 @param cellData the data object to render.
 @param maxWidth the maximum available width.
 @return the cell height
 */
+ (CGFloat)heightForCellData:(MXKCellData*)cellData withMaximumWidth:(CGFloat)maxWidth;

@optional

/**
 User's actions delegate.
 */
@property (nonatomic, weak) id<MXKCellRenderingDelegate> delegate;

/**
 Reset the cell.

 The cell is no more displayed. This is time to release resources and removing listeners.
 In case of UITableViewCell or UIContentViewCell object, the cell must reset in a state
 that it can be reusable.
 */
- (void)didEndDisplay;

@end


/**
`MXKCellRenderingDelegate` defines a protocol used when the user has interactions with
 the cell view.
 */
@protocol MXKCellRenderingDelegate <NSObject>

/**
 Tells the delegate that a user action (button pressed, tap, long press...) has been observed in the cell.

 The action is described by the `actionIdentifier` param.
 This identifier is specific and depends to the cell view class implementing MXKCellRendering.
 
 @param cell the cell in which gesture has been observed.
 @param actionIdentifier an identifier indicating the action type (tap, long press...) and which part of the cell is concerned.
 @param userInfo a dict containing additional information. It depends on actionIdentifier. May be nil.
 */
- (void)cell:(id<MXKCellRendering>)cell didRecognizeAction:(NSString*)actionIdentifier userInfo:(NSDictionary *)userInfo;

@end

