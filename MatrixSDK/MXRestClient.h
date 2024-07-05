/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
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

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif

#import "MXHTTPClient.h"
#import "MXEvent.h"
#import "MXError.h"
#import "MXRoomEventFilter.h"
#import "MXInvite3PID.h"
#import "MXJSONModels.h"
#import "MXFilterJSONModel.h"
#import "MXMatrixVersions.h"
#import "MXContentScanResult.h"
#import "MXEncryptedContentFile.h"
#import "MXContentScanEncryptedBody.h"
#import "MXAggregationPaginatedResponse.h"
#import "MXPusher.h"
#import "MXRoomCreationParameters.h"
#import "MXTurnServerResponse.h"
#import "MXSpaceChildrenResponse.h"
#import "MXURLPreview.h"
#import "MXTaggedEvents.h"
#import "MXCredentials.h"
#import "MXRoomAliasResolution.h"

@class MXThirdpartyProtocolsResponse;
@class MXThirdPartyUsersResponse;
@class MXSyncResponse;
@class MXDeviceListResponse;
@class MXSpaceChildrenRequestParameters;
@class MXCapabilities;
@class MXDevice;
@class MXToDevicePayload;

MX_ASSUME_MISSING_NULLABILITY_BEGIN

#pragma mark - Constants definitions
/**
 A constant representing the URI path for release 0 of the Client-Server HTTP API.
 */
FOUNDATION_EXPORT NSString *const kMXAPIPrefixPathR0;

/**
 A constant representing the URI path for as-yet unspecified of the Client-Server HTTP API.
 */
FOUNDATION_EXPORT NSString *const kMXAPIPrefixPathUnstable;


/**
 Account data types
 */
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeDirect;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypePushRules;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeIgnoredUserList;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeUserWidgets;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeIdentityServer;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeAcceptedTerms;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeBreadcrumbs;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeAcceptedTermsKey;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeClientInformation;

/**
 Account data keys
 */
FOUNDATION_EXPORT NSString *const kMXAccountDataKeyIgnoredUser;
FOUNDATION_EXPORT NSString *const kMXAccountDataKeyIdentityServer;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeRecentRoomsKey;
FOUNDATION_EXPORT NSString *const kMXAccountDataLocalNotificationKeyPrefix;
FOUNDATION_EXPORT NSString *const kMXAccountDataIsSilencedKey;

/**
 Threads list request parameters
 */
FOUNDATION_EXPORT NSString *const kMXThreadsListIncludeAllParameter;
FOUNDATION_EXPORT NSString *const kMXThreadsListIncludeParticipatedParameter;

/**
 MXRestClient error domain
 */
FOUNDATION_EXPORT NSString *const kMXRestClientErrorDomain;

/**
 MXRestClient errors
 */

NS_ERROR_ENUM(kMXRestClientErrorDomain)
{
    MXRestClientErrorUnknown,
    MXRestClientErrorInvalidParameters,
    MXRestClientErrorInvalidContentURI,
    MXRestClientErrorMissingIdentityServer,
    MXRestClientErrorMissingIdentityServerAccessToken
};

/**
 Parameters that can be used in [MXRestClient membersOfRoom:withParameters:...].
 */
FOUNDATION_EXPORT NSString *const kMXMembersOfRoomParametersAt;
FOUNDATION_EXPORT NSString *const kMXMembersOfRoomParametersMembership;
FOUNDATION_EXPORT NSString *const kMXMembersOfRoomParametersNotMembership;


/**
 Block called when a request needs the identity server access token.

 @param success A block object called when the operation succeeds. It provides the access token.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
typedef MXHTTPOperation* (^MXRestClientIdentityServerAccessTokenHandler)(void (^success)(NSString *accessToken), void (^failure)(NSError *error));

/**
 Block called when the rest client has become unauthenticated(E.g. refresh failed or server invalidated an access token).

 @param error The error from the failed refresh.
 */
typedef void(^MXRestClientUnauthenticatedHandler)(MXError *error, BOOL isSoftLogout, BOOL isRefreshTokenAuth, void (^completion)(void));

/**
 Block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new refresh data to disk if it is not.
 @param handler A closure that accepts the current persisted credentials. These can optionally be updated and saved back initWithCredentials returning YES from the closure.
 */
typedef void (^MXRestClientPersistTokenDataHandler)(void (^handler)(NSArray <MXCredentials*> *credentials, void (^shouldPersistCompletion)(BOOL didUpdateCredentials)));

/**
 `MXRestClient` makes requests to Matrix servers.

 It is the single point to send requests to Matrix servers which are:
    - the specified Matrix home server
    - the Matrix content repository manage by this home server
    - the specified Matrix identity server
 */
@interface MXRestClient : NSObject

/**
 Notification name sent when the refresh/access tokens should be updated in the credential. userInfo contains 'kMXCredentialsNewRefreshTokenDataKey'.
 */
extern NSString *const MXCredentialsUpdateTokensNotification;

/**
 A key for getting the refresh response from `MXCredentialsWillUpdateTokensNotification` userInfo.
 */
extern NSString *const kMXCredentialsNewRefreshTokenDataKey;

/**
 Credentials for the Matrix Client-Server API.
 */
@property (nonatomic, readonly) MXCredentials *credentials;

/**
 Block called when the rest client failed to refresh it's tokens and session is now unauthenticated.
 */
@property (nonatomic, copy) MXRestClientUnauthenticatedHandler unauthenticatedHandler;

/**
 Block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new data to disk if it is not.
 */
@property (nonatomic, copy) MXRestClientPersistTokenDataHandler persistTokenDataHandler;

/**
 The homeserver URL.
 Shortcut to credentials.homeServer.
 */
@property (nonatomic, readonly) NSString *homeserver;

/**
 The homeserver suffix (for example ":matrix.org"). Available only when credentials have been set.
 */
@property (nonatomic, readonly) NSString *homeserverSuffix;

/**
 The identity server URL (ex: "https://vector.im").
 
 TODO: Remove it when all HSes will no more require IS.
 */
@property (nonatomic, copy) NSString *identityServer;

/**
 Block called when a request needs the identity server access token.
 */
@property (nonatomic, copy) MXRestClientIdentityServerAccessTokenHandler identityServerAccessTokenHandler;

/**
 The antivirus server URL (nil by default).
 Set a non-null url to enable the antivirus scanner use.
 */
@property (nonatomic) NSString *antivirusServer;

/**
 The Client-Server API prefix to use for the antivirus server
 By default, it is defined by the constant kMXAntivirusAPIPrefixPathUnstable.
 In case of a custom path prefix use, set it before settings the antivirus server url.
 */
@property (nonatomic) NSString *antivirusServerPathPrefix;

/**
 The Client-Server API prefix to use.
 By default, it is '_matrix/client/r0'. See kMXAPIPrefixPathR0 and kMXAPIPrefixPathUnstable for constants.
 */
@property (nonatomic) NSString *apiPathPrefix;

/**
 The Matrix content repository prefix to use.
 By default, it is defined by the constant kMXContentPrefixPath.
 */
@property (nonatomic) NSString *contentPathPrefix;

/**
 The Matrix content repository prefix to use for authenticated access.
 By default, it is defined by the constant kMXAuthenticatedContentPrefixPath.
 */
@property (nonatomic) NSString *authenticatedContentPathPrefix;

/**
 The current trusted certificate (if any).
 */
@property (nonatomic, readonly) NSData* allowedCertificate;

/**
 The queue on which asynchronous response blocks are called.
 Default is dispatch_get_main_queue().
 */
@property (nonatomic, strong) dispatch_queue_t completionQueue;

/**
 The acceptable MIME types for responses.
 */
@property (nonatomic, copy) NSSet <NSString *> *acceptableContentTypes;

/**
 Supported server versions of the matrix server, only for internal use of the SDK, use the stored version on the app side.
 */
@property (readonly) BOOL isUsingAuthenticatedMedia;

/**
 Create an instance based on homeserver url.

 @param homeserver the homeserver URL.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @return a MXRestClient instance.
 */
-(id)initWithHomeServer:(NSString *)homeserver andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock NS_REFINED_FOR_SWIFT;

/**
 Create an instance based on a matrix user account.

 @param credentials the response to a login or a register request.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @return a MXRestClient instance.
 */

-(id)initWithCredentials:(MXCredentials*)credentials
andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
NS_REFINED_FOR_SWIFT;

/**
 Create an instance based on a matrix user account.

 @param credentials the response to a login or a register request.
 @param onUnrecognizedCertBlock the block called to handle unrecognized certificate (nil if unrecognized certificates are ignored).
 @param persistentTokenDataHandler the block called when the rest client needs to check the persisted refresh token data is valid and optionally persist new refresh data to disk if it is not.
 @param unauthenticatedHandler the block called when the rest client has become unauthenticated(E.g. refresh failed or server invalidated an access token).
 @return a MXRestClient instance.
 */

-(id)initWithCredentials:(MXCredentials*)credentials
andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock
andPersistentTokenDataHandler: (MXRestClientPersistTokenDataHandler)persistentTokenDataHandler
andUnauthenticatedHandler: (MXRestClientUnauthenticatedHandler)unauthenticatedHandler
NS_REFINED_FOR_SWIFT;

