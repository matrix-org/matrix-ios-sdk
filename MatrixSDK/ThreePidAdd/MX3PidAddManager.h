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

#import <Foundation/Foundation.h>

#import "MX3PidAddSession.h"

@class MXSession;

NS_ASSUME_NONNULL_BEGIN

/**
 MX3PidAddManager error domain
 */
FOUNDATION_EXPORT NSString *const MX3PidAddManagerErrorDomain;

/**
 MXIdentityServerRestClient errors
 */
NS_ERROR_ENUM(MX3PidAddManagerErrorDomain)
{
    MX3PidAddManagerErrorDomainErrorInvalidParameters,
    MX3PidAddManagerErrorDomainIdentityServerRequired
};



/**
  The `MX3PidAddManager` instance allows a user to add a third party identifier
  to their homeserver and, optionally, the identity servers (bind).

  Diagrams of the intended API flows here are available at:

  https://gist.github.com/jryans/839a09bf0c5a70e2f36ed990d50ed928
 */
@interface MX3PidAddManager : NSObject

- (instancetype)initWithMatrixSession:(MXSession*)session NS_REFINED_FOR_SWIFT;


#pragma mark - Add Email

/**
 Add an email to the user homeserver account.

 The user will receive a validation email.
 Use then `tryFinaliseAddEmailSession` to complete the session.

 @param email the email.
 @param nextLink an optional URL where the user will be redirected to after they
                 click on the validation link within the validation email.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a 3pid add session.
 */
- (MX3PidAddSession*)startAddEmailSessionWithEmail:(NSString*)email
                                          nextLink:(nullable NSString*)nextLink
                                           success:(void (^)(void))success
                                           failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;

/**
 Try to finalise the email addition.

 This must be called after the user has clicked the validation link.

 @param threePidAddSession the session to finalise.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)tryFinaliseAddEmailSession:(MX3PidAddSession*)threePidAddSession
                           success:(void (^)(void))success
                           failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Add MSISDN

/**
 Add a phone number to the user homeserver account.

 The user will receive a code by SMS.
 Use then `finaliseAddPhoneNumberSession` to complete the session.

 @param phoneNumber the phone number.
 @param countryCode the country code. Can be nil if `phoneNumber` is internationalised.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a 3pid add session.
 */
- (MX3PidAddSession*)startAddPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                   countryCode:(nullable NSString*)countryCode
                                                       success:(void (^)(void))success
                                                       failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;

/**
 Finalise the phone number addition.

 @param threePidAddSession the session to finalise.
 @param token the code received by SMS.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)finaliseAddPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                            withToken:(NSString*)token
                              success:(void (^)(void))success
                              failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Bind Email

/**
 Add (bind) an email to the user identity server.

 The user will receive a validation email.
 Use then `tryFinaliseBindEmailSession` to complete the session.

 @param email the email.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a 3pid add session.
 */
- (MX3PidAddSession*)startBindEmailSessionWithEmail:(NSString*)email
                                            success:(void (^)(void))success
                                            failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;

/**
 Try to finalise the email addition to the user identity server.

 This must be called after the user has clicked the validation link.

 @param threePidAddSession the session to finalise.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)tryFinaliseBindEmailSession:(MX3PidAddSession*)threePidAddSession
                            success:(void (^)(void))success
                            failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Bind Phone Number

/**
 Add (bind) a phone number to the user identity server.

 The user will receive a code by SMS.
 Use then `finaliseBindPhoneNumberSession` to complete the session.

 @param phoneNumber the phone number.
 @param countryCode the country code. Can be nil if `phoneNumber` is internationalised.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a 3pid add session.
 */
- (MX3PidAddSession*)startBindPhoneNumberSessionWithPhoneNumber:(NSString*)phoneNumber
                                                    countryCode:(nullable NSString*)countryCode
                                                        success:(void (^)(void))success
                                                        failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;

/**
 Finalise the phone number addition.

 @param threePidAddSession the session to finalise.
 @param token the code received by SMS.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)finaliseBindPhoneNumberSession:(MX3PidAddSession*)threePidAddSession
                             withToken:(NSString*)token
                               success:(void (^)(void))success
                               failure:(void (^)(NSError * _Nonnull))failure NS_REFINED_FOR_SWIFT;

@end

NS_ASSUME_NONNULL_END
