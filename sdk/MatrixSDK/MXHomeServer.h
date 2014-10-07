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

#import "MXJSONModels.h"

// @TBD
typedef NSString* MXRoomVisibility;

@interface MXHomeServer : NSObject

@property (readonly, nonatomic) NSString *homeserver;

/**
 Create a MXHomeServer instance.
 
 @param homeserver The home server location (ex: http://matrix.org)
 
 @return The newly-initialized MXHomeServer.
 */
- (id)initWithHomeServer:(NSString*)homeserver;

/*
 #pragma mark - Registration operations
 - (void)getRegisterFlow:(void (^)(NSObject *tbd))success
 failure:(void (^)(NSError *error))failure;
 
 - (void)register:(void (^)(NSObject *tbd))success
 failure:(void (^)(NSError *error))failure;
 
 
 #pragma mark - Login operations
 - (void)getLoginFlow:(void (^)(NSObject *tbd))success
 failure:(void (^)(NSError *error))failure;
 - (void)login:(void (^)(NSObject *tbd))success
 failure:(void (^)(NSError *error))failure;
 */

/**
 Get the list of public rooms hosted by the home server.
 
 @param success A block object called when the operation succeeds. rooms is an array of MXPublicRoom objects
 @param failure A block object called when the operation fails.
 */
- (void)publicRooms:(void (^)(NSArray *rooms))success
            failure:(void (^)(NSError *error))failure;

@end