- (void)close;


#pragma mark - Server administration
/**
 Gets the versions of the specification supported by the server.

 @param success A block object called when the operation succeeds. It provides
                the supported spec versions.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)supportedMatrixVersions:(void (^)(MXMatrixVersions *matrixVersions))success
                                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the wellknwon data of the homeserver.

 @param success A block object called when the operation succeeds. It provides
                the wellknown data.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)wellKnow:(void (^)(MXWellKnown *wellKnown))success
                     failure:(void (^)(NSError *error))failure;

/**
 Get the capabilities of the homeserver.

 @param success A block object called when the operation succeeds. It provides
                the capabilities.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)capabilities:(void (^)(MXCapabilities *capabilities))success
                         failure:(void (^)(NSError *error))failure;

#pragma mark - Registration operations
/**
 Make a ping to the registration endpoint to detect a possible registration problem earlier.

 @param username the user name to test (This value must not be nil).
 @param callback A block object called when the operation is completed.
                 It provides a MXError to check to verify if the user can be registered.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)testUserRegistration:(NSString*)username
                                callback:(void (^)(MXError *mxError))callback;

/**
 Check whether a username is already in use.

 @param username the user name to test (This value must not be nil).
 @param callback A block object called when the operation is completed.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)isUserNameInUse:(NSString*)username
                           callback:(void (^)(BOOL isUserNameInUse))callback NS_REFINED_FOR_SWIFT __deprecated_msg("Use isUsernameAvailable instead.");

/**
 Checks whether a username is available.

 @param username the user name to test (This value must not be nil).
 @param success A block object called when the operation succeeds. It provides the server response
 as an MXUsernameAvailability instance.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)isUsernameAvailable:(NSString*)username
                                success:(void (^)(MXUsernameAvailability *availability))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;
/**
 Get the list of register flows supported by the home server.

 @param success A block object called when the operation succeeds. It provides the server response
 as an MXAuthenticationSession instance.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getRegisterSession:(void (^)(MXAuthenticationSession *authSession))success
                               failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Generic registration action request.

 As described in http://matrix.org/docs/spec/client_server/r0.2.0.html#client-authentication some registration flows require to
 complete several stages in order to complete user registration.
 This can lead to make several requests to the home server with different kinds of parameters.
 This generic method with open parameters and response exists to handle any kind of registration flow stage.

 At the end of the registration process, the SDK user should be able to construct a MXCredentials object
 from the response of the last registration action request.
 
 @note The caller may provide the device display name by adding @"initial_device_display_name" key
 in the `parameters` dictionary. If the caller does not provide it, the device display name field
 is filled with the device name.

 @param parameters the parameters required for the current registration stage
 @param success A block object called when the operation succeeds. It provides the raw JSON response
 from the server.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)registerWithParameters:(NSDictionary*)parameters
                                   success:(void (^)(NSDictionary *JSONResponse))success
                                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Register a user.
 
 This method manages the full flow for simple login types and returns the credentials of the newly created matrix user.

 @param loginType the login type. Only kMXLoginFlowTypePassword and kMXLoginFlowTypeDummy (m.login.password and m.login.dummy) are supported.
 @param username the user id (ex: "@bob:matrix.org") or the user id localpart (ex: "bob") of the user to register. Can be nil.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)registerWithLoginType:(NSString*)loginType username:(NSString*)username password:(NSString*)password
                                  success:(void (^)(MXCredentials *credentials))success
                                  failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the register fallback page to make registration via a web browser or a web view.

 @return the fallback page URL.
 */
- (NSString*)registerFallback NS_REFINED_FOR_SWIFT;

/**
 Reset the password server side
 
 Check that the given email address is associated with any account
 and then request the validation of an email address.
 
 Check MXMatrixVersion.doesServerRequireIdentityServerParam to determine if
 the homeserver requires the id_server parameter to be provided.
 
 @param email the email address to validate.
 @param clientSecret a secret key generated by the client. ([MXTools generateSecret] creates such key)
 @param sendAttempt the number of the attempt for the validation request. Increment this value to make the
 identity server resend the email. Keep it to retry the request in case the previous request
 failed.
 
 @param success A block object called when the operation succeeds. It provides the id of the
 forget password session.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)forgetPasswordForEmail:(NSString *)email
                              clientSecret:(NSString *)clientSecret
                               sendAttempt:(NSUInteger)sendAttempt
                                   success:(void (^)(NSString *sid))success
                                   failure:(void (^)(NSError *error))failure;

#pragma mark - Login operations
/**
 Get the list of login flows supported by the home server.

 @param success A block object called when the operation succeeds. It provides the server response
 as an MXAuthenticationSession instance.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getLoginSession:(void (^)(MXAuthenticationSession *authSession))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Generic login action request.

 @see the register method for explanation of flows that require to make several request to the
 home server.
 
 @note The caller may provide the device display name by adding @"initial_device_display_name" key
 in the `parameters` dictionary. If the caller does not provide it, the device display name field
 is filled with the device name.
 
 @param parameters the parameters required for the current login stage
 @param success A block object called when the operation succeeds. It provides the raw JSON response
 from the server.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)login:(NSDictionary*)parameters
                  success:(void (^)(NSDictionary *JSONResponse))success
                  failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Log a user in.

 This method manages the full flow for simple login types and returns the credentials of the logged matrix user.
 
 @note The device display name field is filled with the device name by default.

 @param loginType the login type. Only kMXLoginFlowTypePassword (m.login.password) is supported.
 @param username the user id (ex: "@bob:matrix.org") or the user id localpart (ex: "bob") of the user to register.
 @param password his password.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)loginWithLoginType:(NSString*)loginType username:(NSString*)username password:(NSString*)password
                               success:(void (^)(MXCredentials *credentials))success
                               failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the login fallback page to make login via a web browser or a web view.

 Presently only server auth v1 is supported.

 @return the fallback page URL.
 */
- (NSString*)loginFallback NS_REFINED_FOR_SWIFT;

