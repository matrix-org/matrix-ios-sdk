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

#import "MXHTTPClient.h"
#import "MXError.h"

#import <AFNetworking.h>

@interface MXHTTPClient ()
{
    // Use AFNetworking as HTTP client
    AFHTTPRequestOperationManager *httpManager;

    // If defined, append it to the requested URL
    NSString *accessToken;
}
@end

@implementation MXHTTPClient

-(id)initWithBaseURL:(NSString *)baseURL
{
    return [self initWithBaseURL:baseURL andAccessToken:nil];
}

-(id)initWithBaseURL:(NSString *)baseURL andAccessToken:(NSString *)access_token
{
    self = [super init];
    if (self)
    {
        accessToken = access_token;
        
        httpManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:[NSURL URLWithString:baseURL]];
        
        // Send requests parameters in JSON format 
        httpManager.requestSerializer = [AFJSONRequestSerializer serializer];
    }
    return self;
}

- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    return [self requestWithMethod:httpMethod path:path parameters:parameters timeout:-1 success:success failure:failure];
}

- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                timeout:(NSTimeInterval)timeoutInSeconds
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    return [self requestWithMethod:httpMethod path:path parameters:parameters data:nil headers:nil timeout:timeoutInSeconds uploadProgress:nil success:success failure:failure ];
}

- (NSOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                   data:(NSData *)data
                headers:(NSDictionary*)headers
                timeout:(NSTimeInterval)timeoutInSeconds
         uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    // If an access token is set, use it
    if (accessToken)
    {
        path = [path stringByAppendingString:[NSString stringWithFormat:@"?access_token=%@", accessToken]];
    }
    
    NSString *URLString = [[NSURL URLWithString:path relativeToURL:httpManager.baseURL] absoluteString];
    
    NSMutableURLRequest *request;
    request = [httpManager.requestSerializer requestWithMethod:httpMethod URLString:URLString parameters:parameters error:nil];
    if (data)
    {
        NSParameterAssert(![httpMethod isEqualToString:@"GET"] && ![httpMethod isEqualToString:@"HEAD"]);
        request.HTTPBody = data;
        for (NSString *key in headers.allKeys)
        {
            [request setValue:[headers valueForKey:key] forHTTPHeaderField:key];
        }
    }

    // If a timeout is specified, set it
    if (-1 != timeoutInSeconds)
    {
        [request setTimeoutInterval:timeoutInSeconds];
    }
    
    AFHTTPRequestOperation *operation = [httpManager HTTPRequestOperationWithRequest:request
                                                                             success:^(AFHTTPRequestOperation *operation, NSDictionary *JSONResponse) {
                                                                                 success(JSONResponse);
                                                                             }
                                                                             failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                                                 NSLog(@"Request failed for path: %@ - HTTP code: %ld", path, (long)operation.response.statusCode);
                                                                                 
                                                                                 if (operation.responseData)
                                                                                 {
                                                                                     // If the home server (or any other Matrix server) sent data, it contains errcode and error
                                                                                     // Try to send an NSError encapsulating MXError information
                                                                                     NSError *serializationError = nil;
                                                                                     NSDictionary *JSONResponse = [httpManager.responseSerializer responseObjectForResponse:operation.response
                                                                                                                                                                       data:operation.responseData
                                                                                                                                                                      error:&serializationError];
                                                                                     if (JSONResponse)
                                                                                     {
                                                                                         // Extract values from the home server JSON response
                                                                                         error = [[[MXError alloc] initWithErrorCode:JSONResponse[@"errcode"]
                                                                                                                               error:JSONResponse[@"error"]] createNSError];
                                                                                     }
                                                                                 }
                                                                                 failure(error);
                                                                             }];
    
    if (uploadProgress)
    {
        [operation setUploadProgressBlock:uploadProgress];
    }
    
    [httpManager.operationQueue addOperation:operation];
    
    return operation;
}

@end
