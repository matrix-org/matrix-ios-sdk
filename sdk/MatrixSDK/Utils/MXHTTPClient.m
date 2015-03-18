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

#pragma mark - Constants definitions
/**
 The max time in milliseconds a request can be retried in the case of rate limiting errors.
 */
#define MXHTTPCLIENT_RATE_LIMIT_MAX_MS 20000

/**
 The base time in milliseconds between 2 retries.
 */
#define MXHTTPCLIENT_RETRY_AFTER_MS 5000

/**
 The jitter value to apply to compute a random retry time.
 */
#define MXHTTPCLIENT_RETRY_JITTER_MS 3000


@interface MXHTTPClient ()
{
    /**
     Use AFNetworking as HTTP client.
     */
    AFHTTPRequestOperationManager *httpManager;

    /**
     If defined, append it to the requested URL.
     */
    NSString *accessToken;

    /**
     The main observer to AFNetworking reachability.
     */
    id reachabilityObserver;

    /**
     The list of blocks managing request retries once network is back
     */
    NSMutableArray *reachabilityObservers;
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

        [self setUpNetworkReachibility];
    }
    return self;
}

- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    return [self requestWithMethod:httpMethod path:path parameters:parameters timeout:-1 success:success failure:failure];
}

- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                timeout:(NSTimeInterval)timeoutInSeconds
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    return [self requestWithMethod:httpMethod path:path parameters:parameters data:nil headers:nil timeout:timeoutInSeconds uploadProgress:nil success:success failure:failure ];
}

- (MXHTTPOperation*)requestWithMethod:(NSString *)httpMethod
                   path:(NSString *)path
             parameters:(NSDictionary*)parameters
                   data:(NSData *)data
                headers:(NSDictionary*)headers
                timeout:(NSTimeInterval)timeoutInSeconds
         uploadProgress:(void (^)(NSUInteger bytesWritten, long long totalBytesWritten, long long totalBytesExpectedToWrite))uploadProgress
                success:(void (^)(NSDictionary *JSONResponse))success
                failure:(void (^)(NSError *error))failure
{
    MXHTTPOperation *mxHTTPOperation = [[MXHTTPOperation alloc] init];

    [self tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:success failure:failure];

    return mxHTTPOperation;
}