/**
 Generates a new login token
 @param success A block object called when the operation succeeds. It provides the raw JSON response
 from the server.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)generateLoginTokenWithSuccess:(void (^)(MXLoginToken *loginToken))success
                                          failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Reset the account password.

 @param parameters a set of parameters containing a threepid credentials and the new password.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)resetPasswordWithParameters:(NSDictionary*)parameters
                                        success:(void (^)(void))success
                                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Replace the account password.

 @param oldPassword the current password to update.
 @param newPassword the new password.
 @param logoutDevices flag to logout from all devices.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)changePassword:(NSString*)oldPassword
                              with:(NSString*)newPassword
                     logoutDevices:(BOOL)logoutDevices
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Invalidate the access token, so that it can no longer be used for authorization.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)logout:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


/**
 Deactivate the user's account, removing all ability for the user to login again.
 
 @discussion This API endpoint uses the User-Interactive Authentication API.
 
 @note An access token should be submitted to this endpoint if the client has an active session.
 The homeserver may change the flows available depending on whether a valid access token is provided.
 
 @param authParameters The additional authentication information for the user-interactive authentication API.
 @param eraseAccount Indicating whether the account should be erased.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deactivateAccountWithAuthParameters:(NSDictionary*)authParameters
                                           eraseAccount:(BOOL)eraseAccount
                                                success:(void (^)(void))success
                                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Authenticated session
/**
 Get an authentication session for a given request.

 @param httpMethod The HTTP method for the request.
 @param path The request path.
 @param parameters Request parameters.
 
 @param success A block object called when the operation succeeds. It provides the server response
                as an MXAuthenticationSession instance.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)authSessionForRequestWithMethod:(NSString *)httpMethod
                                               path:(NSString *)path
                                         parameters:(NSDictionary*)parameters
                                            success:(void (^)(MXAuthenticationSession *authSession))success
                                            failure:(void (^)(NSError *error))failure;


#pragma mark - Account data
/**
 Set some account_data for the client.

 @param data the new data to set for this event type.
 @param type The event type of the account_data to set (@see kMXAccountDataType* strings)
 Custom types should be namespaced to avoid clashes.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setAccountData:(NSDictionary*)data
                           forType:(NSString*)type
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Delete an account_data event for the client.

 @param type The event type of the account_data to delete (@see kMXAccountDataType* strings)
 Custom types should be namespaced to avoid clashes.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteAccountDataWithType:(NSString*)type
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure;

#pragma mark - Filtering
/**
 Uploads a new filter definition to the homeserver.

 @param filter the filter to set.

 @param success A block object called when the operation succeeds. It provides the
                id of the created filter.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setFilter:(MXFilterJSONModel*)filter
                      success:(void (^)(NSString *filterId))success
                      failure:(void (^)(NSError *error))failure;

/**
 Download a filter.

 @param filterId The filter id to download.

 @param success A block object called when the operation succeeds. It provides the
                filter object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getFilterWithFilterId:(NSString*)filterId
                                  success:(void (^)(MXFilterJSONModel *filter))success
                                  failure:(void (^)(NSError *error))failure;


/**
 Gets a bearer token from the homeserver that the user can
 present to a third party in order to prove their ownership
 of the Matrix account they are logged into.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)openIdToken:(void (^)(MXOpenIdToken *tokenObject))success
                        failure:(void (^)(NSError *error))failure;


#pragma mark - 3pid token request
/**
 Requests an email verification token for the purposes of adding a
 third party identifier to an account.

 Check MXMatrixVersion.doesServerRequireIdentityServerParam to determine if
 the homeserver requires the id_server parameter to be provided.

 If an account with the given email address already exists and is
 associated with an account other than the one the user is authed as,
 it will either send an email to the address informing them of this
 or return M_THREEPID_IN_USE (which one is up to the homeserver).
 
 Use the returned sid to complete operations that require authenticated email
 like [MXRestClient add3PID:].
 
 @param email the email address to validate.
 @param isDuringRegistration  tell whether this request occurs during a registration flow.
 @param clientSecret a secret key generated by the client. ([MXTools generateSecret] creates such key)
 @param sendAttempt the number of the attempt for the validation request. Increment this value to make the
 identity server resend the email. Keep it to retry the request in case the previous request
 failed.
 @param nextLink the link the validation page will automatically open. Can be nil
 
 @param success A block object called when the operation succeeds. It provides the id of the
 email validation session.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestTokenForEmail:(NSString*)email
                    isDuringRegistration:(BOOL)isDuringRegistration
                            clientSecret:(NSString*)clientSecret
                             sendAttempt:(NSUInteger)sendAttempt
                                nextLink:(NSString*)nextLink
                                 success:(void (^)(NSString *sid))success
                                 failure:(void (^)(NSError *error))failure;

/**
 Requests a text message verification token for the purposes of registration.

 Check MXMatrixVersion.doesServerRequireIdentityServerParam to determine if
 the homeserver requires the id_server parameter to be provided.
 
 Use the returned sid to complete operations that require authenticated phone number
 like [MXRestClient add3PID:].
 
 @param phoneNumber the phone number (in international or national format).
 @param isDuringRegistration  tell whether this request occurs during a registration flow.
 @param countryCode the ISO 3166-1 country code representation (required when the phone number is in national format).
 @param clientSecret a secret key generated by the client. ([MXTools generateSecret] creates such key)
 @param sendAttempt the number of the attempt for the validation request. Increment this value to make the
 identity server resend the sms token. Keep it to retry the request in case the previous request
 failed.
 @param nextLink the link the validation page will automatically open. Can be nil
 
 @param success A block object called when the operation succeeds. It provides the id of the validation session and the msisdn.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)requestTokenForPhoneNumber:(NSString*)phoneNumber
                          isDuringRegistration:(BOOL)isDuringRegistration
                                   countryCode:(NSString*)countryCode
                                  clientSecret:(NSString*)clientSecret
                                   sendAttempt:(NSUInteger)sendAttempt
                                      nextLink:(NSString *)nextLink
                                       success:(void (^)(NSString *sid, NSString *msisdn, NSString *submitUrl))success
                                       failure:(void (^)(NSError *error))failure;

#pragma mark - Push Notifications
/**
 Update the pusher for this device on the Home Server.

 @param pushkey The pushkey for this pusher. This should be the APNS token formatted as required for your push gateway (base64 is the recommended formatting).
 @param kind The kind of pusher your push gateway requires. Generally 'http', or an NSNull to disable the pusher.
 @param appId The app ID of this application as required by your push gateway.
 @param appDisplayName A human readable display name for this app.
 @param deviceDisplayName A human readable display name for this device.
 @param profileTag The profile tag for this device. Identifies this device in push rules.
 @param lang The user's preferred language for push, eg. 'en' or 'en-US'
 @param data Dictionary of data as required by your push gateway (generally the notification URI and aps-environment for APNS).
 @param append If true, the homeserver should add another pusher with the given pushkey and App ID in addition to any others with different user IDs.
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPusherWithPushkey:(NSString *)pushkey
                                    kind:(NSObject *)kind
                                   appId:(NSString *)appId
                          appDisplayName:(NSString *)appDisplayName
                       deviceDisplayName:(NSString *)deviceDisplayName
                              profileTag:(NSString *)profileTag
                                    lang:(NSString *)lang
                                    data:(NSDictionary *)data
                                  append:(BOOL)append
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Update the pusher for this device on the Home Server.

 @param pushkey The pushkey for this pusher. This should be the APNS token formatted as required for your push gateway (base64 is the recommended formatting).
 @param kind The kind of pusher your push gateway requires. Generally 'http', or an NSNull to disable the pusher.
 @param appId The app ID of this application as required by your push gateway.
 @param appDisplayName A human readable display name for this app.
 @param deviceDisplayName A human readable display name for this device.
 @param profileTag The profile tag for this device. Identifies this device in push rules.
 @param lang The user's preferred language for push, eg. 'en' or 'en-US'
 @param data Dictionary of data as required by your push gateway (generally the notification URI and aps-environment for APNS).
 @param append If true, the homeserver should add another pusher with the given pushkey and App ID in addition to any others with different user IDs.
 @param enabled Whether the pusher should actively create push notifications
 @param success A block object called when the operation succeeds. It provides credentials to use to create a MXRestClient.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPusherWithPushkey:(NSString *)pushkey
                                    kind:(NSObject *)kind
                                   appId:(NSString *)appId
                          appDisplayName:(NSString *)appDisplayName
                       deviceDisplayName:(NSString *)deviceDisplayName
                              profileTag:(NSString *)profileTag
                                    lang:(NSString *)lang
                                    data:(NSDictionary *)data
                                  append:(BOOL)append
                                 enabled:(BOOL)enabled
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *))failure NS_REFINED_FOR_SWIFT;

/**
 Gets all currently active pushers for the authenticated user.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)pushers:(void (^)(NSArray<MXPusher *> *pushers))success
                    failure:(void (^)(NSError *))failure NS_REFINED_FOR_SWIFT;

/**
 Get all push notifications rules.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)pushRules:(void (^)(MXPushRulesResponse *pushRules))success
                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Enable/Disable a push notification rule.

 @param ruleId The identifier for the rule.
 @param scope Either 'global' or 'device/<profile_tag>' to specify global rules or device rules for the given profile_tag.
 @param kind The kind of rule, ie. 'override', 'underride', 'sender', 'room', 'content' (see MXPushRuleKind).
 @param enable YES to enable
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation *)enablePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                             enable:(BOOL)enable
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Remove a push notification rule.

 @param ruleId The identifier for the rule.
 @param scope Either 'global' or 'device/<profile_tag>' to specify global rules or device rules for the given profile_tag.
 @param kind The kind of rule, ie. 'override', 'underride', 'sender', 'room', 'content' (see MXPushRuleKind).
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation *)removePushRule:(NSString*)ruleId
                              scope:(NSString*)scope
                               kind:(MXPushRuleKind)kind
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Create a new push rule.

 @param ruleId The identifier for the rule (it depends on rule kind: user id for sender rule, room id for room rule...).
 @param scope Either 'global' or 'device/<profile_tag>' to specify global rules or device rules for the given profile_tag.
 @param kind The kind of rule, ie. 'sender', 'room' or 'content' (see MXPushRuleKind).
 @param actions The rule actions: notify, don't notify, set tweak...
 @param pattern The pattern relevant for content rule.
 @param conditions The conditions relevant for override and underride rule.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation *)addPushRule:(NSString*)ruleId
                           scope:(NSString*)scope
                            kind:(MXPushRuleKind)kind
                         actions:(NSArray*)actions
                         pattern:(NSString*)pattern
                      conditions:(NSArray<NSDictionary *> *)conditions
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Update push rule actions.

 @param ruleId The identifier for the rule (it depends on rule kind: user id for sender rule, room id for room rule...).
 @param scope Either 'global' or 'device/<profile_tag>' to specify global rules or device rules for the given profile_tag.
 @param kind The kind of rule, ie. 'sender', 'room' or 'content' (see MXPushRuleKind).
 @param actions The rule actions: notify, don't notify, set tweak...
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation *)updateActionsForPushRule:(NSString*)ruleId
                                        scope:(NSString*)scope
                                         kind:(MXPushRuleKind)kind
                                      actions:(NSArray*)actions
                                      success:(void (^)(void))success
                                      failure:(void (^)(NSError *error))failure;
#pragma mark - Room operations
/**
 Send a generic non state event to a room.

 @param roomId the id of the room.
 @param threadId the identifier of the thread for the event to be sent. If nil, the event will be sent to the room.
 @param eventTypeString the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param txnId the transaction id to use. If nil, one will be generated.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendEventToRoom:(NSString*)roomId
                           threadId:(NSString*)threadId
                          eventType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                              txnId:(NSString*)txnId
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a generic state event to a room.

 @param roomId the id of the room.
 @param eventTypeString the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param stateKey the optional state key.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendStateEventToRoom:(NSString*)roomId
                               eventType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                stateKey:(NSString*)stateKey
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a message to a room

 @param roomId the id of the room.
 @param threadId the identifier of the thread for the event to be sent. If nil, the event will be sent to the room.
 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendMessageToRoom:(NSString*)roomId
                             threadId:(NSString*)threadId
                              msgType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a text message to a room

 @param roomId the id of the room.
 @param threadId the identifier of the thread for the event to be sent. If nil, the event will be sent to the room.
 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTextMessageToRoom:(NSString*)roomId
                                 threadId:(NSString*)threadId
                                     text:(NSString*)text
                                  success:(void (^)(NSString *eventId))success
                                  failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


/**
 Set the topic of a room.

 @param roomId the id of the room.
 @param topic the topic to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomTopic:(NSString*)roomId
                           topic:(NSString*)topic
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the topic of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room topic.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)topicOfRoom:(NSString*)roomId
                        success:(void (^)(NSString *topic))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


/**
 Set the avatar of a room.

 @param roomId the id of the room.
 @param avatar the avatar url to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomAvatar:(NSString*)roomId
                           avatar:(NSString*)avatar
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the avatar of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room avatar url.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)avatarOfRoom:(NSString*)roomId
                         success:(void (^)(NSString *avatar))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the name of a room.

 @param roomId the id of the room.
 @param name the name to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomName:(NSString*)roomId
                           name:(NSString*)name
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the name of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room name.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)nameOfRoom:(NSString*)roomId
                       success:(void (^)(NSString *name))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the history visibility of a room.

 @param roomId the id of the room.
 @param historyVisibility the visibily to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomHistoryVisibility:(NSString*)roomId
                           historyVisibility:(MXRoomHistoryVisibility)historyVisibility
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the history visibility of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room history visibility.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)historyVisibilityOfRoom:(NSString*)roomId
                                    success:(void (^)(MXRoomHistoryVisibility historyVisibility))success
                                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the join rule of a room.

 @deprecated join rules have been enhanced to support `restricted` rule. You should now call [setRoomJoinRule:forRoomWithId:allowedParentIds:success:failure:].

 @param roomId the id of the room.
 @param joinRule the rule to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomJoinRule:(NSString*)roomId
                           joinRule:(MXRoomJoinRule)joinRule
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure __deprecated_msg("Use [setRoomJoinRule:forRoomWithId:allowedParentIds:success:failure:] instead");

/**
 Set the join rule of a room.

 @param joinRule the rule to set.
 @param roomId the id of the room.
 @param allowedParentIds Optional: list of allowedParentIds (required only for `restricted` join rule as per [MSC3083](https://github.com/matrix-org/matrix-doc/pull/3083) )
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomJoinRule:(MXRoomJoinRule)joinRule
                      forRoomWithId:(NSString*)roomId
                   allowedParentIds:(NSArray<NSString *> *)allowedParentIds
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the join rule of a room.
 
 @deprecated join rules have been enhanced to support `restricted` rule. You should now call [joinRuleOfRoomWithId:success:failure:].

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room join rule.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRuleOfRoom:(NSString*)roomId
                           success:(void (^)(MXRoomJoinRule joinRule))success
                           failure:(void (^)(NSError *error))failure __deprecated_msg("Use [joinRuleOfRoomWithId:success:failure:] instead");

/**
 Get the enhanced join rule of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room enhanced join rule as per [MSC3083](https://github.com/matrix-org/matrix-doc/pull/3083.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRuleOfRoomWithId:(NSString*)roomId
                                 success:(void (^)(MXRoomJoinRuleResponse *joinRule))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the guest access of a room.

 @param roomId the id of the room.
 @param guestAccess the guest access to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomGuestAccess:(NSString*)roomId
                           guestAccess:(MXRoomGuestAccess)guestAccess
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the guest access of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room guest access.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)guestAccessOfRoom:(NSString*)roomId
                              success:(void (^)(MXRoomGuestAccess guestAccess))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the directory visibility of a room on the current homeserver.

 @param roomId the id of the room.
 @param directoryVisibility the directory visibility to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomDirectoryVisibility:(NSString*)roomId
                           directoryVisibility:(MXRoomDirectoryVisibility)directoryVisibility
                                       success:(void (^)(void))success
                                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the visibility of a room in the current HS's room directory.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room directory visibility.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)directoryVisibilityOfRoom:(NSString*)roomId
                                      success:(void (^)(MXRoomDirectoryVisibility directoryVisibility))success
                                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Create a new mapping from room alias to room ID.
 
 @param roomId the id of the room.
 @param roomAlias the alias to add.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)addRoomAlias:(NSString*)roomId
                           alias:(NSString*)roomAlias
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Remove a mapping of room alias to room ID.
 
 @param roomAlias the alias to remove.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)removeRoomAlias:(NSString*)roomAlias
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the canonical alias of the room.
 
 @param roomId the id of the room.
 @param canonicalAlias the canonical alias to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomCanonicalAlias:(NSString*)roomId
                           canonicalAlias:(NSString *)canonicalAlias
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the canonical alias.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the canonical alias.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)canonicalAliasOfRoom:(NSString*)roomId
                          success:(void (^)(NSString *canonicalAlias))success
                          failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Join a room.

 @param roomIdOrAlias the id or an alias of the room to join.
 @param viaServers The server names to try and join through in addition to those
                   that are automatically chosen. Can be nil.
 @param thirdPartySigned the signed data obtained by the validation of an 3PID invitation.
                         The valisation is made by [self signUrl]. Can be nil.
 @param success A block object called when the operation succeeds. It provides the room id.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                  viaServers:(NSArray<NSString*>*)viaServers
        withThirdPartySigned:(NSDictionary*)thirdPartySigned
                     success:(void (^)(NSString *theRoomId))success
                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Leave a room.

 @param roomId the id of the room to leave.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)leaveRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Invite a user to a room.

 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteUser:(NSString*)userId
                        toRoom:(NSString*)roomId
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Invite a user to a room based on their email address.

 @param email the user email.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteUserByEmail:(NSString*)email
                               toRoom:(NSString*)roomId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Invite a user to a room based on a third-party identifier.

 @param medium the medium to invite the user e.g. "email".
 @param address the address for the specified medium.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)inviteByThreePid:(NSString*)medium
                             address:(NSString*)address
                              toRoom:(NSString*)roomId
                             success:(void (^)(void))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Kick a user from a room.

 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)kickUser:(NSString*)userId
                    fromRoom:(NSString*)roomId
                      reason:(NSString*)reason
                     success:(void (^)(void))success
                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Ban a user in a room.

 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)banUser:(NSString*)userId
                     inRoom:(NSString*)roomId
                     reason:(NSString*)reason
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Unban a user in a room.

 @param userId the user id.
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)unbanUser:(NSString*)userId
                       inRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Create a room.
 
 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room in the current HS's room directory.
 @param roomAlias (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.
 
 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                       success:(void (^)(MXCreateRoomResponse *response))success
                       failure:(void (^)(NSError *error))failure NS_SWIFT_UNAVAILABLE("TEST");

/**
 Create a room.

 @param parameters the parameters.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoomWithParameters:(MXRoomCreationParameters*)parameters
                                     success:(void (^)(MXCreateRoomResponse *response))success
                                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Create a room.

 @param parameters the parameters. Refer to the matrix specification for details.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoom:(NSDictionary*)parameters
                       success:(void (^)(MXCreateRoomResponse *response))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get a list of messages for this room.

 @param roomId the id of the room.
 @param from the token to start getting results from.
 @param direction `MXTimelineDirectionForwards` or `MXTimelineDirectionBackwards`
 @param limit (optional, use -1 to not defined this value) the maximum number of messages to return.
 @param roomEventFilter the filter to pass in the request. Can be nil.

 @param success A block object called when the operation succeeds. It provides a `MXPaginationResponse` object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)messagesForRoom:(NSString*)roomId
                               from:(NSString*)from
                          direction:(MXTimelineDirection)direction
                              limit:(NSInteger)limit
                             filter:(MXRoomEventFilter*)roomEventFilter
                            success:(void (^)(MXPaginationResponse *paginatedResponse))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get a list of members for this room.

 @param roomId the id of the room.

 @param success A block object called when the operation succeeds. It provides an array of `MXEvent`
 objects  which type is m.room.member.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)membersOfRoom:(NSString*)roomId
                          success:(void (^)(NSArray *roomMemberEvents))success
                          failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get a list of members for this room.

 @param roomId the id of the room.
 @param parameters additional parameters for the request. Check kMXMembersOfRoomParameters*.

 @param success A block object called when the operation succeeds. It provides an array of `MXEvent`
 objects  which type is m.room.member.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)membersOfRoom:(NSString*)roomId
                   withParameters:(NSDictionary*)parameters
                          success:(void (^)(NSArray *roomMemberEvents))success
                          failure:(void (^)(NSError *error))failure ;

/**
 Get a list of all the current state events for this room.

 This is equivalent to the events returned under the 'state' key for this room in initialSyncOfRoom.

 @param roomId the id of the room.

 @param success A block object called when the operation succeeds. It provides the raw
 home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_state_events
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)stateOfRoom:(NSString*)roomId
                        success:(void (^)(NSArray *JSONData))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Inform the home server that the user is typing (or not) in this room.

 @param roomId the id of the room.
 @param typing Use YES if the user is currently typing.
 @param timeout the length of time until the user should be treated as no longer typing,
 in milliseconds. Can be ommited (set to -1) if they are no longer typing.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTypingNotificationInRoom:(NSString*)roomId
                                          typing:(BOOL)typing
                                         timeout:(NSUInteger)timeout
                                         success:(void (^)(void))success
                                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Redact an event in a room.

 @param eventId the id of the redacted event.
 @param roomId the id of the room.
 @param reason the redaction reason (optional).

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         inRoom:(NSString*)roomId
                         reason:(NSString*)reason
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Redact an event and all related events in a room.
 
 You can check whether a homeserver supports the redaction with relations via
 `supportsRedactionWithRelations`.
 
 @param eventId the id of the redacted event.
 @param roomId the id of the room.
 @param reason the redaction reason (optional).
 @param txnId the transaction id to use. If nil, one will be generated.
 @param relations the list of relation types (optional). If nil or empty, related events will not be redacted.
 @param withRelationsIsStable whether the feature to redact related event is stable.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)redactEvent:(NSString*)eventId
                         inRoom:(NSString*)roomId
                         reason:(NSString*)reason
                          txnId:(NSString*)txnId
                  withRelations:(NSArray<NSString *>*)relations
          withRelationsIsStable:(BOOL)withRelationsIsStable
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure;

/**
 Report a room.

 @param roomId the id of the room.
 @param reason the redaction reason (optional).

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
-(MXHTTPOperation *)reportRoom:(NSString *)roomId
                        reason:(NSString *)reason
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *))failure;

/**
 Report an event.

 @param eventId the id of the event event.
 @param roomId the id of the room.
 @param score the metric to let the user rate the severity of the abuse.
 It ranges from -100 “most offensive” to 0 “inoffensive”.
 @param reason the redaction reason (optional).

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)reportEvent:(NSString*)eventId
                         inRoom:(NSString*)roomId
                          score:(NSInteger)score
                         reason:(NSString*)reason
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get all the current information for this room, including messages and state events.

 @param roomId the id of the room.
 @param limit the maximum number of messages to return.

 @param success A block object called when the operation succeeds. It provides the model created from
 the homeserver JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_room_sync_data
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)initialSyncOfRoom:(NSString*)roomId
                            withLimit:(NSInteger)limit
                              success:(void (^)(MXRoomInitialSync *roomInitialSync))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Retrieve an event from its event id.

 @param eventId the id of the event to retrieve.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)eventWithEventId:(NSString*)eventId
                             success:(void (^)(MXEvent *event))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Retrieve an event from its room id and event id.

 @param eventId the id of the event to retrieve.
 @param roomId the id of the room where the event is.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)eventWithEventId:(NSString*)eventId
                              inRoom:(NSString*)roomId
                             success:(void (^)(MXEvent *event))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the context surrounding an event.

 This API returns a number of events that happened just before and after the specified event.

 @param eventId the id of the event to get context around.
 @param roomId the id of the room to get events from.
 @param limit the maximum number of messages to return.
 @param filter the filter to pass in the request. Can be nil.

 @param success A block object called when the operation succeeds. It provides the model created from
 the homeserver JSON response.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)contextOfEvent:(NSString*)eventId
                            inRoom:(NSString*)roomId
                             limit:(NSUInteger)limit
                            filter:(MXRoomEventFilter*)filter
                           success:(void (^)(MXEventContext *eventContext))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the related groups of a room.
 
 @param roomId the id of the room.
 @param relatedGroups the list of the related group identifiers.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomRelatedGroups:(NSString*)roomId
                           relatedGroups:(NSArray<NSString *>*)relatedGroups
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure;

/**
 Get the related groups of a room.
 
 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the list of the group ids.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)relatedGroupsOfRoom:(NSString*)roomId
                                success:(void (^)(NSArray<NSString *>* relatedGroups))success
                                failure:(void (^)(NSError *error))failure;

/**
 Get the room summary of a room
 
 @param roomIdOrAlias the id of the room or its alias
 @param via servers, that should be tried to request a summary from, if it can't be generated locally. These can be from a matrix URI, matrix.to link or a `m.space.child` event for example.
 @param success A block object called when the operation succeeds. It provides the public room data.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)roomSummaryWith:(NSString*)roomIdOrAlias
                                via:(NSArray<NSString *>*)via
                            success:(void (^)(MXPublicRoom *room))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Upgrade a room to a new version
 
 @param roomId the id of the room.
 @param roomVersion the new room version
 @param success A block object called when the operation succeeds. It provides the ID of the replacement room.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)upgradeRoomWithId:(NSString*)roomId
                                   to:(NSString*)roomVersion
                              success:(void (^)(NSString *replacementRoomId))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 List all the threads of a room.
 
 @param roomId the id of the room.
 @param include wether the response should include all threads (e.g. `kMXThreadsListIncludeAllParameter`) or only threads participated by the user (e.g. `kMXThreadsListIncludeParticipatedParameter`)
 @param from the token to pass for doing pagination from a previous response.
 @param success A block object called when the operation succeeds. It provides the list of root events of the threads and, optionally, the next batch token.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)threadsInRoomWithId:(NSString*)roomId
                                include:(NSString *)include
                                   from:(nullable NSString*)from
                                success:(void (^)(MXAggregationPaginatedResponse *response))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Room tags operations
/**
 List the tags of a room.

 @param roomId the id of the room.

 @param success A block object called when the operation succeeds. It provides an array of `MXRoomTag` objects.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)tagsOfRoom:(NSString*)roomId
                       success:(void (^)(NSArray<MXRoomTag*> *tags))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Add a tag to a room.

 Use this method to update the order of an existing tag.

 @param tag the new tag to add to the room.
 @param order the order. @see MXRoomTag.order.
 @param roomId the id of the room.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)addTag:(NSString*)tag
                 withOrder:(NSString*)order
                    toRoom:(NSString*)roomId
                   success:(void (^)(void))success
                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;
/**
 Remove a tag from a room.

 @param tag the tag to remove.
 @param roomId the id of the room.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)removeTag:(NSString*)tag
                     fromRoom:(NSString*)roomId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Room account data operations
/**
 Update the tagged events
 
 @param roomId the id of the room.
 @param content  the new tagged events content
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*) updateTaggedEvents:(NSString*)roomId
                            withContent:(MXTaggedEvents*)content
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the tagged events
 
 @param roomId the id of the room.
 
 @param success A block object called when the operation succeeds. It provides a MXTaggedEvents object.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*) getTaggedEvents:(NSString*)roomId
                             success:(void (^)(MXTaggedEvents *taggedEvents))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set a dedicated room account data field
 
 @param roomId the id of the room.
 @param eventTypeString  the type of the event. @see MXEventType.
 @param content the event content
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*) setRoomAccountData:(NSString*)roomId
                              eventType:(MXEventTypeString)eventTypeString
                         withParameters:(NSDictionary*)content
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the room account data field
 
 @param roomId the id of the room.
 @param eventTypeString  the type of the event. @see MXEventType.
 
 @param success A block object called when the operation succeeds. It provides the raw JSON response.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*) getRoomAccountData:(NSString*)roomId
                              eventType:(MXEventTypeString)eventTypeString
                                success:(void (^)(NSDictionary *JSONResponse))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Profile operations
/**
 Set the logged-in user display name.

 @param displayname the new display name.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setDisplayName:(NSString*)displayname
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the display name of a user.

 @param userId the user id.

 @param success A block object called when the operation succeeds. It provides the user displayname.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)displayNameForUser:(NSString*)userId
                               success:(void (^)(NSString *displayname))success
                               failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the logged-in user avatar url.

 @param avatarUrl the new avatar url.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setAvatarUrl:(NSString*)avatarUrl
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the avatar url of a user.

 @param userId the user id.
 @param success A block object called when the operation succeeds. It provides the user avatar url.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)avatarUrlForUser:(NSString*)userId
                             success:(void (^)(NSString *avatarUrl))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the profile information of a user.
 
 @param userId the user id.
 @param success A block object called when the operation succeeds. It provides the user display name and avatar url.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)profileForUser:(NSString*)userId
                           success:(void (^)(NSString *displayName, NSString *avatarUrl))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Link an authenticated 3rd party id to the Matrix user.

 This API is deprecated, and you should instead use `addThreePidOnly`
 for homeservers that support it.

 @param sid the id provided during the 3PID validation session (see [MXRestClient requestTokenForEmail:], or [MXRestClient requestEmailValidation:]).
 @param clientSecret the same secret key used in the validation session.
 @param bind whether the homeserver should also bind this third party identifier
 to the account's Matrix ID with the identity server.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)add3PID:(NSString*)sid
               clientSecret:(NSString*)clientSecret
                       bind:(BOOL)bind
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Add a 3PID to your homeserver account.

 This API does not use an identity server, as the homeserver is expected to
 handle 3PID ownership validation.

 You can check whether a homeserver supports this API via
 `doesServerSupportSeparateAddAndBind`.

 @param sid the session id provided during the 3PID validation session.
 @param clientSecret the same secret key used in the validation session.
 @param authParameters The additional authentication information for the user-interactive authentication API.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)add3PIDOnlyWithSessionId:(NSString*)sid
                                clientSecret:(NSString*)clientSecret
                                  authParams:(NSDictionary*)authParameters
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Remove a 3rd party id from the Matrix user information.
 
 @param address the 3rd party id.
 @param medium the type of the 3rd party id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)remove3PID:(NSString*)address
                        medium:(NSString*)medium
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 List all 3PIDs linked to the Matrix user account.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)threePIDs:(void (^)(NSArray<MXThirdPartyIdentifier*> *threePIDs))success
                      failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Bind a 3PID for discovery onto an identity server via the homeserver.

 The identity server handles 3PID ownership validation and the homeserver records
 the new binding to track where all 3PIDs for the account are bound.

 You can check whether a homeserver supports this API via
 `doesServerSupportSeparateAddAndBind`.

 @param sid the session id provided during the 3PID validation session.
 @param clientSecret the same secret key used in the validation session.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation*)bind3PidWithSessionId:(NSString*)sid
                             clientSecret:(NSString*)clientSecret
                                  success:(void (^)(void))success
                                  failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Unbind a 3PID for discovery on an identity server via the homeserver.

 The homeserver removes its record of the binding to keep an updated record of
 where all 3PIDs for the account are bound.

 @param address the 3rd party id.
 @param medium the type of the 3rd party id.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)unbind3PidWithAddress:(NSString*)address
                                   medium:(NSString*)medium
                                  success:(void (^)(void))success
                                  failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Presence operations
/**
 Set the current user presence status.

 @param presence the new presence status.
 @param statusMessage the new message status.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
                        success:(void (^)(void))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the presence status of a user.

 @param userId the user id.

 @param success A block object called when the operation succeeds. It provides a MXPresenceResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)presence:(NSString*)userId
                     success:(void (^)(MXPresenceResponse *presence))success
                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Sync
/**
 Synchronise the client's state and receive new messages.

 Synchronise the client's state with the latest state on the server.
 Client's use this API when they first log in to get an initial snapshot
 of the state on the server, and then continue to call this API to get
 incremental deltas to the state, and to receive new messages.

 @param token the token to stream from (nil in case of initial sync).
 @param serverTimeout the maximum time in ms to wait for an event.
 @param clientTimeout the maximum time in ms the SDK must wait for the server response.
 @param setPresence  the optional parameter which controls whether the client is automatically
 marked as online by polling this API. If this parameter is omitted then the client is
 automatically marked as online when it uses this API. Otherwise if
 the parameter is set to "offline" then the client is not marked as
 being online when it uses this API.
 @param filterId the ID of a filter created using the filter API (optinal).
 @param success A block object called when the operation succeeds. It provides a `MXSyncResponse` object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation *)syncFromToken:(NSString*)token
                     serverTimeout:(NSUInteger)serverTimeout
                     clientTimeout:(NSUInteger)clientTimeout
                       setPresence:(NSString*)setPresence
                            filter:(NSString*)filterId
                           success:(void (^)(MXSyncResponse *syncResponse))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Directory operations
/**
 Get the list of public rooms hosted by a home server.
 
 @discussion
 Pagination parameters (`limit` and `since`) should be used in order to limit
 homeserver resources usage.
 
 @param server (optional) the remote server to query for the room list. If nil, get the user
               homeserver's public room list.
 @param limit (optional, use -1 to not defined this value) the maximum number of entries to return.
 @param since (optional) token to paginate from.
 @param filter (optional) the string to search for.
 @param thirdPartyInstanceId (optional) returns rooms published to specific lists on 
                             a third party instance (like an IRC bridge).
 @param includeAllNetworks if YES, returns all rooms that have been published to any list. 
                           NO to return rooms on the main, default list.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)publicRoomsOnServer:(NSString*)server
                                  limit:(NSInteger)limit
                                  since:(NSString*)since
                                 filter:(NSString*)filter
                   thirdPartyInstanceId:(NSString*)thirdPartyInstanceId
                     includeAllNetworks:(BOOL)includeAllNetworks
                                success:(void (^)(MXPublicRoomsResponse *publicRoomsResponse))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Resolve given room alias to a room identifier and a list of servers aware of this identifier

 @param roomAlias the alias of the room to look for.

 @param success A block object called when the operation succeeds.
                It provides a resolution object containing room ID and a list of servers
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)resolveRoomAlias:(NSString *)roomAlias
                             success:(void (^)(MXRoomAliasResolution *resolution))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Third party Lookup API
/**
 Get the third party protocols that can be reached using this HS.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)thirdpartyProtocols:(void (^)(MXThirdpartyProtocolsResponse *thirdpartyProtocolsResponse))success
                                failure:(void (^)(NSError *error))failure;

/**
 Retrieve a Matrix User ID linked to a user on the third party service, given a set of user parameters.
 
 @param protocol Required. The name of the protocol.
 @param fields One or more custom fields that are passed to the AS to help identify the user. Not optional.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return an MXHTTPOperation instance.
 */
