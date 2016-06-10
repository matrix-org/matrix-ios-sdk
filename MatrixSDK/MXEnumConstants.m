/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXEnumConstants.h"

/**
 Room visibility
 */
NSString *const kMXRoomVisibilityPublic  = @"public";
NSString *const kMXRoomVisibilityPrivate = @"private";

/**
 Room history visibility.
 */
NSString *const kMXRoomHistoryVisibilityWorldReadable= @"world_readable";
NSString *const kMXRoomHistoryVisibilityShared       = @"shared";
NSString *const kMXRoomHistoryVisibilityInvited      = @"invited";
NSString *const kMXRoomHistoryVisibilityJoined       = @"joined";

/**
 Room join rule.
 */
NSString *const kMXRoomJoinRulePublic  = @"public";
NSString *const kMXRoomJoinRuleInvite  = @"invite";
NSString *const kMXRoomJoinRulePrivate = @"private";
NSString *const kMXRoomJoinRuleKnock   = @"knock";

/**
 Room guest access.
 */
NSString *const kMXRoomGuestAccessCanJoin   = @"can_join";
NSString *const kMXRoomGuestAccessForbidden = @"forbidden";
