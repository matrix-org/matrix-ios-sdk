/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXRoom.h"

/**
 A `MXPreviewRoom` instance allows to get data from a room the user has not necessarly joined.

 */
@interface MXPreviewRoom : MXRoom

/**
 Get room data by doing an initial sync from the homeserver.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)initialSync:(void (^)())success
                        failure:(void (^)(NSError *error))failure;

@end
