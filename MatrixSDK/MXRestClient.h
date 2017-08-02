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

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#endif

#import "MXHTTPClient.h"
#import "MXEvent.h"
#import "MXRoomEventFilter.h"
#import "MXInvite3PID.h"
#import "MXEventTimeline.h"
#import "MXJSONModels.h"


#pragma mark - Constants definitions
/**
 A constant representing the URI path for release 0 of the Client-Server HTTP API.
 */
FOUNDATION_EXPORT NSString *const kMXAPIPrefixPathR0;

/**
 A constant representing tthe URI path for as-yet unspecified of the Client-Server HTTP API.
 */
FOUNDATION_EXPORT NSString *const kMXAPIPrefixPathUnstable;

/**
 Prefix used in path of identity server API requests.
 */
FOUNDATION_EXPORT NSString *const kMXIdentityAPIPrefixPath;

/**
 Scheme used in Matrix content URIs.
 */
FOUNDATION_EXPORT NSString *const kMXContentUriScheme;
/**
 A constant representing the prefix of the Matrix content repository path.
 */
FOUNDATION_EXPORT NSString *const kMXContentPrefixPath;

/**
 Account data types
 */
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeDirect;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypePushRules;
FOUNDATION_EXPORT NSString *const kMXAccountDataTypeIgnoredUserList;

/**
 Account data keys
 */
FOUNDATION_EXPORT NSString *const kMXAccountDataKeyIgnoredUser;

/**
 MXRestClient error domain
 */
FOUNDATION_EXPORT NSString *const kMXRestClientErrorDomain;


/**
 Methods of thumnailing supported by the Matrix content repository.
 */
typedef enum : NSUInteger
{
    /**
     "scale" tries to return an image where either the width or the height is smaller than the
     requested size. The client should then scale and letterbox the image if it needs to
     fit within a given rectangle.
     */
    MXThumbnailingMethodScale,

    /**
     "crop" tries to return an image where the width and height are close to the requested size
     and the aspect matches the requested size. The client should scale the image if it needs to
     fit within a given rectangle.
     */
    MXThumbnailingMethodCrop
} MXThumbnailingMethod;

/**
 `MXRestClient` makes requests to Matrix servers.

 It is the single point to send requests to Matrix servers which are:
    - the specified Matrix home server
    - the Matrix content repository manage by this home server
    - the specified Matrix identity server
 */
@interface MXRestClient : NSObject
    {
        /**
         HTTP client to the home server.
         */
        MXHTTPClient *httpClient;
        
        /**
         HTTP client to the identity server.
         */
        MXHTTPClient *identityHttpClient;
        
        /**
         The queue to process server response.
         This queue is used to create models from JSON dictionary without blocking the main thread.
         */
        dispatch_queue_t processingQueue;
        
        /**
         The queue on which asynchronous response blocks are called.
         Default is dispatch_get_main_queue().
         */
        dispatch_queue_t completionQueue;
    }


/**
 The homeserver.
 */
@property (nonatomic, readonly) NSString *homeserver;

/**
 The user credentials on this home server.
 */
@property (nonatomic) MXCredentials *credentials;

/**
 The homeserver suffix (for example ":matrix.org"). Available only when credentials have been set.
 */
@property (nonatomic, readonly) NSString *homeserverSuffix;

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
 The identity server.
 By default, it points to the defined home server. If needed, change it by setting
 this property.
 */
@property (nonatomic) NSString *identityServer;

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
 HTTP client to the home server.
 */
@property (nonatomic) MXHTTPClient *httpClient;

/**
 HTTP client to the identity server.
 */
@property (nonatomic) MXHTTPClient *identityHttpClient;

/**
 The queue to process server response.
 This queue is used to create models from JSON dictionary without blocking the main thread.
 */
@property (nonatomic) dispatch_queue_t processingQueue;

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
-(id)initWithCredentials:(MXCredentials*)credentials andOnUnrecognizedCertificateBlock:(MXHTTPClientOnUnrecognizedCertificate)onUnrecognizedCertBlock NS_REFINED_FOR_SWIFT;

- (void)close;

