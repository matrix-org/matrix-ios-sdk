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
 Reset the cell.

 The cell is no more displayed. This is time to release resources and removing listeners.
 In case of UITableViewCell or UIContentViewCell object, the cell must reset in a state
 that it can be reusable.
 */
- (void)didEndDisplay;

@end