- (void)tryRequest:(MXHTTPOperation*)mxHTTPOperation
            method:(NSString *)httpMethod
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
    if (accessToken && (0 == [path rangeOfString:@"access_token="].length))
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

    mxHTTPOperation.numberOfTries++;
    mxHTTPOperation.operation = [httpManager HTTPRequestOperationWithRequest:request success:^(AFHTTPRequestOperation *operation, NSDictionary *JSONResponse) {

        success(JSONResponse);
        
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"[MXHTTPClient] Request %p failed for path: %@ - HTTP code: %ld", mxHTTPOperation, path, (long)operation.response.statusCode);

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
                NSLog(@"[MXHTTPClient] Error JSONResponse: %@", JSONResponse);

                // Extract values from the home server JSON response
                MXError *mxError = [[MXError alloc] initWithErrorCode:JSONResponse[@"errcode"]
                                                                error:JSONResponse[@"error"]];

                if ([mxError.errcode isEqualToString:kMXErrCodeStringLimitExceeded])
                {
                    // Wait and retry if we have not retried too much
                    if (mxHTTPOperation.age < MXHTTPCLIENT_RATE_LIMIT_MAX_MS)
                    {
                        NSString *retryAfterMsString = JSONResponse[@"retry_after_ms"];
                        if (retryAfterMsString)
                        {
                            error = nil;

                            NSLog(@"[MXHTTPClient] Request %p reached rate limiting. Wait for %@ms", mxHTTPOperation, retryAfterMsString);

                            // Wait for the time provided by the server before retrying
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, [retryAfterMsString intValue] * USEC_PER_SEC), dispatch_get_main_queue(), ^{

                                NSLog(@"[MXHTTPClient] Retry rate limited request %p", mxHTTPOperation);

                                [self tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

                                    NSLog(@"[MXHTTPClient] Success of rate limited request %p after %tu tries", mxHTTPOperation, mxHTTPOperation.numberOfTries);

                                    success(JSONResponse);

                                } failure:^(NSError *error) {
                                    failure(error);
                                }];
                            });
                        }
                    }
                    else
                    {
                        NSLog(@"[MXHTTPClient] Giving up rate limited request %p: spent too long retrying.", mxHTTPOperation);
                    }
                }
                else
                {
                    error = [mxError createNSError];
                }
            }
        }
        else if (mxHTTPOperation.numberOfTries < mxHTTPOperation.maxNumberOfTries && mxHTTPOperation.age < mxHTTPOperation.maxRetriesTime)
        {
            // Check if it is a network connectivity issue
            AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
            NSLog(@"[MXHTTPClient] request %p. Network reachability: %d", mxHTTPOperation, networkReachabilityManager.isReachable);

            if (networkReachabilityManager.isReachable)
            {
                // The problem is not the network, do simple retry later
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient jitterTimeForRetry] * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

                    NSLog(@"[MXHTTPClient] Retry request %p. Try #%tu/%tu. Age: %tums. Max retries time: %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries + 1, mxHTTPOperation.maxNumberOfTries, mxHTTPOperation.age, mxHTTPOperation.maxRetriesTime);

                    [self tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

                        NSLog(@"[MXHTTPClient] Request %p finally succeeded after %tu tries and %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries, mxHTTPOperation.age);

                        success(JSONResponse);

                    } failure:^(NSError *error) {
                        failure(error);
                    }];

                });
            }
            else
            {
                __block NSError *lastError = error;

                // The device is not connected to the internet, wait for the connection to be up again before retrying
                __weak __typeof(self)weakSelf = self;
                id networkComeBackObserver = [self addObserverForNetworkComeBack:^{
                    __strong __typeof(weakSelf)strongSelf = weakSelf;

                    NSLog(@"[MXHTTPClient] Network is back for request %p", mxHTTPOperation);

                    // Flag this request as retried
                    lastError = nil;

                    NSLog(@"[MXHTTPClient] Retry request %p. Try #%tu/%tu. Age: %tums. Max retries time: %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries + 1, mxHTTPOperation.maxNumberOfTries, mxHTTPOperation.age, mxHTTPOperation.maxRetriesTime);

                    [strongSelf tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

                        NSLog(@"[MXHTTPClient] Request %p finally succeeded after %tu tries and %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries, mxHTTPOperation.age);

                        success(JSONResponse);

                        // The request is complete, managed the next one
                        [strongSelf wakeUpNextReachabilityServer];

                    } failure:^(NSError *error) {
                        failure(error);

                        // The request is complete, managed the next one
                        [strongSelf wakeUpNextReachabilityServer];
                    }];
                }];

                // Wait for a limit of time. After that the request is considered expired
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (mxHTTPOperation.maxRetriesTime - mxHTTPOperation.age) * USEC_PER_SEC), dispatch_get_main_queue(), ^{
                    __strong __typeof(weakSelf)strongSelf = weakSelf;

                    // If the request has not been retried yet, consider we are in error
                    if (lastError)
                    {
                        NSLog(@"[MXHTTPClient] Give up retry for request %p. Time expired.", mxHTTPOperation);

                        [strongSelf removeObserverForNetworkComeBack:networkComeBackObserver];
                        failure(lastError);
                    }
                });
            }
            error = nil;
        }

        if (error)
        {
            failure(error);
        }
    }];

    // Make the request continue in background
    [mxHTTPOperation.operation setShouldExecuteAsBackgroundTaskWithExpirationHandler:nil];

    if (uploadProgress)
    {
        [mxHTTPOperation.operation setUploadProgressBlock:uploadProgress];
    }

    [httpManager.operationQueue addOperation:mxHTTPOperation.operation];
}

+ (NSUInteger)jitterTimeForRetry
{
    NSUInteger jitter = arc4random_uniform(MXHTTPCLIENT_RETRY_JITTER_MS);
    return  (MXHTTPCLIENT_RETRY_AFTER_MS + jitter);
}


#pragma mark - Private methods
- (void)setUpNetworkReachibility
{
    // Start monitoring reachibility to get its status and change notifications
    [[AFNetworkReachabilityManager sharedManager] startMonitoring];

    reachabilityObservers = [NSMutableArray array];

    AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];

    reachabilityObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingReachabilityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

        if (networkReachabilityManager.isReachable && reachabilityObservers.count)
        {
            // Start retrying request one by one to keep messages order
            NSLog(@"[MXHTTPClient] Network is back. Wake up %tu observers.", reachabilityObservers.count);
            [self wakeUpNextReachabilityServer];
        }
    }];
}

- (void)wakeUpNextReachabilityServer
{
    AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
    if (networkReachabilityManager.isReachable)
    {
        void(^onNetworkComeBackBlock)(void) = [reachabilityObservers firstObject];
        if (onNetworkComeBackBlock)
        {
            [reachabilityObservers removeObject:onNetworkComeBackBlock];
            onNetworkComeBackBlock();
        }
    }
}

- (id)addObserverForNetworkComeBack:(void (^)(void))onNetworkComeBackBlock
{
    id block = [onNetworkComeBackBlock copy];
    [reachabilityObservers addObject:block];

    return block;
}

- (void)removeObserverForNetworkComeBack:(id)observer
{
    [reachabilityObservers removeObject:observer];
}

@end
