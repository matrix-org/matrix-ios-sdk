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
    // @TODO: move it to MXSession as this class has additional information to compute the optimal display name
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
 `MXLoginFlow` represents a login or a register flow supported by the home server.
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


/**
 `MXCredentials` represents the response to a login or a register request.
 */
@interface MXCredentials : MXJSONModel

    /**
     The home server name.
     */
    @property (nonatomic) NSString *home_server;

    /**
     The obtained user id.
     */
    @property (nonatomic) NSString *user_id;

    /**
     The access token to create a MXRestClient
     */
    @property (nonatomic) NSString *access_token;

@end


/**
 `MXCreateRoomResponse` represents the response to createRoom request.
 */
@interface MXCreateRoomResponse : MXJSONModel

    /**
     The allocated room id.
     */
    @property (nonatomic) NSString *room_id;

    /**
     The alias on this home server.
     */
    @property (nonatomic) NSString *room_alias;

@end

/**
 `MXPaginationResponse` represents a response from an api that supports pagination.
 */
@interface MXPaginationResponse : MXJSONModel

    /**
     An array of MXEvents.
     */
    @property (nonatomic) NSArray *chunk;

    /**
     The opaque token for the start.
     */
    @property (nonatomic) NSString *start;

    /**
     The opaque token for the end.
     */
    @property (nonatomic) NSString *end;

@end


/**
 `MXRoomMember` represents a room member.
 */
@interface MXRoomMember : MXJSONModel

    /**
     The user id.
     */
    @property (nonatomic) NSString *user_id;

    /**
     The user display name.
     */
    @property (nonatomic) NSString *displayname;

    /**
     The url of the user of the avatar.
     */
    @property (nonatomic) NSString *avatar_url;

    /**
     The timestamp of the last time the user has been active.
     */
    @property (nonatomic) NSUInteger last_active_ago;

    /**
     The membership state.
     */
    @property (nonatomic) NSString *membership;

    /* @TODO
    @property (nonatomic) NSString *presence;
    @property (nonatomic) NSString *status_msg;
     */

@end

