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

#import "MXJSONModel.h"

/**
 This file contains definitions of basic JSON responses or objects received
 from a Matrix home server.
 
 Note: some such class can be defined in their own file (ex: MXEvent)
 */

/**
  `MXPublicRoom` represents a public room returned by the publicRoom request
 */
@interface MXPublicRoom : MXJSONModel

    @property (nonatomic) NSString *room_id;
    @property (nonatomic) NSString *name;
    @property (nonatomic) NSArray *aliases; // Array of NSString
    @property (nonatomic) NSString *topic;
    @property (nonatomic) NSUInteger num_joined_members;

    // The display name is computed from available information
    // @TODO: move it to MXData as this class has additional information to compute the optimal display name
    @property (nonatomic, readonly) NSString *displayname;

@end


/**
 Login flow types
 */
FOUNDATION_EXPORT NSString *const kMatrixLoginFlowTypePassword;
FOUNDATION_EXPORT NSString *const kMatrixLoginFlowTypeOAuth2;
FOUNDATION_EXPORT NSString *const kMatrixLoginFlowTypeTypeEmailCode;
FOUNDATION_EXPORT NSString *const kMatrixLoginFlowTypeEmailUrl;
FOUNDATION_EXPORT NSString *const kMatrixLoginFlowTypeEmailIdentity;

/**
 `MXLoginFlow` represents a login flow supported by the home server.
 */
@interface MXLoginFlow : MXJSONModel

    /**
     The flow type among kMatrixLoginFlowType* types.
     @see http://matrix.org/docs/spec/#password-based and below for the types descriptions
     */
    @property (nonatomic) NSString *type;

    /**
     The list of stages to proceed the login. This is an array of NSStrings
     */
    @property (nonatomic) NSArray *stages;

@end
