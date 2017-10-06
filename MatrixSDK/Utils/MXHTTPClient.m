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

#import "MXHTTPClient.h"
#import "MXError.h"
#import "MXSDKOptions.h"
#import "MXBackgroundModeHandler.h"

#import <AFNetworking/AFNetworking.h>

#pragma mark - Constants definitions
/**
 The max time in milliseconds a request can be retried in the case of rate limiting errors.
 */
#define MXHTTPCLIENT_RATE_LIMIT_MAX_MS 20000

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
    AFHTTPSessionManager *httpManager;

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

    /**
     The current background task id if any.
     */
    NSUInteger backgroundTaskIdentifier;

    /**
     Flag to indicate that the underlying NSURLSession has been invalidated.
     In this state, we can not use anymore NSURLSession else it crashes.
     */
    BOOL invalidatedSession;
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

        httpManager = [[AFHTTPSessionManager alloc] initWithBaseURL:[NSURL URLWithString:baseURL]];

        [self setDefaultSecurityPolicy];

        onUnrecognizedCertificateBlock = onUnrecognizedCertBlock;

        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        if (handler)
        {
            backgroundTaskIdentifier = [handler invalidIdentifier];
        }

        // No need for caching. The sdk caches the data it needs
        [httpManager.requestSerializer setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];

        // Send requests parameters in JSON format by default
        self.requestParametersInJSON = YES;

        [self setUpNetworkReachibility];
        [self setUpSSLCertificatesHandler];

        // Track potential expected session invalidation (seen on iOS10 beta)
        __weak typeof(self) weakSelf = self;
        [httpManager setSessionDidBecomeInvalidBlock:^(NSURLSession * _Nonnull session, NSError * _Nonnull error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf)
            {
                NSLog(@"[MXHTTPClient] SessionDidBecomeInvalid: %@: %@", session, error);
                strongSelf->invalidatedSession = YES;
            }
        }];
    }
    return self;
}

