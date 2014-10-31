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

#import "MXSession.h"

#import "MXRestClient.h"

#pragma mark - Constants definitions
NSString *const kMXRoomVisibilityPublic = @"public";
NSString *const kMXRoomVisibilityPrivate = @"private";


#pragma mark - MXSession
@interface MXSession ()
{
    MXRestClient *hsClient;
}
@end

@implementation MXSession
@synthesize homeserver, access_token;

-(id)initWithHomeServer:(NSString *)homeserver2 userId:(NSString *)userId accessToken:(NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        homeserver = homeserver2;
        _user_id = userId;
        access_token = accessToken;
        
        hsClient = [[MXRestClient alloc] initWithHomeServer:homeserver andAccessToken:access_token];
    }
    return self;
}

- (void)close
{
    //@TODO
}


#pragma mark - Room operations
- (void)postEvent:(NSString*)room_id
        eventType:(MXEventTypeString)eventTypeString
          content:(NSDictionary*)content
          success:(void (^)(NSString *event_id))success
          failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/send/%@", room_id, eventTypeString];
    [hsClient requestWithMethod:@"POST"
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

- (void)postMessage:(NSString*)room_id
            msgType:(MXMessageType)msgType
            content:(NSDictionary*)content
            success:(void (^)(NSString *event_id))success
            failure:(void (^)(NSError *error))failure
{
    // Add the messsage type to the data to send
    NSMutableDictionary *eventContent = [NSMutableDictionary dictionaryWithDictionary:content];
    eventContent[@"msgtype"] = msgType;
    
    [self postEvent:room_id eventType:kMXEventTypeStringRoomMessage content:eventContent success:success failure:failure];
}

- (void)postTextMessage:(NSString*)room_id
                   text:(NSString*)text
                success:(void (^)(NSString *event_id))success
                failure:(void (^)(NSError *error))failure
{
    [self postMessage:room_id msgType:kMXMessageTypeText
              content:@{
                        @"body": text
                        }
              success:success failure:failure];
}


// Generic methods to change membership
- (void)doMembershipRequest:(NSString*)room_id
                 membership:(NSString*)membership
                 parameters:(NSDictionary*)parameters
                    success:(void (^)())success
                    failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/%@", room_id, membership];
    
    // A body is required even if empty
    if (nil == parameters)
    {
        parameters = @{};
    }
    
    [hsClient requestWithMethod:@"POST"
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

- (void)joinRoom:(NSString*)room_id
     success:(void (^)())success
     failure:(void (^)(NSError *error))failure
{
    [self doMembershipRequest:room_id
                   membership:@"join"
                   parameters:nil
                      success:success failure:failure];
}

- (void)leaveRoom:(NSString*)room_id
      success:(void (^)())success
      failure:(void (^)(NSError *error))failure
{
    [self doMembershipRequest:room_id
                   membership:@"leave"
                   parameters:nil
                      success:success failure:failure];
}

- (void)inviteUser:(NSString*)user_id
            toRoom:(NSString*)room_id
           success:(void (^)())success
           failure:(void (^)(NSError *error))failure
{
    [self doMembershipRequest:room_id
                   membership:@"invite"
                   parameters:@{
                                @"user_id": user_id
                                }
                      success:success failure:failure];
}

- (void)kickUser:(NSString*)user_id
        fromRoom:(NSString*)room_id
          reason:(NSString*)reason
         success:(void (^)())success
         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/state/m.room.member/%@", room_id, user_id];
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[@"membership"] = @"leave";
    
    if (reason)
    {
        parameters[@"reason"] = reason;
    }
    
    [hsClient requestWithMethod:@"PUT"
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
         inRoom:(NSString*)room_id
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
    
    [self doMembershipRequest:room_id
                   membership:@"ban"
                   parameters:parameters
                      success:success failure:failure];
}

- (void)unbanUser:(NSString*)user_id
           inRoom:(NSString*)room_id
          success:(void (^)())success
          failure:(void (^)(NSError *error))failure
{
    // Do an unban by resetting the user membership to "leave"
    [self kickUser:user_id fromRoom:room_id reason:nil success:success failure:failure];
}

- (void)createRoom:(NSString*)name
        visibility:(MXRoomVisibility)visibility
   room_alias_name:(NSString*)room_alias_name
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
    if (room_alias_name)
    {
        parameters[@"room_alias_name"] = room_alias_name;
    }
    if (topic)
    {
        parameters[@"topic"] = topic;
    }
    
    [hsClient requestWithMethod:@"POST"
                           path:@"createRoom"
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         MXCreateRoomResponse *response = [MTLJSONAdapter modelOfClass:[MXCreateRoomResponse class]
                                                  fromJSONDictionary:JSONResponse
                                                               error:nil];
         success(response);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)messages:(NSString*)room_id
            from:(NSString*)from
              to:(NSString*)to
           limit:(NSUInteger)limit
         success:(void (^)(MXPaginationResponse *paginatedResponse))success
         failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/messages", room_id];
    
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
    
    [hsClient requestWithMethod:@"GET"
                           path:path
                     parameters:parameters
                        success:^(NSDictionary *JSONResponse)
     {
         MXPaginationResponse *paginatedResponse = [MTLJSONAdapter modelOfClass:[MXPaginationResponse class]
                                                             fromJSONDictionary:JSONResponse
                                                           error:nil];
         success(paginatedResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}

- (void)members:(NSString*)room_id
        success:(void (^)(NSArray *members))success
        failure:(void (^)(NSError *error))failure
{
    NSString *path = [NSString stringWithFormat:@"rooms/%@/members", room_id];

    [hsClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         NSMutableArray *members = [NSMutableArray array];
         
         for (NSDictionary *event in JSONResponse[@"chunk"])
         {
             MXRoomMember *roomMember = [MTLJSONAdapter modelOfClass:[MXRoomMember class]
                                                  fromJSONDictionary:event[@"content"]
                                                               error:nil];
             
             if (event[@"state_key"])
             {
                 roomMember.user_id = event[@"state_key"];
             }
             else
             {
                 roomMember.user_id = event[@"user_id"];
             }
             
             // Ignore banned and kicked (leave) user
             if ([roomMember.membership isEqualToString:@"ban"] || [roomMember.membership isEqualToString:@"leave"])
             {
                 continue;
             }
             
             [members addObject:roomMember];
         }
         
         success(members);
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
    NSString *path = [NSString stringWithFormat:@"profile/%@/displayname", _user_id];
    [hsClient requestWithMethod:@"PUT"
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

- (void)displayName:(NSString*)user_id
            success:(void (^)(NSString *displayname))success
            failure:(void (^)(NSError *error))failure
{
    if (!user_id)
    {
        user_id = _user_id;
    }
    
    NSString *path = [NSString stringWithFormat:@"profile/%@/displayname", user_id];
    [hsClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"displayname"]);
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
    NSString *path = [NSString stringWithFormat:@"profile/%@/avatar_url", _user_id];
    [hsClient requestWithMethod:@"PUT"
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

- (void)avatarUrl:(NSString*)user_id
          success:(void (^)(NSString *avatar_url))success
          failure:(void (^)(NSError *error))failure
{
    if (!user_id)
    {
        user_id = _user_id;
    }

    NSString *path = [NSString stringWithFormat:@"profile/%@/avatar_url", user_id];
    [hsClient requestWithMethod:@"GET"
                           path:path
                     parameters:nil
                        success:^(NSDictionary *JSONResponse)
     {
         success(JSONResponse[@"avatar_url"]);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Event operations
- (void)initialSync:(NSInteger)limit
           success:(void (^)(NSDictionary *))success
           failure:(void (^)(NSError *))failure
{
    [hsClient requestWithMethod:@"GET"
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

- (void)eventsFromToken:(NSString *)token
          serverTimeout:(NSUInteger)serverTimeout
          clientTimeout:(NSUInteger)clientTimeout
                success:(void (^)(NSDictionary *))success
                failure:(void (^)(NSError *))failure
{
    
    /*
     if (clientTimeout) {
     // If the Internet connection is lost, this timeout is used to be able to
     // cancel the current request and notify the client so that it can retry with a new request.
     $httpParams = {
     timeout: clientTimeout
     };
     }
     */
    
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
    
    [hsClient requestWithMethod:@"GET"
                           path:@"events"
                     parameters:parameters timeout:clientTimeoutInSeconds
                        success:^(NSDictionary *JSONResponse)
     {
         
         success(JSONResponse);
     }
                        failure:^(NSError *error)
     {
         failure(error);
     }];
}


#pragma mark - Directory operations
- (void)roomIDForRoomAlias:(NSString*)room_alias
                   success:(void (^)(NSString *room_id))success
                   failure:(void (^)(NSError *error))failure
{
    // Note: characters in a room alias need to be escaped in the URL
    NSString *path = [NSString stringWithFormat:@"directory/room/%@", [room_alias stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]];
    
    [hsClient requestWithMethod:@"GET"
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
    
    [hsClient requestWithMethod:@"POST"
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
          timeout:(NSTimeInterval)timeoutInSeconds
          success:(void (^)(NSDictionary *imageMessage))success
          failure:(void (^)(NSError *error))failure
{
    // TODO
}

@end