- (MXHTTPOperation*)thirdpartyUsers:(NSString *)protocol
                             fields:(NSDictionary<NSString*, NSString*> *)fields
                            success:(void (^)(MXThirdPartyUsersResponse *thirdpartyUsersResponse))success
                            failure:(void (^)(NSError *error))failure;


#pragma mark - Media Repository API
/**
 Upload content to HomeServer

 @param data the content to upload.
 @param filename optional filename
 @param mimeType the content type (image/jpeg, audio/aac...)
 @param timeoutInSeconds the maximum time in ms the SDK must wait for the server response.

 @param success A block object called when the operation succeeds. It provides the uploaded content url.
 @param failure A block object called when the operation fails.
 @param uploadProgress A block object called when the upload progresses.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadContent:(NSData *)data
                         filename:(NSString*)filename
                         mimeType:(NSString *)mimeType
                          timeout:(NSTimeInterval)timeoutInSeconds
                          success:(void (^)(NSString *url))success
                          failure:(void (^)(NSError *error))failure
                   uploadProgress:(void (^)(NSProgress *uploadProgress))uploadProgress NS_REFINED_FOR_SWIFT;

/**
Get the maximum size a media upload can be in bytes.
 
@param success A block object called when the operation succeeds. It provides the maximum size an upload can be in bytes.
@param failure A block object called when the operation fails.

@return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)maxUploadSize:(void (^)(NSInteger maxUploadSize))success
                          failure:(void (^)(NSError *error))failure;

/**
Get information about a URL for the client that can be used to render a preview.
 
Note: Clients should consider avoiding this endpoint for URLs posted in encrypted rooms.
 
@param url The URL to get the preview data for.
@param success A block object called when the operation succeeds. It provides an `MXURLPreview` object for the requested URL.
@param failure A block object called when the operation fails.

@return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)previewForURL:(NSURL*)url
                          success:(void (^)(MXURLPreview* urlPreview))success
                          failure:(void (^)(NSError *error))failure;


#pragma mark - Antivirus server API

/**
 Get the current public curve25519 key that the antivirus server is advertising.
 
 @param success A block object called when the operation succeeds. It provides the antivirus public key.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getAntivirusServerPublicKey:(void (^)(NSString *publicKey))success
                                        failure:(void (^)(NSError *error))failure;

/**
 Scan an unencrypted content.
 
 @param mxcContentURI the Matrix content URI to scan (in the form of "mxc://...").
 @param success A block object called when the operation succeeds. It provides the scan result.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)scanUnencryptedContent:(NSString*)mxcContentURI
                                   success:(void (^)(MXContentScanResult *scanResult))success
                                   failure:(void (^)(NSError *error))failure;

/**
 Scan an encrypted content.
 
 @param encryptedContentFile the information of the encrypted content
 @param success A block object called when the operation succeeds. It provides the scan result.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)scanEncryptedContent:(MXEncryptedContentFile*)encryptedContentFile
                                   success:(void (^)(MXContentScanResult *scanResult))success
                                   failure:(void (^)(NSError *error))failure;

/**
 Scan an encrypted content by sending an encrypted body (produced by considering the antivirus
 server public key).

 @param encryptedbody the encrypted data used to
 @param success A block object called when the operation succeeds. It provides the scan result.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)scanEncryptedContentWithSecureExchange:(MXContentScanEncryptedBody *)encryptedbody
                                                   success:(void (^)(MXContentScanResult *scanResult))success
                                                   failure:(void (^)(NSError *error))failure;


#pragma mark - Certificates
/**
 The certificates used to evaluate server trust.
 The default SSL pinning mode is MXHTTPClientSSLPinningModeCertificate when the provided set is not empty.
 Set an empty set or null to restore the default security policy.

 @param pinnedCertificates the pinned certificates.
 */