- (void)dealloc
{
    [self cancel];
    [self cleanupBackgroundTask];
    
    [[NSNotificationCenter defaultCenter] removeObserver:reachabilityObserver];
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
         uploadProgress:(void (^)(NSProgress *uploadProgress))uploadProgress
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
    uploadProgress:(void (^)(NSProgress *uploadProgress))uploadProgress
           success:(void (^)(NSDictionary *JSONResponse))success
           failure:(void (^)(NSError *error))failure
{
    // Sanity check
    if (invalidatedSession)
    {
        // This 
    	NSLog(@"[MXHTTPClient] tryRequest: ignore the request as the NSURLSession has been invalidated");
        return;
    }

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

    __weak typeof(self) weakSelf = self;

    mxHTTPOperation.numberOfTries++;
    mxHTTPOperation.operation = [httpManager dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull theUploadProgress) {

        __strong __typeof(weakSelf)strongSelf = weakSelf;
        if (strongSelf && uploadProgress)
        {
            // theUploadProgress is called from an AFNetworking thread. So, switch to the UI one
            dispatch_async(dispatch_get_main_queue(), ^{
                uploadProgress(theUploadProgress);
            });
        }
        
    } downloadProgress:nil completionHandler:^(NSURLResponse * _Nonnull theResponse, NSDictionary *JSONResponse, NSError * _Nullable error) {

        __strong __typeof(weakSelf)strongSelf = weakSelf;
        if (strongSelf)
        {
            mxHTTPOperation.operation = nil;

            if (!error)
            {
                success(JSONResponse);
            }
            else
            {
                NSHTTPURLResponse *response = (NSHTTPURLResponse*)theResponse;

#if DEBUG
                NSLog(@"[MXHTTPClient] Request %p failed for path: %@ - HTTP code: %@", mxHTTPOperation, path, response ? @(response.statusCode) : @"none");
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
                NSLog(@"[MXHTTPClient] Request %p failed for path: %@ - HTTP code: %@", mxHTTPOperation, printedPath, @(response.statusCode));

                if (error.userInfo[NSLocalizedDescriptionKey])
                {
                    NSLog(@"[MXHTTPClient] error domain: %@, code:%zd, description: %@", error.domain, error.code, error.userInfo[NSLocalizedDescriptionKey]);
                }
                else
                {
                    NSLog(@"[MXHTTPClient] error domain: %@, code:%zd", error.domain, error.code);
                }
#endif

                if (response)
                {
                    // If the home server (or any other Matrix server) sent data, it may contain 'errcode' and 'error'.
                    // In this case, we return an NSError which encapsulates MXError information.
                    // When neither 'errcode' nor 'error' are present, the received data are reported in NSError userInfo thanks to 'MXHTTPClientErrorResponseDataKey' key.
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

                                            [strongSelf tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

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
                else if (mxHTTPOperation.numberOfTries < mxHTTPOperation.maxNumberOfTries
                         && mxHTTPOperation.age < mxHTTPOperation.maxRetriesTime
                         && !([error.domain isEqualToString:NSURLErrorDomain] && error.code == kCFURLErrorCancelled)    // No need to retry a cancelation (which can also happen on SSL error)
                         && response.statusCode != 400 && response.statusCode != 401 && response.statusCode != 403      // No amount of retrying will save you now
                         )
                {
                    // Check if it is a network connectivity issue
                    AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
                    NSLog(@"[MXHTTPClient] request %p. Network reachability: %d", mxHTTPOperation, networkReachabilityManager.isReachable);

                    if (networkReachabilityManager.isReachable)
                    {
                        // The problem is not the network, do simple retry later
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, [MXHTTPClient timeForRetry:mxHTTPOperation] * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{

                            NSLog(@"[MXHTTPClient] Retry request %p. Try #%tu/%tu. Age: %tums. Max retries time: %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries + 1, mxHTTPOperation.maxNumberOfTries, mxHTTPOperation.age, mxHTTPOperation.maxRetriesTime);

                            [strongSelf tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

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
                        __weak __typeof(self)weakSelf2 = strongSelf;
                        id networkComeBackObserver = [strongSelf addObserverForNetworkComeBack:^{

                            __strong __typeof(weakSelf2)strongSelf2 = weakSelf2;
                            if (strongSelf2)
                            {
                                NSLog(@"[MXHTTPClient] Network is back for request %p", mxHTTPOperation);

                                // Flag this request as retried
                                lastError = nil;

                                // Check whether the pending operation was not cancelled.
                                if (mxHTTPOperation.maxNumberOfTries)
                                {
                                    NSLog(@"[MXHTTPClient] Retry request %p. Try #%tu/%tu. Age: %tums. Max retries time: %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries + 1, mxHTTPOperation.maxNumberOfTries, mxHTTPOperation.age, mxHTTPOperation.maxRetriesTime);

                                    [strongSelf2 tryRequest:mxHTTPOperation method:httpMethod path:path parameters:parameters data:data headers:headers timeout:timeoutInSeconds uploadProgress:uploadProgress success:^(NSDictionary *JSONResponse) {

                                        NSLog(@"[MXHTTPClient] Request %p finally succeeded after %tu tries and %tums", mxHTTPOperation, mxHTTPOperation.numberOfTries, mxHTTPOperation.age);

                                        success(JSONResponse);

                                        // The request is complete, managed the next one
                                        [strongSelf2 wakeUpNextReachabilityServer];

                                    } failure:^(NSError *error) {
                                        failure(error);

                                        // The request is complete, managed the next one
                                        [strongSelf2 wakeUpNextReachabilityServer];
                                    }];
                                }
                                else
                                {
                                    NSLog(@"[MXHTTPClient] The request %p has been cancelled", mxHTTPOperation);
                                    
                                    // The request is complete, managed the next one
                                    [strongSelf2 wakeUpNextReachabilityServer];
                                }
                            }
                        }];

                        // Wait for a limit of time. After that the request is considered expired
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (mxHTTPOperation.maxRetriesTime - mxHTTPOperation.age) * USEC_PER_SEC), dispatch_get_main_queue(), ^{

                            __strong __typeof(weakSelf2)strongSelf2 = weakSelf2;
                            if (strongSelf2)
                            {
                                // If the request has not been retried yet, consider we are in error
                                if (lastError)
                                {
                                    NSLog(@"[MXHTTPClient] Give up retry for request %p. Time expired.", mxHTTPOperation);

                                    [strongSelf2 removeObserverForNetworkComeBack:networkComeBackObserver];
                                    failure(lastError);
                                }
                            }
                        });
                    }
                    error = nil;
                }
            }
            
            if (error)
            {
                failure(error);
            }
            
            // Delay the call of 'cleanupBackgroundTask' in order to let httpManager.tasks.count
            // decrease.
            // Note that if one of the callbacks of 'tryRequest' makes a new request, the bg
            // task will persist until the end of this new request.
            // The basic use case is the sending of a media which consists in two requests:
            //     - the upload of the media
            //     - then, the sending of the message event associated to this media
            // When backgrounding the app while sending the media, the user expects that the two
            // requests complete.
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupBackgroundTask];
            });
        }
    }];

    // Make request continues when app goes in background
    [self startBackgroundTask];

    [mxHTTPOperation.operation resume];
}

+ (NSUInteger)timeForRetry:(MXHTTPOperation *)httpOperation
{
    NSUInteger jitter = arc4random_uniform(MXHTTPCLIENT_RETRY_JITTER_MS);

    NSUInteger retry = (2 << (httpOperation.numberOfTries - 1)) * 1000 + jitter;
    return retry;
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


#pragma - Background task
/**
 Engage a background task.
 
 The bg task will be ended by the call of 'cleanupBackgroundTask' when the request completes.
 The goal of these methods is to mimic the behavior of 'setShouldExecuteAsBackgroundTaskWithExpirationHandler'
 in AFNetworking < 3.0.
 */
- (void)startBackgroundTask
{
    @synchronized(self)
    {
        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        if (handler && backgroundTaskIdentifier == [handler invalidIdentifier])
        {
            __weak __typeof(self)weakSelf = self;
            backgroundTaskIdentifier = [handler startBackgroundTaskWithName:nil completion:^{

                NSLog(@"[MXHTTPClient] Background task #%tu is going to expire - Try to end it",
                      backgroundTaskIdentifier);

                __strong __typeof(weakSelf)strongSelf = weakSelf;
                if (strongSelf)
                {
                    // Cancel all the tasks currently run by the managed session
                    NSArray *tasks = httpManager.tasks;
                    for (NSURLSessionTask *sessionTask in tasks)
                    {
                        [sessionTask cancel];
                    }

                    [strongSelf cleanupBackgroundTask];
                }
            }];

            NSLog(@"[MXHTTPClient] Background task #%tu started", backgroundTaskIdentifier);
        }
    }
}


/**
 End the background task.

 The tast will be stopped only if there is no more http request in progress.
 */
- (void)cleanupBackgroundTask
{
    NSLog(@"[MXHTTPClient] cleanupBackgroundTask");

    @synchronized(self)
    {
        id<MXBackgroundModeHandler> handler = [MXSDKOptions sharedInstance].backgroundModeHandler;
        if (handler && backgroundTaskIdentifier != [handler invalidIdentifier] && httpManager.tasks.count == 0)
        {
            NSLog(@"[MXHTTPClient] Background task #%tu is complete",
                  backgroundTaskIdentifier);

            [handler endBackgrounTaskWithIdentifier:backgroundTaskIdentifier];
            backgroundTaskIdentifier = [handler invalidIdentifier];
        }
    }
}

- (void)setPinnedCertificates:(NSSet<NSData *> *)pinnedCertificates
{
    _pinnedCertificates = pinnedCertificates;
    if (!pinnedCertificates.count)
    {
        [self setDefaultSecurityPolicy];
        return;
    }
    AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
    securityPolicy.pinnedCertificates = pinnedCertificates;
    httpManager.securityPolicy = securityPolicy;
}


#pragma mark - Private methods
- (void)cancel
{
    NSLog(@"[MXHTTPClient] cancel");
    [httpManager invalidateSessionCancelingTasks:YES];
}

- (void)setUpNetworkReachibility
{
    AFNetworkReachabilityManager *networkReachabilityManager = [AFNetworkReachabilityManager sharedManager];
    
    // Start monitoring reachibility to get its status and change notifications
    [networkReachabilityManager startMonitoring];

    reachabilityObservers = [NSMutableArray array];
    
    __weak typeof(self) weakSelf = self;
    reachabilityObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AFNetworkingReachabilityDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {

        if (weakSelf)
        {
            __strong typeof(weakSelf) self = weakSelf;

            if (networkReachabilityManager.isReachable && self->reachabilityObservers.count)
            {
                // Start retrying request one by one to keep messages order
                NSLog(@"[MXHTTPClient] Network is back. Wake up %tu observers.", self->reachabilityObservers.count);
                [self wakeUpNextReachabilityServer];
            }
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

- (void)setUpSSLCertificatesHandler
{
    __weak __typeof(self)weakSelf = self;

    // Handle SSL certificates
    [httpManager setSessionDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(NSURLSession * _Nonnull session, NSURLAuthenticationChallenge * _Nonnull challenge, NSURLCredential *__autoreleasing  _Nullable * _Nullable credential) {

        __strong __typeof(weakSelf)strongSelf = weakSelf;

        if (strongSelf)
        {
            NSURLProtectionSpace *protectionSpace = [challenge protectionSpace];

            if ([protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
            {
                if ([strongSelf->httpManager.securityPolicy evaluateServerTrust:protectionSpace.serverTrust forDomain:protectionSpace.host])
                {
                    *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
                    return NSURLSessionAuthChallengeUseCredential;
                }
                else
                {
                    NSLog(@"[MXHTTPClient] Shall we trust %@?", protectionSpace.host);

                    if (strongSelf->onUnrecognizedCertificateBlock)
                    {
                        SecTrustRef trust = [protectionSpace serverTrust];

                        if (SecTrustGetCertificateCount(trust) > 0)
                        {
                            // Consider here the leaf certificate (the one at index 0).
                            SecCertificateRef certif = SecTrustGetCertificateAtIndex(trust, 0);

                            NSData *certifData = (__bridge NSData*)SecCertificateCopyData(certif);
                            if (strongSelf->onUnrecognizedCertificateBlock(certifData))
                            {
                                NSLog(@"[MXHTTPClient] Yes, the user trusts its certificate");
                                
                                strongSelf->_allowedCertificate = certifData;
                                
                                // Update http manager security policy with this trusted certificate.
                                AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
                                securityPolicy.pinnedCertificates = [NSSet setWithObjects:certifData, nil];
                                securityPolicy.allowInvalidCertificates = YES;
                                // Disable the domain validation for this certificate trusted by the user.
                                securityPolicy.validatesDomainName = NO;
                                strongSelf->httpManager.securityPolicy = securityPolicy;

                                // Evaluate again server security
                                if ([strongSelf->httpManager.securityPolicy evaluateServerTrust:protectionSpace.serverTrust forDomain:protectionSpace.host])
                                {
                                    *credential = [NSURLCredential credentialForTrust:protectionSpace.serverTrust];
                                    return NSURLSessionAuthChallengeUseCredential;
                                }

                                // Here pin certificate failed
                                NSLog(@"[MXHTTPClient] Failed to pin certificate for %@", protectionSpace.host);
                                return NSURLSessionAuthChallengePerformDefaultHandling;
                            }
                        }
                    }
                    
                    // Here we don't trust the certificate
                    NSLog(@"[MXHTTPClient] No, the user doesn't trust it");
                    return NSURLSessionAuthChallengeCancelAuthenticationChallenge;
                }
            }
        }

        return NSURLSessionAuthChallengePerformDefaultHandling;
    }];
}

- (void)setDefaultSecurityPolicy
{
    // If some certificates are included in app bundle, we enable the AFNetworking pinning mode based on certificate 'AFSSLPinningModeCertificate'.
    // These certificates will be handled as pinned certificates, the app allows them without prompting the user.
    // This is an additional option for the developer to handle certificates.
    AFSecurityPolicy *securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
    if (securityPolicy.pinnedCertificates.count)
    {
        securityPolicy.allowInvalidCertificates = YES;
        httpManager.securityPolicy = securityPolicy;
    }
}

@end
