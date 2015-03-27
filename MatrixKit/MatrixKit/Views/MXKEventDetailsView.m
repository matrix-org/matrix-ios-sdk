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

#import "MXKEventDetailsView.h"

#import "MXEvent+MatrixKit.h"

@interface MXKEventDetailsView () {
    /**
     The displayed event
     */
    MXEvent *mxEvent;
    
    /**
     The matrix session.
     */
    MXSession *mxSession;
}
@end

@implementation MXKEventDetailsView

- (instancetype)initWithEvent:(MXEvent*)event andMatrixSession:(MXSession*)session {
    NSArray *nibViews = [[NSBundle bundleForClass:[MXKEventDetailsView class]] loadNibNamed:NSStringFromClass([MXKEventDetailsView class])
                                                                                          owner:nil
                                                                                        options:nil];
    self = nibViews.firstObject;
    if (self) {
        mxEvent = event;
        mxSession = session;
        
        [self setTranslatesAutoresizingMaskIntoConstraints: NO];
        
        // Disable redact button by default
        _redactButton.enabled = NO;
        
        if (mxEvent) {
            NSMutableDictionary *eventDict = [NSMutableDictionary dictionaryWithDictionary:mxEvent.originalDictionary];
            
            // Remove event type added by SDK
            [eventDict removeObjectForKey:@"event_type"];
            // Remove null values and empty dictionaries
            for (NSString *key in eventDict.allKeys) {
                if ([[eventDict objectForKey:key] isEqual:[NSNull null]]) {
                    [eventDict removeObjectForKey:key];
                } else if ([[eventDict objectForKey:key] isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *dict = [eventDict objectForKey:key];
                    if (!dict.count) {
                        [eventDict removeObjectForKey:key];
                    } else {
                        NSMutableDictionary *updatedDict = [NSMutableDictionary dictionaryWithDictionary:dict];
                        for (NSString *subKey in dict.allKeys) {
                            if ([[dict objectForKey:subKey] isEqual:[NSNull null]]) {
                                [updatedDict removeObjectForKey:subKey];
                            }
                        }
                        [eventDict setObject:updatedDict forKey:key];
                    }
                }
            }
            
            // Set text view content
            NSError *error;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:eventDict
                                                               options:NSJSONWritingPrettyPrinted
                                                                 error:&error];
            _textView.text = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            
            // Check whether the user can redact this event
            if (!mxEvent.isRedactedEvent) {
                // Here the event has not been already redacted, check the user's power level
                MXRoom *mxRoom = [mxSession roomWithRoomId:mxEvent.roomId];
                if (mxRoom) {
                    MXRoomPowerLevels *powerLevels = [mxRoom.state powerLevels];
                    NSUInteger userPowerLevel = [powerLevels powerLevelOfUserWithUserID:mxSession.myUser.userId];
                    if (powerLevels.redact) {
                        if (userPowerLevel >= powerLevels.redact) {
                            _redactButton.enabled = YES;
                        }
                    } else if (userPowerLevel >= [powerLevels minimumPowerLevelForSendingEventAsMessage:kMXEventTypeStringRoomRedaction]) {
                        _redactButton.enabled = YES;
                    }
                }
            }
        } else {
            _textView.text = nil;
        }
        
        // Hide potential activity indicator
        [_activityIndicator stopAnimating];
    }
    
    return self;
}

- (void)dealloc {
    mxEvent = nil;
    mxSession = nil;
}

#pragma mark - Actions

- (IBAction)onButtonPressed:(id)sender {
    if (sender == _redactButton) {
        MXRoom *mxRoom = [mxSession roomWithRoomId:mxEvent.roomId];
        if (mxRoom) {
            [_activityIndicator startAnimating];
            [mxRoom redactEvent:mxEvent.eventId reason:nil success:^{
                [_activityIndicator stopAnimating];
                [self removeFromSuperview];
            } failure:^(NSError *error) {
                NSLog(@"[MXKEventDetailsView] Redact event (%@) failed: %@", mxEvent.eventId, error);
                // TODO Alert user
//                [[AppDelegate theDelegate] showErrorAsAlert:error];
                [_activityIndicator stopAnimating];
            }];
        }
        
    } else if (sender == _closeButton) {
        [self removeFromSuperview];
    }
}

@end