#pragma mark - Registration operations
/**
 Check whether a username is already in use.

 @username the user name to test (This value must not be nil).
 @param callback A block object called when the operation is completed.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)isUserNameInUse:(NSString*)username
                           callback:(void (^)(BOOL isUserNameInUse))callback NS_REFINED_FOR_SWIFT;
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
 
 The identity server will send an email to this address. The end user
 will have to click on the link it contains to validate the address.
 
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
 Reset the account password.

 @param parameters a set of parameters containing a threepid credentials and the new password.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)resetPasswordWithParameters:(NSDictionary*)parameters
                                        success:(void (^)())success
                                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Replace the account password.

 @param oldPassword the current password to update.
 @param newPassword the new password.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)changePassword:(NSString*)oldPassword with:(NSString*)newPassword
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Invalidate the access token, so that it can no longer be used for authorization.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)logout:(void (^)())success
                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

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
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - 3pid token request
/**
 Request the validation of an email address (like `requestEmailValidation` in identity server API),
 but first checks that the given email address is not already associated with an account on this Home Server.
 
 The identity server will send an email to this address. The end user
 will have to click on the link it contains to validate the address.
 
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
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Request the validation of a phone number (like `requestPhoneNumberValidation` in identity server API),
 but first checks that the given email address is not already associated with an account on this Home Server.
 
 The identity server will send a validation token by sms. The end user
 will have to send this token by using [MXRestClient submit3PIDValidationToken].
 
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
                                       success:(void (^)(NSString *sid, NSString *msisdn))success
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
                                 success:(void (^)())success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

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
                            success:(void (^)())success
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
                            success:(void (^)())success
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
                         success:(void (^)())success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;


#pragma mark - Room operations
/**
 Send a generic non state event to a room.

 @param roomId the id of the room.
 @param eventTypeString the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendEventToRoom:(NSString*)roomId
                          eventType:(MXEventTypeString)eventTypeString
                            content:(NSDictionary*)content
                            success:(void (^)(NSString *eventId))success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a generic state event to a room.

 @param roomId the id of the room.
 @param eventTypeString the type of the event. @see MXEventType.
 @param content the content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendStateEventToRoom:(NSString*)roomId
                               eventType:(MXEventTypeString)eventTypeString
                                 content:(NSDictionary*)content
                                 success:(void (^)(NSString *eventId))success
                                 failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a message to a room

 @param roomId the id of the room.
 @param msgType the type of the message. @see MXMessageType.
 @param content the message content that will be sent to the server as a JSON object.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendMessageToRoom:(NSString*)roomId
                              msgType:(MXMessageType)msgType
                              content:(NSDictionary*)content
                              success:(void (^)(NSString *eventId))success
                              failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Send a text message to a room

 @param roomId the id of the room.
 @param text the text to send.
 @param success A block object called when the operation succeeds. It returns
 the event id of the event generated on the home server
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendTextMessageToRoom:(NSString*)roomId
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
                         success:(void (^)())success
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
                          success:(void (^)())success
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
                        success:(void (^)())success
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
                                     success:(void (^)())success
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

 @param roomId the id of the room.
 @param joinRule the rule to set.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)setRoomJoinRule:(NSString*)roomId
                           joinRule:(MXRoomJoinRule)joinRule
                            success:(void (^)())success
                            failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the join rule of a room.

 @param roomId the id of the room.
 @param success A block object called when the operation succeeds. It provides the room join rule.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRuleOfRoom:(NSString*)roomId
                           success:(void (^)(MXRoomJoinRule joinRule))success
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
                               success:(void (^)())success
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
                                       success:(void (^)())success
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
                         success:(void (^)())success
                         failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Remove a mapping of room alias to room ID.
 
 @param roomAlias the alias to remove.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)removeRoomAlias:(NSString*)roomAlias
                            success:(void (^)())success
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
                           success:(void (^)())success
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
 @param success A block object called when the operation succeeds. It provides the room id.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
                     success:(void (^)(NSString *theRoomId))success
                     failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Join a room where the user has been invited by a 3PID invitation.

 @param roomIdOrAlias the id or an alias of the room to join.
 @param thirdPartySigned the signed data obtained by the validation of the 3PID invitation.
                         The valisation is made by [self signUrl].
 @param success A block object called when the operation succeeds. It provides the room id.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)joinRoom:(NSString*)roomIdOrAlias
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
                      success:(void (^)())success
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
                       success:(void (^)())success
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
                              success:(void (^)())success
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
                             success:(void (^)())success
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
                     success:(void (^)())success
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
                    success:(void (^)())success
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
                      success:(void (^)())success
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

 @param name (optional) the room name.
 @param visibility (optional) the visibility of the room in the current HS's room directory.
 @param roomAlias (optional) the room alias on the home server the room will be created.
 @param topic (optional) the room topic.
 @param inviteArray (optional) A list of user IDs to invite to the room. This will tell the server to invite everyone in the list to the newly created room.
 @param invite3PIDArray (optional) A list of objects representing third party IDs to invite into the room.
 @param isDirect This flag makes the server set the is_direct flag on the m.room.member events sent to the users in invite and invite_3pid (Use NO by default).
 @param preset (optional) Convenience parameter for setting various default state events based on a preset.

 @param success A block object called when the operation succeeds. It provides a MXCreateRoomResponse object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)createRoom:(NSString*)name
                    visibility:(MXRoomDirectoryVisibility)visibility
                     roomAlias:(NSString*)roomAlias
                         topic:(NSString*)topic
                        invite:(NSArray<NSString*>*)inviteArray
                    invite3PID:(NSArray<MXInvite3PID*>*)invite3PIDArray
                      isDirect:(BOOL)isDirect
                        preset:(MXRoomPreset)preset
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
 @param roomEventFilter to filter returned events with.

 @param success A block object called when the operation succeeds. It provides a `MXPaginationResponse` object.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)messagesForRoom:(NSString*)roomId
                               from:(NSString*)from
                          direction:(MXTimelineDirection)direction
                              limit:(NSUInteger)limit
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
 Get a list of all the current state events for this room.

 This is equivalent to the events returned under the 'state' key for this room in initialSyncOfRoom.

 @param roomId the id of the room.

 @param success A block object called when the operation succeeds. It provides the raw
 home server JSON response. @see http://matrix.org/docs/api/client-server/#!/-rooms/get_state_events
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)stateOfRoom:(NSString*)roomId
                        success:(void (^)(NSDictionary *JSONData))success
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
                                         success:(void (^)())success
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
                        success:(void (^)())success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

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
                        success:(void (^)())success
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
 Get the context surrounding an event.

 This API returns a number of events that happened just before and after the specified event.

 @param eventId the id of the event to get context around.
 @param roomId the id of the room to get events from.
 @param limit the maximum number of messages to return.

 @param success A block object called when the operation succeeds. It provides the model created from
 the homeserver JSON response.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)contextOfEvent:(NSString*)eventId
                            inRoom:(NSString*)roomId
                             limit:(NSUInteger)limit
                           success:(void (^)(MXEventContext *eventContext))success
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
                   success:(void (^)())success
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
                      success:(void (^)())success
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
                           success:(void (^)())success
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
                         success:(void (^)())success
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
 Link an authenticated 3rd party id to the Matrix user.

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
                    success:(void (^)())success
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
                       success:(void (^)())success
                       failure:(void (^)(NSError *error))failure;

/**
 List all 3PIDs linked to the Matrix user account.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)threePIDs:(void (^)(NSArray<MXThirdPartyIdentifier*> *threePIDs))success
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
                        success:(void (^)())success
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
                                  limit:(NSUInteger)limit
                                  since:(NSString*)since
                                 filter:(NSString*)filter
                   thirdPartyInstanceId:(NSString*)thirdPartyInstanceId
                     includeAllNetworks:(BOOL)includeAllNetworks
                                success:(void (^)(MXPublicRoomsResponse *publicRoomsResponse))success
                                failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Get the room ID corresponding to this room alias

 @param roomAlias the alias of the room to look for.

 @param success A block object called when the operation succeeds. It provides the ID of the room.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)roomIDForRoomAlias:(NSString*)roomAlias
                               success:(void (^)(NSString *roomId))success
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
 Resolve a Matrix media content URI (in the form of "mxc://...") into an HTTP URL.

 @param mxcContentURI the Matrix content URI to resolve.
 @return the Matrix content HTTP URL. nil if the Matrix content URI is invalid.
 */
