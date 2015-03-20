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

#import "MXKRoomBubbleComponent.h"

@interface MXKRoomBubbleCellData (){
    /**
     For this model, each bubble is composed by only one component (based on one event)
     */
    MXKRoomBubbleComponent *component;
}

@end

@implementation MXKRoomBubbleCellData
@synthesize senderId, senderDisplayName, attributedTextMessage, startsWithSenderName, isIncoming, date;

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)roomDataSource {
    self = [self init];
    if (self) {
        // Create the bubble component
        component = [[MXKRoomBubbleComponent alloc] initWithEvent:event andRoomState:roomState andEventFormatter:roomDataSource.eventFormatter];
        if (component) {
            senderId = event.userId;
            senderDisplayName = [roomDataSource.eventFormatter senderDisplayNameForEvent:event withRoomState:roomState];
            isIncoming = ([event.userId isEqualToString:roomDataSource.mxSession.myUser.userId] == NO);
            
            // Deduce other properties from its component
            attributedTextMessage = component.attributedTextMessage;
            startsWithSenderName = (event.isEmote || [component.textMessage hasPrefix:senderDisplayName]);
            date = component.date;
        } else {
            // Ignore this event
            self = nil;
        }
    }
    return self;
}

- (void)dealloc {
    component = nil;
}

@end
