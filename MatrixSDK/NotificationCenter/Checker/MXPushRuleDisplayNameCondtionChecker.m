/*
 Copyright 2015 OpenMarket Ltd
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

#import "MXPushRuleDisplayNameCondtionChecker.h"

#import "MXSession.h"

@interface MXPushRuleDisplayNameCondtionChecker ()
{
    MXSession *mxSession;
    
    /**
     Regex for finding the user's display name in events content.
     */
    NSRegularExpression *userNameRegex;
    
    /**
     The user display name used to build the regex.
     */
    NSString *currentUserName;
}

@end

@implementation MXPushRuleDisplayNameCondtionChecker

- (instancetype)initWithMatrixSession:(MXSession *)mxSession2
               currentUserDisplayName:(NSString* _Nullable)currentUserDisplayName
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
        currentUserName = currentUserDisplayName;
    }
    return self;
}

- (BOOL)isCondition:(MXPushRuleCondition*)condition satisfiedBy:(MXEvent*)event roomState:(MXRoomState*)roomState withJsonDict:(NSDictionary*)contentAsJsonDict
{
    BOOL isSatisfied = NO;
    
    NSString *displayName = currentUserName;
    
    if (!displayName)
    {
        displayName = mxSession.myUser.displayname;
    }

    // If it exists, search for the current display name in the content body with case insensitive
    if (displayName && event.content)
    {
        NSObject* bodyAsVoid;
        MXJSONModelSet(bodyAsVoid, NSObject.class, event.content[kMXMessageBodyKey]);
        
        if (bodyAsVoid && [bodyAsVoid isKindOfClass:[NSString class]])
        {
            NSString *body = (NSString*)bodyAsVoid;
            
            if (body)
            {
                if (!userNameRegex || ![currentUserName isEqualToString:displayName])
                {
                    userNameRegex = [NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"(^|\\W)\\Q%@\\E($|\\W)", displayName] options:NSRegularExpressionCaseInsensitive error:nil];
                    currentUserName = displayName;
                }

                NSRange range = [userNameRegex rangeOfFirstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
                if (range.length)
                {
                    isSatisfied = YES;
                }
            }
        }
    }
    return isSatisfied;
}

@end