- (NSString*)urlOfContent:(NSString*)mxcContentURI;

/**
 Get the suitable HTTP URL of a thumbnail image from a Matrix media content according to the destined view size.

 @param mxcContentURI the Matrix content URI to resolve.
 @param viewSize in points, it will be converted in pixels by considering screen scale.
 @param thumbnailingMethod the method the Matrix content repository must use to generate the thumbnail.
 @return the thumbnail HTTP URL. The provided URI is returned if it is not a valid Matrix content URI.
 */
- (NSString*)urlOfContentThumbnail:(NSString*)mxcContentURI toFitViewSize:(CGSize)viewSize withMethod:(MXThumbnailingMethod)thumbnailingMethod;

/**
 Get the HTTP URL of an identicon served by the media repository.

 @param identiconString the string to build an identicon from.
 @return the identicon HTTP URL.
 */
- (NSString*)urlOfIdenticon:(NSString*)identiconString;


#pragma mark - Identity server API
/**
 Retrieve a user matrix id from a 3rd party id.

 @param address the id of the user in the 3rd party system.
 @param medium the 3rd party system (ex: "email").

 @param success A block object called when the operation succeeds. It provides the Matrix user id.
 It is nil if the user is not found.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)lookup3pid:(NSString*)address
                     forMedium:(MX3PIDMedium)medium
                       success:(void (^)(NSString *userId))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Retrieve user matrix ids from a list of 3rd party ids.

 @param threepids the list of 3rd party ids: [[<(MX3PIDMedium)media1>, <(NSString*)address1>], [<(MX3PIDMedium)media2>, <(NSString*)address2>], ...].
 @param success A block object called when the operation succeeds. It provides the array of the discovered users returned by the identity server.
 [[<(MX3PIDMedium)media>, <(NSString*)address>, <(NSString*)userId>], ...].
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)lookup3pids:(NSArray*)threepids
                        success:(void (^)(NSArray *discoveredUsers))success
                        failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Request the validation of an email address.

 The identity server will send an email to this address. The end user
 will have to click on the link it contains to validate the address.

 Use the returned sid to complete operations that require authenticated email
 like [MXRestClient add3PID:].

 @param email the email address to validate.
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
- (MXHTTPOperation*)requestEmailValidation:(NSString*)email
                              clientSecret:(NSString*)clientSecret
                               sendAttempt:(NSUInteger)sendAttempt
                                  nextLink:(NSString*)nextLink
                                   success:(void (^)(NSString *sid))success
                                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Request the validation of a phone number.
 
 The identity server will send a validation token by sms. The end user
 will have to send this token by using [MXRestClient submit3PIDValidationToken].
 
 Use the returned sid to complete operations that require authenticated phone number
 like [MXRestClient add3PID:].
 
 @param phoneNumber the phone number (in international or national format).
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
- (MXHTTPOperation*)requestPhoneNumberValidation:(NSString*)phoneNumber
                                     countryCode:(NSString*)countryCode
                                    clientSecret:(NSString*)clientSecret
                                     sendAttempt:(NSUInteger)sendAttempt
                                        nextLink:(NSString *)nextLink
                                         success:(void (^)(NSString *sid, NSString *msisdn))success
                                         failure:(void (^)(NSError *error))failure;

/**
 Submit the validation token received by an email or a sms.
 
 In case of success, the related third-party id has been validated.
 
 @param token the validation token.
 @param medium the type of the third-party id (see kMX3PIDMediumEmail, kMX3PIDMediumMSISDN).
 @param clientSecret the clientSecret used during the validation request.
 @param sid the validation session id returned by the server.
 
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 
 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)submit3PIDValidationToken:(NSString *)token
                                        medium:(NSString *)medium
                                  clientSecret:(NSString *)clientSecret
                                           sid:(NSString *)sid
                                       success:(void (^)())success
                                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Sign a 3PID URL.

 @param signUrl the URL that will be called for signing.
 @param success A block object called when the operation succeeds. It provides the signed data.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)signUrl:(NSString*)signUrl
                    success:(void (^)(NSDictionary *thirdPartySigned))success
                    failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

/**
 Set the certificates used to evaluate server trust according to the SSL pinning mode.

 @param pinnedCertificates the pinned certificates.
 */
