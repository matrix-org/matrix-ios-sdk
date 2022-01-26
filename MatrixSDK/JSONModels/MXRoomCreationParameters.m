/*
 Copyright 2020 The Matrix.org Foundation C.I.C

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


#import "MXRoomCreationParameters.h"
#import "MXRoomCreateContent.h"
#import "MatrixSDKSwiftHeader.h"

@implementation MXRoomCreationParameters

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _isDirect = NO;
    }
    return self;
}

- (NSDictionary*)JSONDictionary
{
    NSMutableDictionary *dictionary = [@{
                                         @"is_direct": [NSNumber numberWithBool:_isDirect]
                                         } mutableCopy];

    NSMutableDictionary *createContentDictionary;
    
    if (_creationContent)
    {
        createContentDictionary = [_creationContent mutableCopy];
    }
    else
    {
        createContentDictionary = [NSMutableDictionary new];
    }    
    if (_roomType)
    {
        createContentDictionary[MXRoomCreateContentRoomTypeJSONKey] = _roomType;
    }
    if (_name)
    {
        dictionary[@"name"] = _name;
    }
    if (_visibility)
    {
        dictionary[@"visibility"] = _visibility;
    }
    if (_roomAlias)
    {
        dictionary[@"room_alias_name"] = _roomAlias;
    }
    if (_topic)
    {
        dictionary[@"topic"] = _topic;
    }
    if (_inviteArray)
    {
        dictionary[@"invite"] = _inviteArray;
    }
    if (_invite3PIDArray)
    {
        NSMutableArray *invite3PIDArray2 = [NSMutableArray arrayWithCapacity:_invite3PIDArray.count];
        for (MXInvite3PID *invite3PID in _invite3PIDArray)
        {
            if (invite3PID.dictionary)
            {
                [invite3PIDArray2 addObject:invite3PID.dictionary];
            }
        }

        if (invite3PIDArray2.count)
        {
            dictionary[@"invite_3pid"] = invite3PIDArray2;
        }
    }
    if (_preset)
    {
        dictionary[@"preset"] = _preset;
    }
    if (_initialStateEvents)
    {
        dictionary[@"initial_state"] = _initialStateEvents;
    }
    if (createContentDictionary.count)
    {
        dictionary[@"creation_content"] = createContentDictionary;
    }
    if (_powerLevelContentOverride)
    {
        dictionary[@"power_level_content_override"] = [_powerLevelContentOverride JSONDictionary];
    }
    if (_roomVersion)
    {
        dictionary[@"room_version"] = _roomVersion;
    }
    
    return dictionary;
}

- (void)addOrUpdateInitialStateEvent:(NSDictionary*)stateEvent
{
    if (!self.initialStateEvents)
    {
        self.initialStateEvents = @[];
    }
    
    NSString *stateEventTypeString;
    
    MXJSONModelSetString(stateEventTypeString, stateEvent[@"type"]);
    
    if (!stateEventTypeString)
    {
        return;
    }
    
    NSInteger existingStateEventIndex = [self indexForStateEventTypeString:stateEventTypeString];
    
    NSMutableArray *initialStateEvents = [self.initialStateEvents mutableCopy];
    
    if (existingStateEventIndex != NSNotFound)
    {
        initialStateEvents[existingStateEventIndex] = stateEvent;
    }
    else
    {
        [initialStateEvents addObject:stateEvent];
    }
    
    self.initialStateEvents = initialStateEvents;
}

#pragma mark - Private

- (NSInteger)indexForStateEventTypeString:(NSString*)eventTypeString
{
    return [self.initialStateEvents indexOfObjectPassingTest:^BOOL(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([obj[@"type"] isEqualToString:eventTypeString])
        {
            *stop = YES;
            return YES;
        }
        return NO;
    }];
}

#pragma mark - Factory

+ (instancetype)parametersForDirectRoomWithUser:(NSString*)userId
{
    MXRoomCreationParameters *roomCreationParameters = [MXRoomCreationParameters new];
    roomCreationParameters.inviteArray = @[userId];
    roomCreationParameters.isDirect = YES;
    roomCreationParameters.preset = kMXRoomPresetTrustedPrivateChat;

    return roomCreationParameters;
}

+ (NSDictionary *)initialStateEventForEncryptionWithAlgorithm:(NSString *)algorithm
{
    // Do not break the API for the moment
    MXRoomInitialStateEventBuilder *stateEventBuilder = [MXRoomInitialStateEventBuilder new];
    return [stateEventBuilder buildAlgorithmEventWithAlgorithm:algorithm];
}

+ (NSDictionary *)creationContentForVirtualRoomWithNativeRoomId:(NSString *)roomId
{
    return @{
        kRoomIsVirtualJSONKey: @{
                kRoomNativeRoomIdJSONKey : roomId
        }
    };
}

@end
