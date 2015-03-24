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

#import "MXKRoomDataSource.h"

#import "MXEvent+MatrixKit.h"

@class MXKRoomDataSource;
/**
 `MXKRoomBubbleCellDataStoring` defines a protocol a class must conform in order to store MXKRoomBubble cell data
 managed by `MXKRoomDataSource`.
 
 @discussion
 @TODO: As it is currently implemented, MXKRoomDataSource passed each event to a MXKRoomBubbleCellDataStoring class object.
 This later, in initWithEvent or addEvent, will process the event in order to extract data to display in the cell.
 Not sure it is the right way.

 The other way is to keep all business logic in the MXKRoomDataSource and use MXKRoomBubbleCellDataStoring only
 as a storing class.

 Pros/Cons of the current implementation:
 Cons:
   - These methods are called on the internal processing queue of MXKRoomDataSource.
   - The business logic risks to be cut in 2 classes the MXKRoomBubbleCellDataStoring class and MXKRoomDataSource.
 
 Pros:
   - This model seems easier for developers wanting to customize the display.
     The developer creates his own MXKCellRendering class for room bubbles display. If he needs more data, he can
     can create his own MXKRoomBubbleCellDataStoring class that will be able to extract the required data.
     There is no need to change code in MXKRoomDataSource.
 
 For now, we keep the current design. When the MXKRoomViewController will be able to display messages as Console does, 
 we will check if we need to change the implementation.
 */
@protocol MXKRoomBubbleCellDataStoring <NSObject>

#pragma mark - Data displayed by a room bubble cell

/**
 The sender Id
 */
@property (nonatomic) NSString *senderId;

/**
 The sender display name composed when event occured
 */
@property (nonatomic) NSString *senderDisplayName;

/**
 The body of the message with sets of attributes, or kind of content description in case of attachment (e.g. "image attachment")
 */
@property (nonatomic) NSAttributedString *attributedTextMessage;

/**
 YES if the sender name appears at the beginning of the message text
 */
@property (nonatomic) BOOL startsWithSenderName;

/**
 YES when the bubble is composed by incoming event(s).
 */
@property (nonatomic) BOOL isIncoming;

/**
 The bubble date
 */
@property (nonatomic) NSDate *date;


#pragma mark - Public methods
/**
 Create a new `MXKCellData` object for a new bubble cell.
 
 @param event the event to be displayed in the cell.
 @param roomState the room state when the event occured.
 @param roomDataSource the `MXKRoomDataSource` object that will use this instance.
 @return the newly created instance.
 */
- (instancetype)initWithEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState andRoomDataSource:(MXKRoomDataSource*)roomDataSource;

@optional
/**
 Attempt to add a new event to the bubble.
 
 @param event the event to be displayed in the cell.
 @param roomState the room state when the event occured.
 @return YES if the model accepts that the event can concatenated to events already in the bubble.
 */
- (BOOL)addEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState;

@end
