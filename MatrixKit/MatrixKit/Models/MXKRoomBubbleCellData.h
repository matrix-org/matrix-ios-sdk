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
#import <MatrixSDK/MatrixSDK.h>

#import "MXKCellData.h"

/**
 `MXKRoomBubbleCellData` modelised the data for a `MXKRoomBubbleTableViewCell` cell.
 */
@interface MXKRoomBubbleCellData : MXKCellData

@property (nonatomic) NSString *senderId;

// The body of the message, or kind of content description in case of attachment (e.g. "image attachment")
@property (nonatomic) /*NSAttributedString @TODO*/ NSString *attributedTextMessage;

- (instancetype)initWithEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState;

// @TODO
//- (BOOL)addEvent:(MXEvent*)event;

@end
