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

#import "MXCallManager.h"

#import "MXSession.h"

#pragma mark - Constants definitions
NSString *const kMXCallManagerDidReceiveCallInvite = @"kMXCallManagerDidReceiveCallInvite";


@interface MXCallManager ()
{
    /**
     Calls being handled.
     */
    NSMutableArray *calls;

    id callInviteListener;
}

@end


@implementation MXCallManager

- (instancetype)initWithMatrixSession:(MXSession *)mxSession
{
    self = [super init];
    if (self)
    {
        /*
        calls = [NSMutableArray array];

        conditionCheckers = [NSMutableDictionary dictionary];

        // Define condition checkers for default Matrix conditions
        eventMatchConditionChecker = [[MXPushRuleEventMatchConditionChecker alloc] init];
        [self setChecker:eventMatchConditionChecker forConditionKind:kMXPushRuleConditionStringEventMatch];

        MXPushRuleDisplayNameCondtionChecker *displayNameCondtionChecker = [[MXPushRuleDisplayNameCondtionChecker alloc] initWithMatrixSession:mxSession];
        [self setChecker:displayNameCondtionChecker forConditionKind:kMXPushRuleConditionStringContainsDisplayName];

        MXPushRuleRoomMemberCountConditionChecker *roomMemberCountConditionChecker = [[MXPushRuleRoomMemberCountConditionChecker alloc] initWithMatrixSession:mxSession];
        [self setChecker:roomMemberCountConditionChecker forConditionKind:kMXPushRuleConditionStringRoomMemberCount];
         
         */

        _mxSession = mxSession;

        // Lister for incoming calls
        callInviteListener = [mxSession listenToEventsOfTypes:@[kMXEventTypeStringCallInvite] onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {

            if (MXEventDirectionForwards == direction)
            {
                [self handleCallInvite:event];
            }

        }];
    }
    return self;
}

- (void)close
{
    // @TODO: Hang up current call

    [_mxSession removeListener:callInviteListener];
    callInviteListener = nil;
}


#pragma mark - Private methods
- (void)handleCallInvite:(MXEvent*)event
{
    MXCall *call = [[MXCall alloc] initWithEvent:event andCallManager:self];

    [calls addObject:call];

    // Broadcast the information
    [[NSNotificationCenter defaultCenter] postNotificationName:kMXCallManagerDidReceiveCallInvite object:call userInfo:nil];
}

@end
