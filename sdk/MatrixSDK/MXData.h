/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXSession.h"

#import "MXRoomData.h"

/**
 `MXData` manages data and events from the home server
 It is responsible for:
    - retrieving events from the home server
    - storing them
    - serving them to the app
 */
@interface MXData : NSObject

- (id)initWithMatrixSession:(MXSession*)mSession;

- (void)start;
- (void)stop;

- (MXRoomData *)getRoomData:(NSString*)room_id;

@end
