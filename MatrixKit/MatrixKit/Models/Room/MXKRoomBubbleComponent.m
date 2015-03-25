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

#import "MXKRoomBubbleComponent.h"

#import "MXEvent+MatrixKit.h"

@implementation MXKRoomBubbleComponent

- (instancetype)initWithEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState andEventFormatter:(MXKEventFormatter*)formatter {
    if (self = [super init]) {
        // Build text component related to this event
        _eventFormatter = formatter;
        MXKEventFormatterError error;
        NSString *eventString = [_eventFormatter stringFromEvent:event withRoomState:roomState error:&error];
        if (eventString.length) {
            // Manage error
            if (error != MXKEventFormatterErrorNone) {
                switch (error) {
                    case MXKEventFormatterErrorUnsupported:
                        event.mxkState = MXKEventStateUnsupported;
                        break;
                    case MXKEventFormatterErrorUnexpected:
                        event.mxkState = MXKEventStateUnexpected;
                        break;
                    case MXKEventFormatterErrorUnknownEventType:
                        event.mxkState = MXKEventStateUnknownType;
                        break;
                        
                    default:
                        break;
                }
            }
            
            _textMessage = eventString;
            _attributedTextMessage = nil;
            
            // Set date time
            if (event.originServerTs != kMXUndefinedTimestamp) {
                _date = [NSDate dateWithTimeIntervalSince1970:(double)event.originServerTs/1000];
            } else {
                _date = nil;
            }
            
            // Keep ref on event (used in case of redaction)
            _event = event;
        } else {
            // Ignore this event
            self = nil;
        }
    }
    return self;
}

- (void)dealloc {
}

- (void)updateWithRedactedEvent:(MXEvent*)redactedEvent {
    
    // Build text component related to this event (Note: we don't have valid room state here, userId will be used as display name)
    MXKEventFormatterError error;
    _textMessage = [_eventFormatter stringFromEvent:redactedEvent withRoomState:nil error:&error];
    _event = redactedEvent;
}

- (NSAttributedString*)attributedTextMessage {
    if (!_attributedTextMessage) {
        // Retrieve string attributes from formatter
        NSDictionary *attributes = [_eventFormatter stringAttributesForEvent:_event];
        if (attributes) {
            _attributedTextMessage = [[NSAttributedString alloc] initWithString:_textMessage attributes:attributes];
        } else {
            _attributedTextMessage = [[NSAttributedString alloc] initWithString:_textMessage];
        }
    }
    
    return _attributedTextMessage;
}

@end

