// 
// Copyright 2020 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"

/**
 `MXTurnServerResponse` represents the response to turnServer request.
 It provides TURN server configuration advised by the homeserver.
 */
@interface MXTurnServerResponse : MXJSONModel

/**
 The username of the Matrix user on the TURN server.
 */
@property (nonatomic) NSString *username;

/**
 The associated password.
 */
@property (nonatomic) NSString *password;

/**
 The list URIs of TURN servers - including STUN servers.
 The URI scheme obeys to http://tools.ietf.org/html/rfc7064#section-3.1
 and http://tools.ietf.org/html/rfc7065#section-3.1
 */
@property (nonatomic) NSArray<NSString *> *uris;

/**
 Time To Live. The time is seconds this data is still valid.
 It is computed by the user's homeserver when the request is made.
 Then, the SDK updates the property each time it is read.
 */
@property (nonatomic) NSUInteger ttl;

/**
 The `ttl` value transcoded to an absolute date, a timestamp in milliseconds
 based on the device clock.
 */
@property (nonatomic) uint64_t ttlExpirationLocalTs;

@end