- (void)setPinnedCertificates:(NSSet<NSData *> *)pinnedCertificates;

/**
 Set the certificates used to evaluate server trust and the SSL pinning mode.
 
 @param pinnedCertificates The certificates to pin against.
 @param pinningMode The SSL pinning mode.
 */
- (void)setPinnedCertificates:(NSSet<NSData *> *)pinnedCertificates withPinningMode:(MXHTTPClientSSLPinningMode)pinningMode;


#pragma mark - VoIP API
/**
 Get the TURN server configuration advised by the homeserver.

 @param success A block object called when the operation succeeds. It provides
 a `MXTurnServerResponse` object. It is nil if the HS has TURN config
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)turnServer:(void (^)(MXTurnServerResponse *turnServerResponse))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - read receipt
/**
 Send a read receipt.

 @param roomId the id of the room.
 @param eventId the id of the event.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendReadReceipt:(NSString*)roomId
                            eventId:(NSString*)eventId
                           threadId:(nullable NSString*)threadId
                            success:(void (^)(void))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - read marker
/**
 Send a read marker with an optional read receipt.
 
 @param roomId the id of the room.
 @param readMarkerEventId the read marker event Id.
 @param readReceiptEventId the nullable read receipt event Id.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendReadMarker:(NSString*)roomId
                 readMarkerEventId:(NSString*)readMarkerEventId
                readReceiptEventId:(NSString*)readReceiptEventId
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Search
/**
 Search a text in room messages.

 @param textPattern the text to search for in message body.
 @param roomEventFilter the filter to pass in the request. Can be nil.
 @param beforeLimit the number of events to get before the matching results.
 @param afterLimit the number of events to get after the matching results.
 @param nextBatch the token to pass for doing pagination from a previous response.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)searchMessagesWithText:(NSString*)textPattern
                           roomEventFilter:(MXRoomEventFilter*)roomEventFilter
                               beforeLimit:(NSUInteger)beforeLimit
                                afterLimit:(NSUInteger)afterLimit
                                 nextBatch:(NSString*)nextBatch
                                   success:(void (^)(MXSearchRoomEventResults *roomEventResults))success
                                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Make a search.

 @param parameters the search parameters as defined by the Matrix search spec (http://matrix.org/docs/api/client-server/#!/Search/post_search ).
 @param nextBatch the token to pass for doing pagination from a previous response.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)search:(NSDictionary*)parameters
                 nextBatch:(NSString*)nextBatch
                   success:(void (^)(MXSearchRoomEventResults *roomEventResults))success
                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


/**
 Search users on homeserver user directory.

 @param pattern the search pattern.
 @param limit the number of users to return.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
*/
- (MXHTTPOperation*)searchUsers:(NSString*)pattern
                          limit:(NSUInteger)limit
                        success:(void (^)(MXUserSearchResponse *userSearchResponse))success
                        failure:(void (^)(NSError *error))failure;


