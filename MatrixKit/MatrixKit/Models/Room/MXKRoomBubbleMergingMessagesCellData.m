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

#import "MXKRoomBubbleMergingMessagesCellData.h"

// @TODO: This string was exposed on Console for latter processing.
// Not sure it is the right way to do. Moreover, this can be a constant in future
// since it needs to be internationalised.
NSString *const kMXKRoomBubbleCellDataUnsupportedEventDescriptionPrefix = @"Unsupported event: ";

@interface MXKRoomBubbleMergingMessagesCellData () {

    /**
     The data source owner of this instance.
     */
    MXKRoomDataSource *roomDataSource;
}

@end

@implementation MXKRoomBubbleMergingMessagesCellData
@synthesize senderId, senderDisplayName, attributedTextMessage, startsWithSenderName, isIncoming, date;

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)roomDataSource2 {
    self = [self init];
    if (self) {
        roomDataSource = roomDataSource2;
        
        // @TODO
        senderId = event.userId;
        MXKEventFormatterError error;
        NSString *eventString = [roomDataSource.eventFormatter stringFromEvent:event withRoomState:roomState error:&error];

        // @TODO: Manage error
        attributedTextMessage = [[NSAttributedString alloc] initWithString:eventString];
    }
    return self;
}

- (BOOL)addEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState {
    BOOL contatenated = NO;

    NSLog(@"addEvent: %@", event);

    // Group events only if they come from the same sender
    if ([event.userId isEqualToString:senderId]) {

        NSLog(@"---\n%@", attributedTextMessage);

        MXKEventFormatterError error;
        NSString *eventString = [roomDataSource.eventFormatter stringFromEvent:event withRoomState:roomState error:&error];

        // @TODO: Manage error
        attributedTextMessage = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", eventString, attributedTextMessage]];

        NSLog(@"+++\n%@", attributedTextMessage);

        contatenated = YES;
    }
    return contatenated;
}

@end
