/*
 Copyright 2019 New Vector Ltd

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

@class MXLoginResponse;

NS_ASSUME_NONNULL_BEGIN

/**
 The `MXCredentials` class contains credentials to communicate with the  Matrix
 Client-Server API.
 */
@interface MXCredentials : NSObject

/**
 The homeserver url (ex: "https://matrix.org").
 */
@property (nonatomic) NSString *homeServer;

/**
 The obtained user id.
 */
@property (nonatomic) NSString *userId;

/**
 The access token to create a MXRestClient
 */
@property (nonatomic) NSString *accessToken;

/**
 The device id.
 */
@property (nonatomic) NSString *deviceId;

/**
 The homeserver name (ex: "matrix.org").
 */
- (NSString *)homeServerName;

/**
 The server certificate trusted by the user (nil when the server is trusted by the device).
 */
@property (nonatomic) NSData *allowedCertificate;

/**
 The ignored server certificate (set when the user ignores a certificate change).
 */
@property (nonatomic) NSData *ignoredCertificate;


/**
 Simple MXCredentials construtor

 @param homeServer the homeserver URL.
 @param userId the user id.
 @param accessToken the user access token.
 @return a MXCredentials instance.
 */
- (instancetype)initWithHomeServer:(NSString*)homeServer
                            userId:(NSString*)userId
                       accessToken:(NSString*)accessToken;

/**
 Create credentials from a login or register response.

 @param loginResponse the login or register response.
 @param homeServer the homeserver URL to use if we cannot trust loginResponse data
 @return a MXCredentials instance.
 */
- (instancetype)initWithLoginResponse:(MXLoginResponse*)loginResponse
                withDefaultHomeServer:(NSString*)homeServer;

@end

NS_ASSUME_NONNULL_END
