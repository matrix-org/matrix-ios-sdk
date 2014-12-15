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

#import "MXRestClient.h"

#import "MXHTTPClient.h"
#import "MXJSONModel.h"
#import "MXTools.h"

#pragma mark - Constants definitions
NSString *const kMXRoomVisibilityPublic = @"public";
NSString *const kMXRoomVisibilityPrivate = @"private";


typedef enum
{
    MXAuthActionRegister,
    MXAuthActionLogin
}
MXAuthAction;


#pragma mark - MXRestClient
@interface MXRestClient ()
{
    MXHTTPClient *httpClient;
}
@end

@implementation MXRestClient
@synthesize homeserver, credentials;

-(id)initWithHomeServer:(NSString *)homeserver2
{
    self = [super init];
    if (self)
    {
        homeserver = homeserver2;
        
        httpClient = [[MXHTTPClient alloc] initWithHomeServer:homeserver andAccessToken:nil];
    }
    return self;
}

-(id)initWithCredentials:(MXCredentials*)credentials2
{
    self = [super init];
    if (self)
    {
        homeserver = credentials2.homeServer;
        credentials = credentials2;
        
        httpClient = [[MXHTTPClient alloc] initWithHomeServer:homeserver andAccessToken:credentials.accessToken];
    }
    return self;
}

- (void)close
{
    //@TODO
}


#pragma mark - Registration operations
- (void)getRegisterFlow:(void (^)(NSArray *flows))success
                failure:(void (^)(NSError *error))failure
{
    [self getRegisterOrLoginFlow:MXAuthActionRegister success:success failure:failure];
}

- (void)registerWithUser:(NSString*)user andPassword:(NSString*)password
                 success:(void (^)(MXCredentials *credentials))success
                 failure:(void (^)(NSError *error))failure
{
    [self registerOrLoginWithUser:MXAuthActionRegister user:user andPassword:password
                          success:success failure:failure];
}


#pragma mark - Login operations
- (void)getLoginFlow:(void (^)(NSArray *flows))success
             failure:(void (^)(NSError *error))failure
{
    [self getRegisterOrLoginFlow:MXAuthActionLogin success:success failure:failure];
}

- (void)loginWithUser:(NSString *)user andPassword:(NSString *)password
              success:(void (^)(MXCredentials *))success failure:(void (^)(NSError *))failure
{
    [self registerOrLoginWithUser:MXAuthActionLogin user:user andPassword:password
                          success:success failure:failure];
}


#pragma mark - Common operations for register and login
/*
 The only difference between register and login request are the path of the requests.
 The parameters and the responses are of the same types.
 So, use common functions to implement their functions.
 */

/**
 Return the home server path to use for register or for login actions.
 */
- (NSString*)authActionPath:(MXAuthAction)authAction
{
    NSString *authActionPath = @"register";
    if (MXAuthActionLogin == authAction)
    {
        authActionPath = @"login";
    }
    return authActionPath;
}