#pragma mark - Crypto
/**
 Upload device and/or one-time keys.

 @param deviceKeys the device keys to send.
 @param oneTimeKeys the one-time keys to send.
 @param fallbackKeys the fallback keys to send.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadKeys:(NSDictionary*)deviceKeys
                   oneTimeKeys:(NSDictionary*)oneTimeKeys
                  fallbackKeys:(NSDictionary *)fallbackKeys
                       success:(void (^)(MXKeysUploadResponse *keysUploadResponse))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Upload device and/or one-time keys.

 @param deviceKeys the device keys to send.
 @param oneTimeKeys the one-time keys to send.
 @param fallbackKeys the fallback keys to send.
 @param deviceId ID of the device the keys belong to. Nil to upload keys to the device of the current session.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadKeys:(NSDictionary*)deviceKeys
                   oneTimeKeys:(NSDictionary*)oneTimeKeys
                  fallbackKeys:(NSDictionary *)fallbackKeys
               forDeviceWithId:(NSString*)deviceId
                       success:(void (^)(MXKeysUploadResponse *keysUploadResponse))success
                       failure:(void (^)(NSError *error))failure;

/**
 Upload signatures of device keys.

 @param signatures the signatures content.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadKeySignatures:(NSDictionary*)signatures
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure;

/**
 Download device keys.

 @param userIds list of users to get keys for.
 @param token sync token to pass in the query request, to help
              the HS give the most recent results. It can be nil.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)downloadKeysForUsers:(NSArray<NSString*>*)userIds
                                   token:(NSString*)token
                                 success:(void (^)(MXKeysQueryResponse *keysQueryResponse))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

- (MXHTTPOperation*)downloadKeysRawForUsers:(NSArray<NSString*>*)userIds
                                   token:(NSString*)token
                                 success:(void (^)(MXKeysQueryResponseRaw *keysQueryResponse))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;
/**
 * Claim one-time keys.

 @param usersDevicesKeyTypesMap a list of users, devices and key types to retrieve keys for.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)claimOneTimeKeysForUsersDevices:(MXUsersDevicesMap<NSString*>*)usersDevicesKeyTypesMap
                                            success:(void (^)(MXKeysClaimResponse *keysClaimResponse))success
                                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Ask the server for a list of users who have changed their device lists
 between a pair of sync tokens

 @param fromToken the old token.
 @param toToken the new token.

 @param success A block object called when the operation succeeds. deviceLists is the
                list of users with a change in their devices.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keyChangesFrom:(NSString*)fromToken to:(NSString*)toToken
                           success:(void (^)(MXDeviceListResponse *deviceLists))success
                           failure:(void (^)(NSError *error))failure;

#pragma mark - Device Dehydration

/**
 Creates a new dehydrated device on the current user's account with the given parameters, coming out of the RustCryptoSDK
 @param parameters the device data as received from the RustCryptoSDK
 @param success A block object called when the operation succeeds. It provides the ID of the newly dehydrated device.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createDehydratedDevice:(MXDehydratedDeviceCreationParameters *)parameters
                                   success:(void (^)(NSString * _Nonnull deviceId))success
                                   failure:(void (^)(NSError * _Nonnull error))failure;

/**
 Get the dehydrated device of the current account.
 @param success A block object called when the operation succeeds. It provides a `MXDehydratedDeviceResponse` instance of the current account.
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
  */
