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

@implementation MXKRoomBubbleCellData
@synthesize senderId, attributedTextMessage;

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)roomDataSource {
    self = [self init];
    if (self) {

        // @TODO
        _event = event;
        senderId = event.userId;
        MXKEventFormatterError error;
        NSString *eventString = [roomDataSource.eventFormatter stringFromEvent:event withRoomState:roomState error:&error];

        // @TODO: Manage error
        attributedTextMessage = [[NSAttributedString alloc] initWithString:eventString];
    }
    return self;
}

@end
