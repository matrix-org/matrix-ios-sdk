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
 Formatting result codes.
 */
typedef enum : NSUInteger {

    /**
     The formatting was successful.
     */
    MXKEventFormatterErrorNone,

    /**
     The formatter knows the event type but it encountered data that it does not support.
     */
    MXKEventFormatterErrorUnsupported,

    /**
     The formatter encountered unexpected data in the event.
     */
    MXKEventFormatterErrorUnexpected,

    /**
     The formatter does not support the type of the passed event.
     */
    MXKEventFormatterErrorUnknownEventType

} MXKEventFormatterError;

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
 The date formatter
 */
@property (nonatomic, readonly) NSDateFormatter *dateFormatter;

/**
 Initialise the event formatter.

 @param mxSession the Matrix to retrieve contextual data.
 @return the newly created instance.
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

/**
 Checks whether the event is related to an attachment and if it is supported.

 @param event
 @return YES if the provided event is related to a supported attachment type.
 */
- (BOOL)isSupportedAttachment:(MXEvent*)event;

/**
 Return the suitable url to display the content thumbnail into the provided view size.
 
 @param contentURI
 @param viewSize in points, this method will convert this size in pixels by considering screen scale
 @param thumbnailingMethod method of thumbnailing supported by the matrix content repository
 @return the thumbnail url
 */
- (NSString*)thumbnailURLForContent:(NSString*)contentURI inViewSize:(CGSize)viewSize withMethod:(MXThumbnailingMethod)thumbnailingMethod;


#pragma mark - Events to strings conversion methods
/**
 Compose the event sender display name according to the current room state.
 
 @param event the event to format.
 @param roomState the room state right before the event.
 @return the sender display name
 */
- (NSString*)senderDisplayNameForEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState;

/**
 Retrieve the avatar url of the event sender from the current room state.
 
 @param event the event to format.
 @param roomState the room state right before the event.
 @return the sender avatar url
 */
- (NSString*)senderAvatarUrlForEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState;

/**
 Generate a displayable string representating the event.
 
 @param event the event to format.
 @param roomState the room state right before the event.
 @param error the error code. In case of formatting error, the formatter may return non nil string as a proposal.
 @return the display text for the event.
 */
- (NSString*)stringFromEvent:(MXEvent*)event withRoomState:(MXRoomState*)roomState error:(MXKEventFormatterError*)error;

/**
 Return sets of attributes for the displayable string representing the event.
 
 @param event the event.
 @return sets of attributes to apply on event description.
 */
- (NSDictionary*)stringAttributesForEvent:(MXEvent*)event;


#pragma mark - Fake event objects creation
- (MXEvent*)fakeRoomMessageEventForRoomId:(NSString*)roomId withEventId:(NSString*)eventId andContent:(NSDictionary*)content;


#pragma mark - Timestamp formatting
/**
 Generate the date in string format corresponding to the timestamp.
 The returned string is localised according to the current device settings.

 @param timestamp the timestamp in milliseconds since Epoch.
 @return the string representation of the event data.
 */
- (NSString*)dateStringForTimestamp:(uint64_t)timestamp;

/**
 Generate the date in string format corresponding to the event.
 The returned string is localised according to the current device settings.
 
 @param event the event to format.
 @return the string representation of the event data.
 */
- (NSString*)dateStringForEvent:(MXEvent*)event;

@end
