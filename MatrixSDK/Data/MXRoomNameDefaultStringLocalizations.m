/*
 Copyright 2018 New Vector Ltd

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

#import "MXRoomNameDefaultStringLocalizations.h"

@interface MXRoomNameDefaultStringLocalizations ()

@property (nonatomic, copy) NSString *emptyRoom;
@property (nonatomic, copy) NSString *twoMembers;
@property (nonatomic, copy) NSString *moreThanTwoMembers;
@property (nonatomic, copy) NSString *allOtherParticipantsLeft;

@end

@implementation MXRoomNameDefaultStringLocalizations

- (instancetype)init
{
    if (self == [super init])
    {
        _emptyRoom = @"Empty room";
        _twoMembers = @"%@ and %@";
        _moreThanTwoMembers = @"%@ & %@ others";
        _allOtherParticipantsLeft = @"%@ (Left)";
        
    }
    return self;
}

@end