- (MXHTTPOperation*)retrieveDehydratedDeviceWithSuccess:(void (^)(MXDehydratedDeviceResponse * _Nonnull dehydratedDevice))success
                                                failure:(void (^)(NSError * _Nonnull error))failure;

/**
 Delete the current dehydrated device
 @param success A block object called when the operation succeeds
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
  */
- (MXHTTPOperation*)deleteDehydratedDeviceWithSuccess:(void (^)(void))success
                                              failure:(void (^)(NSError * _Nonnull error))failure;

/**
 Retrieves the to device events stored on the backend for the given dehydrated device. Results are batched so multiple invocations might be necessary
 @param deviceId The dehydrated device id in question
 @param nextBatch Pagination token for retrieving more events
 @param success A block object called when the operation succeeds. It provides the events and a next batch token
 @param failure A block object called when the operation fails.
 @return a MXHTTPOperation instance.
  */
- (MXHTTPOperation*)retrieveDehydratedDeviceEventsForDeviceId:(NSString *)deviceId
                                                    nextBatch:(NSString *)nextBatch
                                                      success:(void (^)(MXDehydratedDeviceEventsResponse * _Nonnull dehydratedDeviceEventsResponse))success
                                                      failure:(void (^)(NSError * _Nonnull error))failure;

#pragma mark - Crypto: e2e keys backup

