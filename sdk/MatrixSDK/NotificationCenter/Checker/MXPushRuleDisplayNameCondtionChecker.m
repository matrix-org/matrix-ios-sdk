/*
 Copyright 2015 OpenMarket Ltd

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
}

@end

@implementation MXPushRuleDisplayNameCondtionChecker

- (instancetype)initWithMatrixSession:(MXSession *)mxSession2
{
    self = [super init];
    if (self)
    {
        mxSession = mxSession2;
    }
    return self;
}

- (BOOL)isCondition:(MXPushRuleCondition *)condition satisfiedBy:(MXEvent *)event
{
    BOOL isSatisfied = NO;

    // If it exists, search for the current display name in the content body with case insensitive
    if (mxSession.myUser.displayname && event.content)
    {
        NSString *body = event.content[@"body"];
        if (body)
        {
            if (NSNotFound != [body rangeOfString:mxSession.myUser.displayname options:NSCaseInsensitiveSearch].location)
            {
                isSatisfied = YES;
            }
        }
    }
    return isSatisfied;
}

@end
