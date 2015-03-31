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

#import "MatrixKit.h"
#import "JSQMessages.h"

/**
 `MXKSampleJSQMessageMediaData` is a connector between `MXKRoomBubbleCellData` data and
 the `JSQMessageMediaData` protocol required by JSQMessages in order to display media
 like images.
 */
@interface MXKSampleJSQMessageMediaData : NSObject <JSQMessageMediaData>

/**
 Initialize a data connector to a `MXKRoomBubbleCellData` object.

 @param cellData the `MXKRoomBubbleCellData` object.
 @return the newly created instance.
 */
- (instancetype)initWithCellData:(MXKRoomBubbleCellData*)cellData;

@end
