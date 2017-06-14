/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd

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
 `MXHTTPClientErrorResponseDataKey`
 The corresponding value is an `NSDictionary` containing the response data of the operation associated with an error.
 */
extern NSString * const MXHTTPClientErrorResponseDataKey;

/**
 Block called when an authentication challenge from a server failed whereas a certificate is present in certificate chain.
 
 @param certificate the server certificate to evaluate.
 @return YES to accept/trust this certificate, NO to cancel/ignore it.
 */
typedef BOOL (^MXHTTPClientOnUnrecognizedCertificate)(NSData *certificate);

/**
 `MXHTTPClient` is an abstraction layer for making requests to a HTTP server.

*/
@interface MXHTTPClient : NSObject


#pragma mark - Configuration
/**
 `requestParametersInJSON` indicates if parameters passed in [self requestWithMethod:..] methods
 must be serialised in JSON.
 Else, they will be send in form data.
 Default is YES.
 */
@property (nonatomic) BOOL requestParametersInJSON;

/**
 The current trusted certificate (if any).
 */
@property (nonatomic, readonly) NSData* allowedCertificate;


#pragma mark - Public methods
/**
 Create an instance to make requests to the server.

 @param baseURL the server URL from which requests will be done.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @return a MXHTTPClient instance.
 */
- (id)initWithBaseURL:(NSString*)baseURL andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock;

/**
 Create an intance to make access-token-authenticated requests to the server.
 MXHTTPClient will automatically add the access token to requested URLs

 @param baseURL the server URL from which requests will be done.
 @param accessToken the access token to authenticate requests.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @return a MXHTTPClient instance.
 */
- (id)initWithBaseURL:(NSString*)baseURL accessToken:(NSString*)accessToken andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock;

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
 @param timeoutInSeconds the timeout allocated for the request.

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
 @param timeoutInSeconds (optional) the timeout allocated for the request.
 
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
                   uploadProgress:(void (^)(NSProgress *uploadProgress))uploadProgress
                          success:(void (^)(NSDictionary *JSONResponse))success
                          failure:(void (^)(NSError *error))failure;

/**
 Return the amount of time to wait before retrying a request.
 
 The time is based on an exponential backoff plus a jitter in order to prevent all Matrix clients 
 from retrying all in the same time if there is server side issue like server restart.
 
 @return a time in milliseconds like [2000, 4000, 8000, 16000, ...] + a jitter of 3000ms.
 */
+ (NSUInteger)timeForRetry:(MXHTTPOperation*)httpOperation;

/**
 The certificates used to evaluate server trust according to the SSL pinning mode.
 */
@property (nonatomic, strong) NSSet <NSData *> *pinnedCertificates;

@end
