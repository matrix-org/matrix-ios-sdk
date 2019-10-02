/*
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import "MX3PidAddManager.h"

#import "MXSession.h"
#import "MXTools.h"

NSString *const MX3PidAddManagerErrorDomain = @"org.matrix.sdk.MX3PidAddManagerErrorDomain";

@interface MX3PidAddManager()
{
    MXSession *mxSession;
}

@end

@implementation MX3PidAddManager

- (instancetype)initWithMatrixSession:(MXSession *)session
{
    self = [super init];
    if (self)
    {
        mxSession = session;
    }
    return self;
}

- (void)cancel3PidAddSession:(MX3PidAddSession*)threePidAddSession
{
    NSLog(@"[MX3PidAddManager] cancel3PidAddSession: threePid: %@", threePidAddSession);

    [threePidAddSession.httpOperation cancel];
    threePidAddSession.httpOperation = nil;
}


#pragma mark - Add Email

- (MX3PidAddSession*)startAddEmailSessionWithEmail:(NSString*)email
                                          nextLink:(nullable NSString*)nextLink
                                           success:(void (^)(void))success
                                           failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumEmail andAddress:email];

    NSLog(@"[MX3PidAddManager] startAddEmailSessionWithEmail: threePid: %@", threePidAddSession);

    threePidAddSession.httpOperation = [self checkIdentityServerRequirementForAdding3PidWithSuccess:^{

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient requestTokenForEmail:email isDuringRegistration:NO clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nextLink success:^(NSString *sid) {

            NSLog(@"[MX3PidAddManager] startAddEmailSessionWithEmail: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }
        
    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)tryFinaliseAddEmailSession:(MX3PidAddSession*)threePidAddSession
                           success:(void (^)(void))success
                           failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseAddEmailSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    threePidAddSession.httpOperation = [mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:NO success:^{
        threePidAddSession.httpOperation = nil;

        NSLog(@"[MX3PidAddManager] tryFinaliseAddEmailSession: DONE: threePid: %@", threePidAddSession);

        success();

    } failure:^(NSError *error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}


#pragma mark - Add MSISDN

- (MX3PidAddSession*)startAddPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                   countryCode:(nullable NSString*)countryCode
                                                       success:(void (^)(void))success
                                                       failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumMSISDN andAddress:phoneNumber];

    NSLog(@"[MX3PidAddManager] startAddPhoneNumberSessionWithPhoneNumber: threePid: %@", threePidAddSession);

    threePidAddSession.httpOperation = [self checkIdentityServerRequirementForAdding3PidWithSuccess:^{

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient requestTokenForPhoneNumber:phoneNumber isDuringRegistration:NO countryCode:countryCode clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid, NSString *msisdn) {

            NSLog(@"[MX3PidAddManager] startAddPhoneNumberSessionWithPhoneNumber: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;

            threePidAddSession.sid = sid;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)finaliseAddPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                            withToken:(NSString*)token
                              success:(void (^)(void))success
                              failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] finaliseAddPhoneNumberSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    MXWeakify(self);
    threePidAddSession.httpOperation = [self submitValidationToken:token for3PidAddSession:threePidAddSession success:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:NO success:^{

            NSLog(@"[MX3PidAddManager] finaliseAddPhoneNumberSession: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError *error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}


#pragma mark - Bind Email

- (MX3PidAddSession*)startBindEmailSessionWithEmail:(NSString*)email
                                            success:(void (^)(void))success
                                            failure:(void (^)(NSError * _Nonnull))failure
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumEmail andAddress:email];

    NSLog(@"[MX3PidAddManager] startBindEmailSessionWithEmail: threePid: %@", threePidAddSession);

    if (!mxSession.identityService)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                         userInfo:nil];
        failure(error);
        return threePidAddSession;
    }

    threePidAddSession.httpOperation = [self doesServerSupportSeparateAddAndBind:^(bool doesServerSupportSeparateAddAndBind) {

        MXHTTPOperation *operation;
//        if (doesServerSupportSeparateAddAndBind)
//        {
//            // TODO
//        }
//        else
        {
            operation = [self startBind3PidSessionWithOldHomeserver:threePidAddSession success:^{
                threePidAddSession.httpOperation = nil;
                success();
            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];
        }

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)tryFinaliseBindEmailSession:(MX3PidAddSession*)threePidAddSession
                            success:(void (^)(void))success
                            failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] tryFinaliseBindEmailSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    // TODO: this is for !doesServerSupportSeparateAddAndBind
    threePidAddSession.httpOperation = [mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:YES success:^{
        threePidAddSession.httpOperation = nil;

        NSLog(@"[MX3PidAddManager] tryFinaliseBindEmailSession: DONE: threePid: %@", threePidAddSession);

        success();

    } failure:^(NSError *error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}


#pragma mark - Bind Phone Number

- (MX3PidAddSession*)startBindPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                    countryCode:(nullable NSString*)countryCode
                                                        success:(void (^)(void))success
                                                        failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT
{
    MX3PidAddSession *threePidAddSession = [[MX3PidAddSession alloc] initWithMedium:kMX3PIDMediumMSISDN andAddress:phoneNumber];

    NSLog(@"[MX3PidAddManager] startBindPhoneNumberSessionWithPhoneNumber: threePid: %@", threePidAddSession);

    if (!mxSession.identityService)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                         userInfo:nil];
        failure(error);
        return threePidAddSession;
    }

    threePidAddSession.httpOperation = [self doesServerSupportSeparateAddAndBind:^(bool doesServerSupportSeparateAddAndBind) {

        MXHTTPOperation *operation;
        //        if (doesServerSupportSeparateAddAndBind)
        //        {
        //            // TODO
        //        }
        //        else
        {
            operation = [self startBind3PidSessionWithOldHomeserver:threePidAddSession success:^{
                threePidAddSession.httpOperation = nil;
                success();
            } failure:^(NSError *error) {
                threePidAddSession.httpOperation = nil;
                failure(error);
            }];
        }

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError * _Nonnull error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];

    return threePidAddSession;
}

- (void)finaliseBindPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                             withToken:(NSString*)token
                               success:(void (^)(void))success
                               failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT
{
    NSLog(@"[MX3PidAddManager] finaliseBindPhoneNumberSession: threePid: %@", threePidAddSession);

    NSParameterAssert([threePidAddSession.medium isEqualToString:kMX3PIDMediumMSISDN]);

    if (threePidAddSession.httpOperation || !threePidAddSession.sid)
    {
        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainErrorInvalidParameters
                                         userInfo:nil];
        failure(error);
        return;
    }

    // TODO: this is for !doesServerSupportSeparateAddAndBind
    MXWeakify(self);
    threePidAddSession.httpOperation = [self submitValidationToken:token for3PidAddSession:threePidAddSession success:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation = [self->mxSession.matrixRestClient add3PID:threePidAddSession.sid clientSecret:threePidAddSession.clientSecret bind:YES success:^{

            NSLog(@"[MX3PidAddManager] finaliseBindPhoneNumberSession: DONE: threePid: %@", threePidAddSession);

            threePidAddSession.httpOperation = nil;
            success();

        } failure:^(NSError *error) {
            threePidAddSession.httpOperation = nil;
            failure(error);
        }];

        if (operation)
        {
            [threePidAddSession.httpOperation mutateTo:operation];
        }

    } failure:^(NSError *error) {
        threePidAddSession.httpOperation = nil;
        failure(error);
    }];
}

#pragma mark - Private methods -

- (MXHTTPOperation *)checkIdentityServerRequirementForAdding3PidWithSuccess:(void (^)(void))success
                                                       failure:(void (^)(NSError * _Nonnull))failure
{
    MXWeakify(self);
    return [mxSession.matrixRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {
        MXStrongifyAndReturnIfNil(self);

        NSLog(@"[MX3PidAddManager] checkIdentityServerRequirement: %@", matrixVersions.doesServerRequireIdentityServerParam ? @"YES": @"NO");

        if (matrixVersions.doesServerRequireIdentityServerParam
            && !self->mxSession.matrixRestClient.identityServer)
        {
            NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                                 code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                             userInfo:nil];
            failure(error);
        }
        else
        {
            success();
        }

    } failure:failure];
}

- (MXHTTPOperation *)doesServerSupportSeparateAddAndBind:(void (^)(bool doesServerSupportSeparateAddAndBind))success
                                                                    failure:(void (^)(NSError * _Nonnull))failure
{
    return [mxSession.matrixRestClient supportedMatrixVersions:^(MXMatrixVersions *matrixVersions) {

        NSLog(@"[MX3PidAddManager] doesServerSupportSeparateAddAndBind: %@", matrixVersions.doesServerSupportSeparateAddAndBind ? @"YES": @"NO");
        success(matrixVersions.doesServerSupportSeparateAddAndBind);

    } failure:failure];
}

- (nullable MXHTTPOperation *)submitValidationToken:(NSString *)token
            for3PidAddSession:(MX3PidAddSession*)threePidAddSession
                      success:(void (^)(void))success
                      failure:(void (^)(NSError * _Nonnull))failure
{
    MXHTTPOperation *operation;
    if (mxSession.identityService)
    {
        operation = [mxSession.identityService submit3PIDValidationToken:token
                                                                  medium:threePidAddSession.medium
                                                            clientSecret:threePidAddSession.clientSecret
                                                                     sid:threePidAddSession.sid
                                                                 success:success
                                                                 failure:failure];
    }
    else
    {
        NSLog(@"[MX3PidAddManager] submitValidationToken: ERROR: Failed to submit validation token for 3PID: %@, identity service is not set", threePidAddSession);

        NSError *error = [NSError errorWithDomain:MX3PidAddManagerErrorDomain
                                             code:MX3PidAddManagerErrorDomainIdentityServerRequired
                                         userInfo:nil];
        failure(error);
    }

    return operation;
}


#pragma mark - Bind to Identity Server

- (MXHTTPOperation *)startBind3PidSessionWithOldHomeserver:(MX3PidAddSession*)threePidAddSession
                                                   success:(void (^)(void))success
                                                   failure:(void (^)(NSError * _Nonnull))failure
{
    NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@", threePidAddSession);

    MXWeakify(self);
    MXHTTPOperation *operation;
    operation = [mxSession.matrixRestClient remove3PID:threePidAddSession.address medium:threePidAddSession.medium success:^{
        MXStrongifyAndReturnIfNil(self);

        MXHTTPOperation *operation2;
        if ([threePidAddSession.medium isEqualToString:kMX3PIDMediumEmail])
        {
            operation2 = [self->mxSession.matrixRestClient requestTokenForEmail:threePidAddSession.address isDuringRegistration:NO clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid) {

                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.sid = sid;
                success();

            } failure:^(NSError *error) {
                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
                failure(error);
            }];
        }
        else
        {
            operation2 = [self->mxSession.matrixRestClient requestTokenForPhoneNumber:threePidAddSession.address isDuringRegistration:NO countryCode:nil clientSecret:threePidAddSession.clientSecret sendAttempt:threePidAddSession.sendAttempt++ nextLink:nil success:^(NSString *sid, NSString *msisdn) {

                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: DONE: threePid: %@", threePidAddSession);

                threePidAddSession.sid = sid;
                success();

            } failure:^(NSError *error) {
                NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: requestTokenForEmail failed: %@", threePidAddSession, error);
                failure(error);
            }];
        }


        if (operation2)
        {
            [operation mutateTo:operation2];
        }


    } failure:^(NSError *error) {

        NSLog(@"[MX3PidAddManager] startBind3PidSessionWithOldHomeserver: threePid: %@. ERROR: remove3PID failed: %@", threePidAddSession, error);
        failure(error);
    }];

    return operation;
}

@end
