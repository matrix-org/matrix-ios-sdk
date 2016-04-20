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

#import <AFNetworking/AFNetworking.h>

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

/**
 `MXHTTPClientErrorResponseDataKey`
 The corresponding value is an `NSDictionary` containing the response data of the operation associated with an error.
 */
NSString * const MXHTTPClientErrorResponseDataKey = @"com.matrixsdk.httpclient.error.response.data";

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

    /**
     Unrecognized Certificate handler
     */
    MXHTTPClientOnUnrecognizedCertificate onUnrecognizedCertificateBlock;
}
@end

@implementation MXHTTPClient


#pragma mark - Public methods
-(id)initWithBaseURL:(NSString *)baseURL andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    return [self initWithBaseURL:baseURL accessToken:nil andOnUnrecognizedCertificateBlock:onUnrecognizedCertBlock];
}

-(id)initWithBaseURL:(NSString *)baseURL accessToken:(NSString *)access_token andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
{
    self = [super init];
    if (self)
    {
        accessToken = access_token;
        
        httpManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:[NSURL URLWithString:baseURL]];
        
        // If some certificates are included in app bundle, we enable the AFNetworking pinning mode based on certificate 'AFSSLPinningModeCertificate'.
        // These certificates will be handled as pinned certificates, the app allows them without prompting the user.
        // This is an additional option for the developer to handle certificates.
        AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
        if (securityPolicy.pinnedCertificates.count)
        {
            securityPolicy.allowInvalidCertificates = YES;
            securityPolicy.validatesDomainName = YES; // Enable the domain validation on pinned certificates retrieved from app bundle.
            httpManager.securityPolicy = securityPolicy;
        }
        
        onUnrecognizedCertificateBlock = onUnrecognizedCertBlock;
        
        // Send requests parameters in JSON format by default
        self.requestParametersInJSON = YES;

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
        // Use '&' if there is already an url separator
        NSString *urlSeparator = [path rangeOfString:@"?"].length ? @"&" : @"?";
        path = [path stringByAppendingString:[NSString stringWithFormat:@"%@access_token=%@", urlSeparator, accessToken]];
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
        mxHTTPOperation.operation = nil;
        success(JSONResponse);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {

        mxHTTPOperation.operation = nil;

#if DEBUG
        NSLog(@"[MXHTTPClient] Request %p failed for path: %@ - HTTP code: %ld", mxHTTPOperation, path, (long)operation.response.statusCode);
        NSLog(@"[MXHTTPClient] error: %@", error);
#else
        // Hide access token in printed path
        NSMutableString *printedPath = [NSMutableString stringWithString:path];
        if (accessToken)
        {
            NSRange range = [path rangeOfString:accessToken];
            if (range.location != NSNotFound)
            {
                [printedPath replaceCharactersInRange:range withString:@"..."];
            }
        }
        NSLog(@"[MXHTTPClient] Request %p failed for path: %@ - HTTP code: %ld", mxHTTPOperation, printedPath, (long)operation.response.statusCode);
        
        if (error.userInfo[NSLocalizedDescriptionKey])
        {
            NSLog(@"[MXHTTPClient] error domain: %@, code:%zd, description: %@", error.domain, error.code, error.userInfo[NSLocalizedDescriptionKey]);
        }
        else
        {
            NSLog(@"[MXHTTPClient] error domain: %@, code:%zd", error.domain, error.code);
        }
#endif

        if (operation.responseData)
        {
            // If the home server (or any other Matrix server) sent data, it may contain 'errcode' and 'error'.
            // In this case, we return an NSError which encapsulates MXError information.
            // When neither 'errcode' nor 'error' are present the received data are reported in NSError userInfo thanks to 'MXHTTPClientErrorResponseDataKey' key.
            NSError *serializationError = nil;
            NSDictionary *JSONResponse = [httpManager.responseSerializer responseObjectForResponse:operation.response
                                                                                              data:operation.responseData
                                                                                             error:&serializationError];
            
            if (JSONResponse)
            {
                NSLog(@"[MXHTTPClient] Error JSONResponse: %@", JSONResponse);
                
                if (JSONResponse[@"errcode"] || JSONResponse[@"error"])
                {
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
                else
                {
                    // Report the received data in userInfo dictionary
                    NSMutableDictionary *userInfo;
                    if (error.userInfo)
                    {
                        userInfo = [NSMutableDictionary dictionaryWithDictionary:error.userInfo];
                    }
                    else
                    {
                        userInfo = [NSMutableDictionary dictionary];
                    }
                    
                    [userInfo setObject:JSONResponse forKey:MXHTTPClientErrorResponseDataKey];
                    
                    error = [NSError errorWithDomain:error.domain code:error.code userInfo:userInfo];
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
                    
                    // Check whether the pending operation was not cancelled.
                    if (mxHTTPOperation.maxNumberOfTries)
                    {
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
                    }
                    else
                    {
                        NSLog(@"[MXHTTPClient] The request %p has been cancelled", mxHTTPOperation);
                        
                        // The request is complete, managed the next one
                        [strongSelf wakeUpNextReachabilityServer];
                    }
                    
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
    
    // Handle SSL certificates
    [mxHTTPOperation.operation setWillSendRequestForAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
        
        NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];
        
        if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
        {
            if ([httpManager.securityPolicy evaluateServerTrust:protectionSpace.serverTrust forDomain:protectionSpace.host])
            {
                NSURLCredential *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
            }
            else
            {
                NSLog(@"[MXHTTPClient] Shall we trust %@?", protectionSpace.host);
                
                if (onUnrecognizedCertificateBlock)
                {
                    SecTrustRef trust = [protectionSpace serverTrust];
                    
                    if (SecTrustGetCertificateCount(trust) > 0)
                    {
                        // Consider here the leaf certificate (the one at index 0).
                        SecCertificateRef certif = SecTrustGetCertificateAtIndex(trust, 0);
                        
                        NSData *certifData = (__bridge NSData*)SecCertificateCopyData(certif);
                        if (onUnrecognizedCertificateBlock(certifData))
                        {
                            NSLog(@"[MXHTTPClient] Yes, the user trusts its certificate");
                            
                            _allowedCertificate = certifData;
                            
                            // Update http manager security policy with this trusted certificate.
                            AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
                            securityPolicy.pinnedCertificates = @[certifData];
                            securityPolicy.allowInvalidCertificates = YES;
                            // Disable the domain validation for this certificate trusted by the user.
                            securityPolicy.validatesDomainName = NO;
                            httpManager.securityPolicy = securityPolicy;
                            
                            // Evaluate again server security
                            if ([httpManager.securityPolicy evaluateServerTrust:protectionSpace.serverTrust forDomain:protectionSpace.host])
                            {
                                NSURLCredential *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
                                [[challenge sender] useCredential:credential forAuthenticationChallenge:challenge];
                                return;
                            }
                            
                            // Here pin certificate failed
                            NSLog(@"[MXHTTPClient] Failed to pin certificate for %@", protectionSpace.host);
                            [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
                            return;
                        }
                    }
                }
                
                // Here we don't trust the certificate
                NSLog(@"[MXHTTPClient] No, the user doesn't trust it");
                [[challenge sender] cancelAuthenticationChallenge:challenge];
            }
        }
        else
        {
            if ([challenge previousFailureCount] == 0)
            {
                if (httpManager.credential)
                {
                    [[challenge sender] useCredential:httpManager.credential forAuthenticationChallenge:challenge];
                }
                else
                {
                    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
                }
            }
            else
            {
                [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
            }
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


#pragma mark - Configuration
- (void)setRequestParametersInJSON:(BOOL)requestParametersInJSON
{
    _requestParametersInJSON = requestParametersInJSON;
    if (_requestParametersInJSON)
    {
        httpManager.requestSerializer = [AFJSONRequestSerializer serializer];
    }
    else
    {
        httpManager.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
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
