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

#import "MXJSONModels.h"
#import "MXEvent.h"

@implementation MXPublicRoom
- (NSString *)displayname
{
    NSString *displayname;
    if (self.aliases && 0 < self.aliases.count)
    {
        // TODO(same as in webclient code): select the smarter alias from the array
        displayname = self.aliases[0];
    }
    else
    {
        NSLog(@"Warning: room id leak for %@", self.roomId);
        displayname = self.roomId;
    }
    
    return displayname;
}
@end


NSString *const kMatrixLoginFlowTypePassword = @"m.login.password";
NSString *const kMatrixLoginFlowTypeOAuth2 = @"m.login.oauth2";
NSString *const kMatrixLoginFlowTypeTypeEmailCode = @"m.login.email.code";
NSString *const kMatrixLoginFlowTypeEmailUrl = @"m.login.email.url";
NSString *const kMatrixLoginFlowTypeEmailIdentity = @"m.login.email.identity";

@implementation MXLoginFlow
@end

@implementation MXCredentials
@end

@implementation MXCreateRoomResponse
@end

@implementation MXPaginationResponse

// Automatically convert array in chunk to an array of MXEvents.
+ (NSValueTransformer *)chunkJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
}

@end


NSString *const kMatrixPresenceOnline = @"online";
NSString *const kMatrixPresenceUnavailable = @"unavailable";
NSString *const kMatrixPresenceOffline = @"offline";
NSString *const kMatrixPresenceFreeForChat = @"free_for_chat";
NSString *const kMatrixPresenceHidden = @"hidden";

@implementation MXRoomMemberEventContent
@end

