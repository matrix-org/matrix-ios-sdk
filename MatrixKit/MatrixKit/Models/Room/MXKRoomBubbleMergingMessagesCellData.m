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
    
    /**
     YES if position of each component must be refreshed
     */
    BOOL shouldUpdateComponentsPosition;
}

@end

static NSAttributedString *messageSeparator = nil;

@implementation MXKRoomBubbleMergingMessagesCellData

- (instancetype)initWithEvent:(MXEvent *)event andRoomState:(MXRoomState *)roomState andRoomDataSource:(MXKRoomDataSource *)inRoomDataSource {
    self = [super initWithEvent:event andRoomState:roomState andRoomDataSource:inRoomDataSource];
    if (self) {
        roomDataSource = inRoomDataSource;
    }
    return self;
}

- (void)dealloc {
    roomDataSource = nil;
}

- (BOOL)addEvent:(MXEvent*)event andRoomState:(MXRoomState*)roomState {
    // We group together text messages from the same user
    if ([event.userId isEqualToString:self.senderId] && (self.dataType == MXKRoomBubbleCellDataTypeText)) {
        // Attachments (image, video ...) cannot be added here
        if ([roomDataSource.eventFormatter isSupportedAttachment:event]) {
            return NO;
        }
        
        // Check sender information
        NSString *eventSenderName = [roomDataSource.eventFormatter senderDisplayNameForEvent:event withRoomState:roomState];
        NSString *eventSenderAvatar = [roomDataSource.eventFormatter senderAvatarUrlForEvent:event withRoomState:roomState];
        if ((self.senderDisplayName || eventSenderName) &&
            ([self.senderDisplayName isEqualToString:eventSenderName] == NO)) {
            return NO;
        }
        if ((self.senderAvatarUrl || eventSenderAvatar) &&
            ([self.senderAvatarUrl isEqualToString:eventSenderAvatar] == NO)) {
            return NO;
        }
        
        // Create new message component
        MXKRoomBubbleComponent *addedComponent = [[MXKRoomBubbleComponent alloc] initWithEvent:event andRoomState:roomState andEventFormatter:roomDataSource.eventFormatter];
        if (addedComponent) {
            [self addComponent:addedComponent];
        }
        // else the event is ignored, we consider it as handled
        return YES;
    }
    return NO;
}

#pragma mark - 

- (void)prepareBubbleComponentsPosition {
    // Set position of the first component
    [super prepareBubbleComponentsPosition];
    
    // Check whether the position of other components need to be refreshed
    if (self.dataType != MXKRoomBubbleCellDataTypeText || !shouldUpdateComponentsPosition || bubbleComponents.count < 2) {
        return;
    }
    
    // Compute height of the first text component
    MXKRoomBubbleComponent *component = [bubbleComponents firstObject];
    CGFloat componentHeight = [self rawTextHeight:component.attributedTextMessage];
    
    // Set position for each other component
    CGFloat positionY = component.position.y;
    CGFloat cumulatedHeight = 0;
    NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithAttributedString:component.attributedTextMessage];
    for (NSUInteger index = 1; index < bubbleComponents.count; index++) {
        cumulatedHeight += componentHeight;
        positionY += componentHeight;
        
        component = [bubbleComponents objectAtIndex:index];
        component.position = CGPointMake(0, positionY);
        
        // Compute height of the current component
        [attributedString appendAttributedString:[MXKRoomBubbleMergingMessagesCellData messageSeparator]];
        [attributedString appendAttributedString:component.attributedTextMessage];
        componentHeight = [self rawTextHeight:attributedString] - cumulatedHeight;
    }
    shouldUpdateComponentsPosition = NO;
}

#pragma mark -

- (NSAttributedString*)attributedTextMessage {
    if (!attributedTextMessage.length && bubbleComponents.count) {
        // Create attributed string
        NSMutableAttributedString *currentAttributedTextMsg;
        
        for (MXKRoomBubbleComponent* component in bubbleComponents) {
            if (!currentAttributedTextMsg) {
                currentAttributedTextMsg = [[NSMutableAttributedString alloc] initWithAttributedString:component.attributedTextMessage];;
            } else {
                // Append attributed text
                [currentAttributedTextMsg appendAttributedString:[MXKRoomBubbleMergingMessagesCellData messageSeparator]];
                [currentAttributedTextMsg appendAttributedString:component.attributedTextMessage];
            }
        }
        attributedTextMessage = currentAttributedTextMsg;
    }
    
    return attributedTextMessage;
}

- (void)setMaxTextViewWidth:(CGFloat)inMaxTextViewWidth {
    [super setMaxTextViewWidth:inMaxTextViewWidth];
    
    // Check change
    if (CGSizeEqualToSize(self.contentSize, CGSizeZero)) {
        // Position of each components should be computed again
        shouldUpdateComponentsPosition = YES;
    }
}

#pragma mark -

+ (NSAttributedString *)messageSeparator {
    @synchronized(self) {
        if(messageSeparator == nil) {
            messageSeparator = [[NSAttributedString alloc] initWithString:@"\n\n" attributes:@{NSForegroundColorAttributeName : [UIColor blackColor],
                                                                                                   NSFontAttributeName: [UIFont systemFontOfSize:4]}];
        }
    }
    return messageSeparator;
}

#pragma mark - Privates

- (void)addComponent:(MXKRoomBubbleComponent*)addedComponent {
    // Check date of existing components to insert this new one
    NSUInteger index = bubbleComponents.count;
    while (index) {
        MXKRoomBubbleComponent *msgComponent = [bubbleComponents objectAtIndex:(--index)];
        if ([msgComponent.date compare:addedComponent.date] != NSOrderedDescending) {
            // New component will be inserted here
            index ++;
            break;
        }
    }
    // Insert new component
    [bubbleComponents insertObject:addedComponent atIndex:index];
    
    // Reset the current attributed string (This will reset rendering attributes).
    self.attributedTextMessage = nil;
    
    // Position of each components should be computed again
    shouldUpdateComponentsPosition = YES;
}

@end
