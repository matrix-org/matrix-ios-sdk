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

/**
 `MXKEventFormatter` is an utility class for formating Matrix events into strings which
 will be displayed to the end user.
 */
@interface MXKEventFormatter : NSObject

/**
 Flag to not list redacted events in the messages list.
 Default is NO.
 */
@property (nonatomic) BOOL hideRedactions;

/**
 Flag to not list unsupported events in the messages list.
 Default is NO.
 */
@property (nonatomic) BOOL hideUnsupportedEvents;

/**
 Flag indicating if the formatter must build strings that will be displayed as subtitle.
 Default is NO.
 */
@property (nonatomic) BOOL isForSubtitle;

/**
 Initialise the event formatter.

 @param mxSession the Matrix to retrieve contextual data.
 @return the newly created instance.
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

/**
 Generate a displayable string representating the event.
 
 @param event the event to format.
 @param roomState the room state right before the event.
 @return the display text for the event.
 */
- (NSString*)stringFromEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState;

@end
