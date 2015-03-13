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

#import <UIKit/UIKit.h>
#import <MatrixSDK/MatrixSDK.h>

#import "MXKDataSource.h"
#import "MXKRecentCellData.h"
#import "MXKEventFormatter.h"

/**
 Identifier to use for cells that display a room is the rooms list.
 */
extern NSString *const kMXKRoomCellIdentifier;

/**
 The data source for `MXKRecentsViewController`.
 */
@interface MXKRecentListDataSource : MXKDataSource <UITableViewDataSource> {

@protected

    /**
     The data for the cells served by `MXKRecentsDataSource`.
     */
    NSMutableArray *rooms;
}

/**
 The matrix session.
 */
@property (nonatomic, readonly) MXSession *mxSession;


#pragma mark - Configuration
/**
 The type of events to display as messages.
 */
@property (nonatomic) NSArray *eventsFilterForMessages;

/**
 The events to display texts formatter.
 `MXKRoomCellDataStoring` instances can use it to format text.
 */
@property (nonatomic) MXKEventFormatter *eventFormatter;

/**
 Flag to not list redacted events in the messages list.
 */
@property (nonatomic) BOOL hideRedactions;

/**
 Flag to not list unsupported events in the messages list.
 */
@property (nonatomic) BOOL hideUnsupportedEvents;


#pragma mark - Life cycle
/**
 Initialise the data source to serve recents rooms data.
 
 @param mxSession the Matrix to retrieve contextual data.
 @return the newly created instance.
 */
- (instancetype)initWithMatrixSession:(MXSession*)mxSession;

@end