- (void)getRegisterOrLoginFlow:(MXAuthAction)authAction
                       success:(void (^)(NSArray *flows))success failure:(void (^)(NSError *error))failure
{
    [httpClient requestWithMethod:@"GET"
                             path:[self authActionPath:authAction]
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         NSArray *flows = [MXLoginFlow modelsFromJSON:JSONResponse[@"flows"]];
         success(flows);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)registerOrLoginWithUser:(MXAuthAction)authAction user:(NSString *)user andPassword:(NSString *)password
                        success:(void (^)(MXCredentials *))success failure:(void (^)(NSError *))failure
{
    NSDictionary *parameters = @{
                                 @"type": kMatrixLoginFlowTypePassword,
                                 @"user": user,
                                 @"password": password
                                 };
    
    [httpClient requestWithMethod:@"POST"
                             path:[self authActionPath:authAction]
                       parameters:parameters
                          success:^(NSDictionary *JSONResponse)
     {
         // Update our credentials
         credentials = [MXCredentials modelFromJSON:JSONResponse];
         
         // Workaround: HS does not return the right URL. Use the one we used to make the request
         credentials.homeServer = homeserver;
         
         success(credentials);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Room operations
- (void)postEventToRoom:(NSString*)roomId
              eventType:(MXEventTypeString)eventTypeString
                content:(NSDictionary*)content
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/send/%@", roomId, eventTypeString];
    [httpClient requestWithMethod:@"POST"
                           path:path
                     parameters:content
                        success:^(NSDictionary *JSONResponse)
     {
         
         success(JSONResponse[@"event_id"]);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)postMessageToRoom:(NSString*)roomId
                  msgType:(MXMessageType)msgType
                  content:(NSDictionary*)content
                  success:(void (^)(NSString *event_id))success
                  failure:(void (^)(NSError *error))failure
{
    // Add the messsage type to the data to send
    NSMutableDictionary *eventContent = [NSMutableDictionary dictionaryWithDictionary:content];
    eventContent[@"msgtype"] = msgType;
    
    [self postEventToRoom:roomId eventType:kMXEventTypeStringRoomMessage content:eventContent success:success failure:failure];
}

- (void)postTextMessageToRoom:(NSString*)roomId
                         text:(NSString*)text
                      success:(void (^)(NSString *event_id))success
                      failure:(void (^)(NSError *error))failure
{
    [self postMessageToRoom:roomId msgType:kMXMessageTypeText
              content:@{
                        @"body": text
                        }
              success:success failure:failure];
}


// Generic methods to change membership
- (void)doMembershipRequest:(NSString*)roomId
                 membership:(NSString*)membership
                 parameters:(NSDictionary*)parameters
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/%@", roomId, membership];
    
    // A body is required even if empty
    if (nil == parameters)
    {
        parameters = @{};
    }
    
    [httpClient requestWithMethod:@"POST"
                           path:path
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)setRoomTopic:(NSString*)roomId
               topic:(NSString*)topic
             success:(void (^)())success
             failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.topic", roomId];
    [httpClient requestWithMethod:@"PUT"
                             path:path
                       parameters:@{
                                    @"topic": topic
                                    }
                          success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)topicOfRoom:(NSString*)roomId
            success:(void (^)(NSString *topic))success
            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.topic", roomId];
    [httpClient requestWithMethod:@"GET"
                             path:path
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"topic"]);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)setRoomName:(NSString*)roomId
               name:(NSString*)name
            success:(void (^)())success
            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.name", roomId];
    [httpClient requestWithMethod:@"PUT"
                             path:path
                       parameters:@{
                                    @"name": name
                                    }
                          success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)nameOfRoom:(NSString*)roomId
           success:(void (^)(NSString *name))success
           failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.name", roomId];
    [httpClient requestWithMethod:@"GET"
                             path:path
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"name"]);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)joinRoom:(NSString*)roomIdOrAlias
     success:(void (^)(NSString *theRoomId))success
     failure:(void (^)(NSError *error))failure
{
    // Characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"join/%@", [roomIdOrAlias stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    [httpClient requestWithMethod:@"POST"
                             path:path
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"room_id"]);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)leaveRoom:(NSString*)roomId
      success:(void (^)())success
      failure:(void (^)(NSError *error))failure
{
    [self doMembershipRequest:roomId
                   membership:@"leave"
                   parameters:nil
                      success:success failure:failure];
}

- (void)inviteUser:(NSString*)user_id
            toRoom:(NSString*)roomId
           success:(void (^)())success
           failure:(void (^)(NSError *error))failure
{
    [self doMembershipRequest:roomId
                   membership:@"invite"
                   parameters:@{
                                @"user_id": user_id
                                }
                      success:success failure:failure];
}

- (void)kickUser:(NSString*)user_id
        fromRoom:(NSString*)roomId
          reason:(NSString*)reason
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.member/%@", roomId, user_id];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"membership"] = @"leave";
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    [httpClient requestWithMethod:@"PUT"
                           path:path
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)banUser:(NSString*)user_id
         inRoom:(NSString*)roomId
         reason:(NSString*)reason
        success:(void (^)())success
        failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"user_id"] = user_id;
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    [self doMembershipRequest:roomId
                   membership:@"ban"
                   parameters:parameters
                      success:success failure:failure];
}

- (void)unbanUser:(NSString*)user_id
           inRoom:(NSString*)roomId
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure
{
    // Do an unban by resetting the user membership to "leave"
    [self kickUser:user_id fromRoom:roomId reason:nil success:success failure:failure];
}