/**
 Create a new backup version.

 @param keyBackupVersion backup information.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
                                   success:(void (^)(NSString *version))success
                                   failure:(void (^)(NSError *error))failure;

/**
 Update associated data to a backup version.

 @param keyBackupVersion backup information.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)updateKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError *error))failure;

/**
 Delete a backup version.

 @param version the backup version to delete.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeyBackupVersion:(NSString*)version
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError *error))failure;

/**
 Get information about a backup version.

 @param version the backup version. Nil returns the current backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keyBackupVersion:(NSString*)version
                             success:(void (^)(MXKeyBackupVersion *keyBackupVersion))success
                             failure:(void (^)(NSError *error))failure;

/**
 Back up a session key to the homeserver.

 @param keyBackupData the key to backup.
 @param roomId the id of the room that the keys are for.
 @param sessionId the id of the session that the keys are.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendKeyBackup:(MXKeyBackupData*)keyBackupData
                             room:(NSString*)roomId
                          session:(NSString*)sessionId
                          version:(NSString*)version
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure;

/**
 Back up keys in a room to the homeserver.

 @param roomKeysBackupData keys to backup.
 @param roomId the id of the room that the keys are for.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendRoomKeysBackup:(MXRoomKeysBackupData*)roomKeysBackupData
                                  room:(NSString*)roomId
                               version:(NSString*)version
                               success:(void (^)(void))success
                               failure:(void (^)(NSError *error))failure;

/**
 Back up keys to the homeserver.

 @param keysBackupData keys to backup.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendKeysBackup:(MXKeysBackupData*)keysBackupData
                           version:(NSString*)version
                           success:(void (^)(NSDictionary *JSONResponse))success
                           failure:(void (^)(NSError *error))failure;

/**
 Retrieve the backup for a session key from the homeserver.

 @param sessionId the id of the session that the keys are.
 @param roomId the id of the room that the keys are for.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keyBackupForSession:(NSString*)sessionId
                                 inRoom:(NSString*)roomId
                                version:(NSString*)version
                                success:(void (^)(MXKeyBackupData *keyBackupData))success
                                failure:(void (^)(NSError *error))failure;

/**
 Retrieve the backup for all keys in a room from the homeserver.

 @param roomId the id of the room that the keys are for.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keysBackupInRoom:(NSString*)roomId
                             version:(NSString*)version
                             success:(void (^)(MXRoomKeysBackupData *roomKeysBackupData))success
                             failure:(void (^)(NSError *error))failure;

/**
 Retrieve all keys backup from the homeserver.

 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keysBackup:(NSString*)version
                       success:(void (^)(MXKeysBackupData *keysBackupData))success
                       failure:(void (^)(NSError *error))failure;

/**
 Delete the backup for a session key from the homeserver.

 @param roomId the id of the room that the keys are for.
 @param sessionId the id of the session that the keys are.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeyFromBackup:(NSString*)roomId
                                session:(NSString*)sessionId
                                version:(NSString*)version
                                success:(void (^)(void))success
                                failure:(void (^)(NSError *error))failure;

/**
 Delete the backup for all keys in a room from the homeserver.

 @param roomId the id of the room that the keys are for.
 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeysInRoomFromBackup:(NSString*)roomId
                                       version:(NSString*)version
                                       success:(void (^)(void))success
                                       failure:(void (^)(NSError *error))failure;

/**
 Delete all keys backup from the homeserver.

 @param version the backup version.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteKeysFromBackup:(NSString*)version
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure;


#pragma mark - Direct-to-device messaging
/**
 Send an event to a specific list of devices

 @param payload Payload with `eventType` and `contentMap` to be sent

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendToDevice:(MXToDevicePayload*)payload
                         success:(void (^)(void))success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Device Management
/**
 Get information about all devices for the current user.
 
 @param success A block object called when the operation succeeds. It provides an array of the devices.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)devices:(void (^)(NSArray<MXDevice *> *))success
                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get information on a single device, by device id.
 
 @param deviceId The device identifier.
 @param success A block object called when the operation succeeds. It provides information on the requested device.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deviceByDeviceId:(NSString *)deviceId
                             success:(void (^)(MXDevice *))success
                             failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Update the display name of a given device.
 
 @param deviceName The new device name. If not given, the display name is unchanged.
 @param deviceId The device identifier.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setDeviceName:(NSString *)deviceName
                      forDeviceId:(NSString *)deviceId
                          success:(void (^)(void))success
                          failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get an authentication session to delete a device.
 
 @param success A block object called when the operation succeeds. It provides the server response
 as an MXAuthenticationSession instance.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getSessionToDeleteDeviceByDeviceId:(NSString *)deviceId
                                               success:(void (^)(MXAuthenticationSession *authSession))success
                                               failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Delete the given device, and invalidates any access token associated with it.
 
 @discussion This API endpoint uses the User-Interactive Authentication API.
 
 @param deviceId The device identifier.
 @param authParameters The additional authentication information for the user-interactive authentication API.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteDeviceByDeviceId:(NSString *)deviceId
                                authParams:(NSDictionary*)authParameters
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Deletes the given devices, and invalidates any access token associated with them.
 
 @discussion This API endpoint uses the User-Interactive Authentication API.
 
 @param deviceIds The identifiers for devices.
 @param authParameters The additional authentication information for the user-interactive authentication API.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)deleteDevicesByDeviceIds:(NSArray<NSString*>*)deviceIds
                                  authParams:(NSDictionary*)authParameters
                                     success:(void (^)(void))success
                                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Cross-Signing

/**
 Get an authentication session to upload cross-signing keys.

 @param success A block object called when the operation succeeds. It provides the server response
 as an MXAuthenticationSession instance.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)authSessionToUploadDeviceSigningKeys:(void (^)(MXAuthenticationSession *authSession))success
                                                 failure:(void (^)(NSError *error))failure;

/**
 Upload cross-signing keys.

 @param keys A dictionary containing keys.
 @param authParameters The additional authentication information for the user-interactive authentication API.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadDeviceSigningKeys:(NSDictionary *)keys
                                 authParams:(NSDictionary*)authParameters
                                    success:(void (^)(void))success
                                    failure:(void (^)(NSError *error))failure;


#pragma mark - Groups
    
/**
 Accept the invitation to join a group.
 
 @param groupId the id of the group to join.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)acceptGroupInvite:(NSString*)groupId
                              success:(void (^)(void))success
                              failure:(void (^)(NSError *error))failure;
/**
 Leave a group.
 
 @param groupId the id of the group to leave.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)leaveGroup:(NSString*)groupId
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure;

/**
 Update the group publicity for the current user.
 
 @param groupId the id of the group.
 @param isPublicised tell whether the user published this community on his profile
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (MXHTTPOperation*)updateGroupPublicity:(NSString*)groupId
                            isPublicised:(BOOL)isPublicised
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure;

/**
 Get the group profile.
 
 @param groupId the id of the group.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getGroupProfile:(NSString*)groupId
                            success:(void (^)(MXGroupProfile *groupProfile))success
                            failure:(void (^)(NSError *error))failure;

/**
 Get the group summary.
 
 @param groupId the id of the group.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getGroupSummary:(NSString*)groupId
                            success:(void (^)(MXGroupSummary *groupSummary))success
                            failure:(void (^)(NSError *error))failure;

/**
 Get the group users.
 
 @param groupId the id of the group.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getGroupUsers:(NSString*)groupId
                          success:(void (^)(MXGroupUsers *groupUsers))success
                          failure:(void (^)(NSError *error))failure;

/**
 Get the invited users in a group.
 
 @param groupId the id of the group.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getGroupInvitedUsers:(NSString*)groupId
                                 success:(void (^)(MXGroupUsers *invitedUsers))success
                                 failure:(void (^)(NSError *error))failure;

/**
 Get the group rooms.
 
 @param groupId the id of the group.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getGroupRooms:(NSString*)groupId
                          success:(void (^)(MXGroupRooms *groupRooms))success
                          failure:(void (^)(NSError *error))failure;

/**
 Get the publicised groups for a list of users.
 We got a list of group identifiers for each listed user id.
 
 @param userIds the list of the user identifiers.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)getPublicisedGroupsForUsers:(NSArray<NSString*>*)userIds
                                        success:(void (^)(NSDictionary<NSString*, NSArray<NSString*>*> *publicisedGroupsByUserId))success
                                        failure:(void (^)(NSError *error))failure;


#pragma mark - Aggregations

/**
 Get relations for a given event.

 @param eventId the id of the event,
 @param roomId the id of the room.
 @param relationType (optional) the type of relation.
 @param eventType (optional) event type to filter by.
 @param from the token to start getting results from.
 @param direction direction from the token.
 @param limit (optional, use -1 to not defined this value) the maximum number of messages to return.

 @param success A block object called when the operation succeeds. It provides a `MXAggregationPaginatedResponse` object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)relationsForEvent:(NSString*)eventId
                               inRoom:(NSString*)roomId
                         relationType:(NSString*)relationType
                            eventType:(NSString*)eventType
                                 from:(NSString*)from
                            direction:(MXTimelineDirection)direction
                                limit:(NSInteger)limit
                              success:(void (^)(MXAggregationPaginatedResponse *paginatedResponse))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Spaces

/// Get the space summary of a given space.
/// @param spaceId The room id of the queried space.
/// @param suggestedOnly If `true`, return only child events and rooms where the `m.space.child` event has `suggested: true`.
/// @param limit A limit to the maximum number of children to return per space. `-1` for no limit
/// @param maxDepth The maximum depth in the tree (from the root room) to return. The deepest depth returned will not include children events. `-1` for no limit
/// @param paginationToken Pagination token given to retrieve the next set of rooms.
/// @param success A block object called when the operation succeeds. It provides a `MXSpaceChildrenResponse` object.
/// @param failure A block object called when the operation fails.
/// @return a MXHTTPOperation instance.
- (MXHTTPOperation*)getSpaceChildrenForSpaceWithId:(NSString*)spaceId
                                     suggestedOnly:(BOOL)suggestedOnly
                                             limit:(NSInteger)limit
                                          maxDepth:(NSInteger)maxDepth
                                   paginationToken:(NSString*)paginationToken
                                           success:(void (^)(MXSpaceChildrenResponse *spaceChildrenResponse))success
                                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Homeserver capabilities

/// Get the capabilities of the home server
/// @param success A block object called when the operation succeeds. It provides a `MXHomeserverCapabilities` object.
/// @param failure A block object called when the operation fails.
/// @return a MXHTTPOperation instance.
- (MXHTTPOperation*)homeServerCapabilitiesWithSuccess:(void (^)(MXHomeserverCapabilities *capabilities))success
                                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

@end

MX_ASSUME_MISSING_NULLABILITY_END
