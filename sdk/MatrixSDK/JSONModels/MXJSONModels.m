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
#import "MXTools.h"

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


NSString *const kMXLoginFlowTypePassword = @"m.login.password";
NSString *const kMXLoginFlowTypeOAuth2 = @"m.login.oauth2";
NSString *const kMXLoginFlowTypeEmailCode = @"m.login.email.code";
NSString *const kMXLoginFlowTypeEmailUrl = @"m.login.email.url";
NSString *const kMXLoginFlowTypeEmailIdentity = @"m.login.email.identity";

@implementation MXLoginFlow
@end

@implementation MXCredentials

-(instancetype)initWithHomeServer:(NSString *)homeServer userId:(NSString *)userId accessToken:(NSString *)accessToken
{
    self = [super init];
    if (self)
    {
        _homeServer = [homeServer copy];
        _userId = [userId copy];
        _accessToken = [accessToken copy];
    }
    return self;
}

@end

@implementation MXCreateRoomResponse
@end

@implementation MXPaginationResponse

// Automatically convert array in chunk to an array of MXEvents.
+ (NSValueTransformer *)chunkJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXEvent.class];
}

@end


@implementation MXRoomMemberEventContent
@end


NSString *const kMXPresenceOnline = @"online";
NSString *const kMXPresenceUnavailable = @"unavailable";
NSString *const kMXPresenceOffline = @"offline";
NSString *const kMXPresenceFreeForChat = @"free_for_chat";
NSString *const kMXPresenceHidden = @"hidden";

@implementation MXPresenceEventContent

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        _presenceStatus = [MXTools presence:_presence];
    }

    return self;
}

@end


@implementation MXPresenceResponse

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        _presenceStatus = [MXTools presence:_presence];
    }

    return self;
}

@end


NSString *const kMXPushRuleActionStringNotify = @"notify";
NSString *const kMXPushRuleActionStringDontNotify = @"dont_notify";
NSString *const kMXPushRuleActionStringCoalesce = @"coalesce";
NSString *const kMXPushRuleActionStringSetTweak = @"set_tweak";

@implementation MXPushRule

+ (NSDictionary *)JSONKeyPathsByPropertyKey {

    // The home server use "default" as key name but `default` is a reserved word
    // in Objective C and cannot be used as a property name. So, it is replaced
    // by `isDefault` in the SDK.

    // Override the default JSON keys/ObjC properties mapping to match this change.
    NSMutableDictionary *JSONKeyPathsByPropertyKey = [NSMutableDictionary dictionaryWithDictionary:[super JSONKeyPathsByPropertyKey]];
    JSONKeyPathsByPropertyKey[@"isDefault"] = @"default";
    return JSONKeyPathsByPropertyKey;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self)
    {
        NSMutableArray *actions = [NSMutableArray arrayWithCapacity:_actions.count];

        for (NSUInteger i = 0; i < _actions.count; i++)
        {
            NSObject *rawAction = _actions[i];

            // According to the push rules specification
            // The action field can a string or dictionary, translate both into
            // a MXPushRuleAction object
            MXPushRuleAction *action = [[MXPushRuleAction alloc] init];

            if ([rawAction isKindOfClass:[NSString class]])
            {
                action.action = [rawAction copy];

                // If possible, map it to an action type
                if ([action.action isEqualToString:kMXPushRuleActionStringNotify])
                {
                    action.actionType = MXPushRuleActionTypeNotify;
                }
                else if ([action.action isEqualToString:kMXPushRuleActionStringDontNotify])
                {
                    action.actionType = MXPushRuleActionTypeDontNotify;
                }
                else if ([action.action isEqualToString:kMXPushRuleActionStringCoalesce])
                {
                    action.actionType = MXPushRuleActionTypeCoalesce;
                }
            }
            else if ([rawAction isKindOfClass:[NSDictionary class]])
            {
                action.parameters = (NSDictionary*)rawAction;

                // The
                if (NSNotFound != [action.parameters.allKeys indexOfObject:kMXPushRuleActionStringSetTweak])
                {
                    action.action = kMXPushRuleActionStringSetTweak;
                    action.actionType = MXPushRuleActionTypeSetTweak;
                }
            }

            [actions addObject:action];
        }

        _actions = actions;
    }

    return self;
}

@end

@implementation MXPushRuleAction

 - (instancetype)init
{
    self = [super init];
    if (self)
    {
        _actionType = MXPushRuleActionTypeCustom;
    }
    return self;
}

@end

@implementation MXPushRulesSet

+ (NSValueTransformer *)overrideJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)contentJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)roomJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)senderJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPushRule.class];
}

+ (NSValueTransformer *)underrideJSONTransformer {
    return [NSValueTransformer mtl_JSONArrayTransformerWithModelClass:MXPushRule.class];
}

@end

@implementation MXPushRulesResponse

/*
+ (NSValueTransformer *)deviceJSONTransformer {
    @TODO: This seems to be a dictionary where keys are profile_tag and values, MXPushRulesSet.
}
*/

+ (NSValueTransformer *)globalJSONTransformer {
    return [NSValueTransformer mtl_JSONDictionaryTransformerWithModelClass:MXPushRulesSet.class];
}

@end