-(void)setPinnedCertificates:(NSSet <NSData *> *)pinnedCertificates;

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
                            success:(void (^)())success
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
                           success:(void (^)())success
                           failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

#pragma mark - Search
/**
 Search a text in room messages.

 @param textPattern the text to search for in message body.
 @param roomEventFilter a nullable dictionary which defines the room event filtering during the search request.
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
 @param deviceId the explicit device_id to use for upload
        (default is to use the same as that used during auth).

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)uploadKeys:(NSDictionary*)deviceKeys oneTimeKeys:(NSDictionary*)oneTimeKeys
                     forDevice:(NSString*)deviceId
                       success:(void (^)(MXKeysUploadResponse *keysUploadResponse))success
                       failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;

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

 @param success A block object called when the operation succeeds. changed is the
                list of users with a change in their devices.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)keyChangesFrom:(NSString*)fromToken to:(NSString*)toToken
                           success:(void (^)(NSArray<NSString*> *changed))success
                           failure:(void (^)(NSError *error))failure;


#pragma mark - Direct-to-device messaging
/**
 Send an event to a specific list of devices

 @param eventType the type of event to send
 @param contentMap content to send. Map from user_id to device_id to content dictionary.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.

 @return a MXHTTPOperation instance.
 */
- (MXHTTPOperation*)sendToDevice:(NSString*)eventType contentMap:(MXUsersDevicesMap<NSDictionary*>*)contentMap
                         success:(void (^)())success
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
                          success:(void (^)())success
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
                                   success:(void (^)())success
                                   failure:(void (^)(NSError *error))failure NS_REFINED_FOR_SWIFT;
@end
