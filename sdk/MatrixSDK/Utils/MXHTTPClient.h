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

/**
 `MXHTTPClient` is an abstraction layer for making HTTP requests to the home server.
*/
@interface MXHTTPClient : NSObject

/**
 Create an intance to make requests to an home server.
 Such created instance can only make requests that do not required to be authenticated.

 @param homeserver the home server URL.
 @return a MXHTTPClient instance.
 */
- (id)initWithHomeServer:(NSString*)homeserver;

/**
 Create an intance to make all kind of requests to an home server.

 @param homeserver the home server URL.
 @param accessToken the access token to authenticate requests.
 @return a MXHTTPClient instance.
 */
- (id)initWithHomeServer:(NSString*)homeserver andAccessToken:(NSString*)accessToken;

/**
 Make a HTTP request to the home server.

 @param httpMethod the HTTP method (GET, PUT, ...)
 @param path the path of the Matrix Client-Server API to call.
 @param parameters the parameters to be set as a query string for `GET` requests, or the request HTTP body.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.
 
 @return a NSOperation instance to use to cancel the request.
 */
- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure;

/**
 Make a HTTP request to the home server with a timeout.

 @param httpMethod the HTTP method (GET, PUT, ...)
 @param path the path of the Matrix Client-Server API to call.
 @param parameters the parameters to be set as a query string for `GET` requests, or the request HTTP body.
 @param timeout the timeout allocated for the request.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.

 @return a NSOperation instance to use to cancel the request.
 */
- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                timeout:(NSTimeInterval)timeoutInSeconds
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure;

/**
 Make a HTTP request to the home server with all possible options.

 @param path the path of the Matrix Client-Server API to call.
 @param parameters (optional) the parameters to be set as a query string for `GET` requests, or the request HTTP body.
 @param data (optional) the data to post.
 @param headers (optional) the HTTP headers to set.
 @param timeout (optional) the timeout allocated for the request.
 
 @param uploadProgress (optional) A block object called when the upload progresses.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.
 
 @return a NSOperation instance to use to cancel the request.
 */
- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                             path:(NSString *)path
                       parameters:(NSDictionary*)parameters
                             data:(NSData *)data
                          headers:(NSDictionary*)headers
                          timeout:(NSTimeInterval)timeoutInSeconds
                   uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress
                          success:(void (^)(NSDictionary *JSONResponse))success
                          failure:(void (^)(NSError *error))failure;

@end
