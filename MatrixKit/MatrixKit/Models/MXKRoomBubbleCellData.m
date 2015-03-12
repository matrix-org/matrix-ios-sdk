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

#import "MXKRoomBubbleCellData.h"

#import "MXKRoomDataSource.h"

// @TODO: This string was exposed on Console for latter processing.
// Not sure it is the right way to do. Moreover, this can be a constant in future
// since it needs to be internationalised.
NSString *const kMXKRoomBubbleCellDataUnsupportedEventDescriptionPrefix = @"Unsupported event: ";

@interface MXKRoomBubbleCellData () {

    /**
     The data source owner of this `MXKRoomBubbleCellData` instance.
     */
    MXKRoomDataSource *roomDataSource;
}

@end

@implementation MXKRoomBubbleCellData
@synthesize senderId, attributedTextMessage;

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)roomDataSource2 {
    self = [self init];
    if (self) {
        roomDataSource = roomDataSource2;
        
        // @TODO
        senderId = event.userId;
        attributedTextMessage = [roomDataSource.eventFormatter stringFromEvent:event withRoomState:roomState];
    }
    return self;
}

- (BOOL)addEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState {
    BOOL contatenated = NO;

    // Group events only if they come from the same sender
    if ([event.userId isEqualToString:senderId]) {

        attributedTextMessage = [NSString stringWithFormat:@"%@\n%@", attributedTextMessage, [roomDataSource.eventFormatter stringFromEvent:event withRoomState:roomState]];
        [attributedTextMessage stringByAppendingString:event.eventId];
        contatenated = YES;
    }
    return contatenated;
}

@end
