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

#import "MXHTTPOperation.h"

/**
 `MXHTTPClient` is an abstraction layer for making requests to a HTTP server.

*/
@interface MXHTTPClient : NSObject

/**
 Create an instance to make requests to the server.

 @param baseURL the server URL from which requests will be done.
 @return a MXHTTPClient instance.
 */
- (id)initWithBaseURL:(NSString*)baseURL;

/**
 Create an intance to make access-token-authenticated requests to the server.
 MXHTTPClient will automatically add the access token to requested URLs

 @param baseURL the server URL from which requests will be done.
 @param accessToken the access token to authenticate requests.
 @return a MXHTTPClient instance.
 */
- (id)initWithBaseURL:(NSString*)baseURL andAccessToken:(NSString*)accessToken;

/**
 Make a HTTP request to the server.

 @param httpMethod the HTTP method (GET, PUT, ...)
 @param path the relative path of the server API to call.
 @param parameters the parameters to be set as a query string for `GET` requests, or the request HTTP body.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure;

/**
 Make a HTTP request to the server with a timeout.

 @param httpMethod the HTTP method (GET, PUT, ...)
 @param path the relative path of the server API to call.
 @param parameters the parameters to be set as a query string for `GET` requests, or the request HTTP body.
 @param timeout the timeout allocated for the request.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                timeout:(NSTimeInterval)timeoutInSeconds
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure;

/**
 Make a HTTP request to the server with all possible options.

 @param path the relative path of the server API to call.
 @param parameters (optional) the parameters to be set as a query string for `GET` requests, or the request HTTP body.
 @param data (optional) the data to post.
 @param headers (optional) the HTTP headers to set.
 @param timeout (optional) the timeout allocated for the request.
 
 @param uploadProgress (optional) A block object called when the upload progresses.

 @param success A block object called when the operation succeeds. It provides the JSON response object from the the server.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                             path:(NSString *)path
                       parameters:(NSDictionary*)parameters
                             data:(NSData *)data
                          headers:(NSDictionary*)headers
                          timeout:(NSTimeInterval)timeoutInSeconds
                   uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress
                          success:(void (^)(NSDictionary *JSONResponse))success
                          failure:(void (^)(NSError *error))failure;

/**
 Return a random time to retry a request.
 
 a jitter is used to prevent all Matrix clients from retrying all in the same time
 if there is server side issue like server restart.
 
 @return a random time in milliseconds between 5s and 8s.
 */
+ (NSUInteger)jitterTimeForRetry;

@end