- (void)createRoom:(NSString*)name
        visibility:(MXRoomVisibility)visibility
         roomAlias:(NSString*)roomAlias
             topic:(NSString*)topic
           success:(void (^)(MXCreateRoomResponse *response))success
           failure:(void (^)(NSError *error))failure
{
    // All parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    if (name)
    {
        parameters[@"name"] = name;
    }
    if (visibility)
    {
        parameters[@"visibility"] = visibility;
    }
    if (roomAlias)
    {
        parameters[@"room_alias_name"] = roomAlias;
    }
    if (topic)
    {
        parameters[@"topic"] = topic;
    }
    
    [httpClient requestWithMethod:@"POST"
                           path:@"createRoom"
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         MXCreateRoomResponse *response = [MXCreateRoomResponse modelFromJSON:JSONResponse];
         success(response);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (NSOperation*)messagesForRoom:(NSString*)roomId
                           from:(NSString*)from
                             to:(NSString*)to
                          limit:(NSUInteger)limit
                        success:(void (^)(MXPaginationResponse *paginatedResponse))success
                        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/messages", roomId];
    
    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (from)
    {
        parameters[@"from"] = from;
    }
    if (to)
    {
        parameters[@"to"] = to;
    }
    if (-1 != limit)
    {
        parameters[@"limit"] = [NSNumber numberWithUnsignedInteger:limit];
    }
    
    // List messages in backward order to make the API answer
    parameters[@"dir"] = @"b";
    
    return [httpClient requestWithMethod:@"GET"
                           path:path
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         MXPaginationResponse *paginatedResponse = [MXPaginationResponse modelFromJSON:JSONResponse];
         success(paginatedResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)membersOfRoom:(NSString*)roomId
              success:(void (^)(NSArray *roomMemberEvents))success
              failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/members", roomId];

    [httpClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSMutableArray *roomMemberEvents = [NSMutableArray array];
         
         for (NSDictionary *event in JSONResponse[@"chunk"])
         {
             MXEvent *roomMemberEvent = [MXEvent modelFromJSON:event];
            [roomMemberEvents addObject:roomMemberEvent];
         }
         
         success(roomMemberEvents);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)stateOfRoom:(NSString*)roomId
            success:(void (^)(NSDictionary *JSONData))success
            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state", roomId];
    
    [httpClient requestWithMethod:@"GET"
                             path:path
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)initialSyncOfRoom:(NSString*)roomId
                withLimit:(NSInteger)limit
                  success:(void (^)(NSDictionary *JSONData))success
                  failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/initialSync", roomId];
    
    [httpClient requestWithMethod:@"GET"
                             path:path
                       parameters:@{
                                    @"limit": [NSNumber numberWithInteger:limit]
                                    }
                          success:^(NSDictionary *JSONResponse)
     {
         
         success(JSONResponse);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Profile operations
- (void)setDisplayName:(NSString*)displayname
               success:(void (^)())success
               failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"profile/%@/displayname", credentials.userId];
    [httpClient requestWithMethod:@"PUT"
                           path:path
                     parameters:@{
                                  @"displayname": displayname
                                  }
                        success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)displayNameForUser:(NSString*)user_id
                   success:(void (^)(NSString *displayname))success
                   failure:(void (^)(NSError *error))failure
{
    if (!user_id)
    {
        user_id = credentials.userId;
    }
    
    NSString *path = [NSString stringWithFormat:@"profile/%@/displayname", user_id];
    [httpClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
         success(cleanedJSONResponse[@"displayname"]);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)setAvatarUrl:(NSString*)avatar_url
             success:(void (^)())success
             failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"profile/%@/avatar_url", credentials.userId];
    [httpClient requestWithMethod:@"PUT"
                           path:path
                     parameters:@{
                                  @"avatar_url": avatar_url
                                  }
                        success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)avatarUrlForUser:(NSString*)user_id
                 success:(void (^)(NSString *avatar_url))success
                 failure:(void (^)(NSError *error))failure
{
    if (!user_id)
    {
        user_id = credentials.userId;
    }

    NSString *path = [NSString stringWithFormat:@"profile/%@/avatar_url", user_id];
    [httpClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSDictionary *cleanedJSONResponse = [MXJSONModel removeNullValuesInJSON:JSONResponse];
         success(cleanedJSONResponse[@"avatar_url"]);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Presence operations
- (void)setPresence:(MXPresence)presence andStatusMessage:(NSString*)statusMessage
            success:(void (^)())success
            failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"presence/%@/status", credentials.userId];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"presence"] = [MXTools presenceString:presence];
    if (statusMessage)
    {
        parameters[@"status_msg"] = statusMessage;
    }
    
    [httpClient requestWithMethod:@"PUT"
                             path:path
                       parameters:parameters
                          success:^(NSDictionary *JSONResponse)
     {
         success();
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)presence:(NSString*)user_id
         success:(void (^)(MXPresenceResponse *presence))success
         failure:(void (^)(NSError *error))failure
{
    if (!user_id)
    {
        user_id = credentials.userId;
    }
    
    NSString *path = [NSString stringWithFormat:@"presence/%@/status", user_id];
    [httpClient requestWithMethod:@"GET"
                             path:path
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         MXPresenceResponse *presence = [MXPresenceResponse modelFromJSON:JSONResponse];
         success(presence);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Event operations
- (void)initialSyncWithLimit:(NSInteger)limit
                     success:(void (^)(NSDictionary *))success
                     failure:(void (^)(NSError *))failure
{
    [httpClient requestWithMethod:@"GET"
                           path:@"initialSync"
                     parameters:@{
                                  @"limit": [NSNumber numberWithInteger:limit]
                                  }
                        success:^(NSDictionary *JSONResponse)
     {
         
         success(JSONResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (NSOperation *)eventsFromToken:(NSString*)token
          serverTimeout:(NSUInteger)serverTimeout
          clientTimeout:(NSUInteger)clientTimeout
                success:(void (^)(MXPaginationResponse *paginatedResponse))success
                failure:(void (^)(NSError *error))failure
{

    // All query parameters are optional. Fill the request parameters on demand
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    if (token)
    {
        parameters[@"from"] = token;
    }
    if (-1 != serverTimeout)
    {
        parameters[@"timeout"] = [NSNumber numberWithInteger:serverTimeout];
    }
    
    NSTimeInterval clientTimeoutInSeconds = clientTimeout;
    if (-1 != clientTimeoutInSeconds)
    {
        // If the Internet connection is lost, this timeout is used to be able to
        // cancel the current request and notify the client so that it can retry with a new request.
        clientTimeoutInSeconds = clientTimeoutInSeconds / 1000;
    }
    
    return [httpClient requestWithMethod:@"GET"
                           path:@"events"
                     parameters:parameters timeout:clientTimeoutInSeconds
                        success:^(NSDictionary *JSONResponse)
     {
         MXPaginationResponse *paginatedResponse = [MXPaginationResponse modelFromJSON:JSONResponse];
         success(paginatedResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)publicRooms:(void (^)(NSArray *rooms))success
            failure:(void (^)(NSError *error))failure
{
    [httpClient requestWithMethod:@"GET"
                             path:@"publicRooms"
                       parameters:nil
                          success:^(NSDictionary *JSONResponse)
     {
         NSArray *publicRooms = [MXPublicRoom modelsFromJSON:JSONResponse[@"chunk"]];
         success(publicRooms);
     }
                          failure:^(NSError *error)
     {
         failure(error);
     }];
}

#pragma mark - Directory operations
- (void)roomIDForRoomAlias:(NSString*)room_alias
                   success:(void (^)(NSString *roomId))success
                   failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"directory/room/%@", [room_alias stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    
    [httpClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"room_id"]);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Content upload
- (void)uploadContent:(NSData *)data
             mimeType:(NSString *)mimeType
              timeout:(NSTimeInterval)timeoutInSeconds
              success:(void (^)(NSString *url))success
              failure:(void (^)(NSError *error))failure
{
    NSString* path = @"/_matrix/content";
    NSDictionary *headers = @{@"Content-Type": mimeType};
    
    [httpClient requestWithMethod:@"POST"
                           path:path
                     parameters:nil
                           data:data
                        headers:headers
                        timeout:timeoutInSeconds
                        success:^(NSDictionary *JSONResponse) {
                            NSString *contentURL = JSONResponse[@"content_token"];
                            NSLog(@"uploadContent succeeded: %@",contentURL);
                            success(contentURL);
                        }
                        failure:failure];
}

- (void)uploadImage:(UIImage *)image
      thumbnailSize:(NSUInteger)thumbnailSize
            timeout:(NSTimeInterval)timeoutInSeconds
            success:(void (^)(NSDictionary *imageMessage))success
            failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *imageMessage = [[NSMutableDictionary alloc] init];
    [imageMessage setValue:@"m.image" forKey:@"msgtype"];
    UIImage *thumbnail = nil;
    
    // Check whether a thumbnail is required
    if (thumbnailSize && (image.size.width > thumbnailSize || image.size.height > thumbnailSize)) {
        CGFloat width, height;
        if (image.size.width > image.size.height) {
            height = (image.size.height * thumbnailSize) / image.size.width;
            height = floorf(height / 2) * 2;
            width = thumbnailSize;
        } else {
            width = (image.size.width * thumbnailSize) / image.size.height;
            width = floorf(width / 2) * 2;
            height = thumbnailSize;
        }
        
        // Create the thumbnail
        CGSize imageSize = CGSizeMake(width, height);
        UIGraphicsBeginImageContext(imageSize);
        
        CGRect thumbnailRect = CGRectMake(0, 0, 0, 0);
        thumbnailRect.origin = CGPointMake(0.0,0.0);
        thumbnailRect.size.width  = imageSize.width;
        thumbnailRect.size.height = imageSize.height;
        
        [image drawInRect:thumbnailRect];
        thumbnail = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    if (thumbnail) {
        // Upload thumbnail
        NSMutableDictionary *thumbnailInfo = [[NSMutableDictionary alloc] init];
        [thumbnailInfo setValue:@"image/jpeg" forKey:@"mimetype"];
        [thumbnailInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)thumbnail.size.width] forKey:@"w"];
        [thumbnailInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)thumbnail.size.height] forKey:@"h"];
        NSData *thumbnailData = UIImageJPEGRepresentation(thumbnail, 0.9);
        [thumbnailInfo setValue:[NSNumber numberWithUnsignedInteger:thumbnailData.length] forKey:@"size"];
        
        [self uploadContent:thumbnailData mimeType:@"image/jpeg" timeout:timeoutInSeconds success:^(NSString *url) {
            [imageMessage setValue:url forKey:@"thumbnail_url"];
            [imageMessage setValue:thumbnailInfo forKey:@"thumbnail_info"];
            
            // Upload the original image
            [self finalizeImageUpload:image thumbnailInfo:imageMessage timeout:timeoutInSeconds success:success failure:failure];
        } failure:^(NSError *error) {
            failure(error);
        }];
    } else {
        // Upload the original image
        [self finalizeImageUpload:image thumbnailInfo:imageMessage timeout:timeoutInSeconds success:success failure:failure];
    }
}

- (void)finalizeImageUpload:(UIImage *)image
              thumbnailInfo:(NSMutableDictionary *)imageMessage
                    timeout:(NSTimeInterval)timeoutInSeconds
                    success:(void (^)(NSDictionary *imageMessage))success
                    failure:(void (^)(NSError *error))failure
{
    NSMutableDictionary *imageInfo = [[NSMutableDictionary alloc] init];
    [imageInfo setValue:@"image/jpeg" forKey:@"mimetype"];
    [imageInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)image.size.width] forKey:@"w"];
    [imageInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)image.size.height] forKey:@"h"];
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
    [imageInfo setValue:[NSNumber numberWithUnsignedInteger:imageData.length] forKey:@"size"];
    
    [self uploadContent:imageData mimeType:@"image/jpeg" timeout:timeoutInSeconds success:^(NSString *url) {
        [imageMessage setValue:url forKey:@"url"];
        [imageMessage setValue:imageInfo forKey:@"info"];
        [imageMessage setValue:@"Image" forKey:@"body"];
        // If there is no thumbnail (because the original image is smaller than thumbnailSize),
        // reuse the original image info for thumbnail data
        if (!imageMessage[@"thumbnail_url"]) {
            [imageInfo setValue:imageInfo forKey:@"thumbnail_info"];
            [imageInfo setValue:url forKey:@"thumbnail_url"];
        }
        success(imageMessage);
    } failure:^(NSError *error) {
        failure(error);
    }];
}
@end
