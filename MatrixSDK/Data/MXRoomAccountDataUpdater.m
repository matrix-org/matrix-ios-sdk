// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "MXRoomAccountDataUpdater.h"

#import "MXTools.h"
#import "MXSession.h"
#import "MXRoom.h"

@implementation MXRoomAccountDataUpdater

+ (instancetype)roomAccountDataUpdaterForSession:(MXSession *)mxSession
{
    static NSMapTable<MXSession*, MXRoomAccountDataUpdater*> *updaterPerSession;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        updaterPerSession = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsWeakMemory
                                                      valueOptions:NSPointerFunctionsWeakMemory
                                                          capacity:1];
    });

    MXRoomAccountDataUpdater *updater = [updaterPerSession objectForKey:mxSession];
    if (!updater)
    {
        updater = [[MXRoomAccountDataUpdater alloc] init];
        [updaterPerSession setObject:updater forKey:mxSession];
    }

    return updater;
}

#pragma mark - MXRoomAccountDataUpdating

- (void)updateAccountDataForRoom:(MXRoom *)room withStateEvents:(NSArray<MXEvent *> *)stateEvents
{
    for (MXEvent *event in stateEvents)
    {
        switch (event.eventType)
        {
            case MXEventTypeRoomCreate:
            {
                MXRoomCreateContent *createContent = [MXRoomCreateContent modelFromJSON:event.content];
                
                if (createContent.virtualRoomInfo.isVirtual && [room.summary.creatorUserId isEqualToString:event.sender])
                {
                    [self updateAccountDataIfRequiredForRoom:room
                                            withNativeRoomId:createContent.virtualRoomInfo.nativeRoomId
                                                  completion:nil];
                }
            }
                break;
            default:
                break;
        }
    }
}

- (void)updateAccountDataIfRequiredForRoom:(MXRoom *)room withNativeRoomId:(NSString *)nativeRoomId completion:(void(^)(BOOL, NSError *))completion
{
    //  set account data on the room, if required
    //  room may be created earlier for a different native room which was left. So check the native room id.
    if ([room.accountData.virtualRoomInfo.nativeRoomId isEqualToString:nativeRoomId] && room.summary.hiddenFromUser)
    {
        //  no need to set the account data
        if (completion)
        {
            completion(YES, nil);
        }
        return;
    }
    else
    {
        //  we need to set the account data
        MXWeakify(room);
        [room setAccountData:@{
            kRoomNativeRoomIdJSONKey: nativeRoomId
        } forType:kRoomIsVirtualJSONKey success:^{
            MXStrongifyAndReturnIfNil(room);
            
            //  trigger a room summary update
            MXEvent *event = [MXEvent modelFromJSON:@{
                @"type": kRoomIsVirtualJSONKey,
                @"content": @{
                        kRoomNativeRoomIdJSONKey: nativeRoomId
                }
            }];
            [room.summary handleEvent:event];
            
            [room.mxSession setVirtualRoom:room.roomId forNativeRoom:nativeRoomId];
            if (completion)
            {
                completion(YES, nil);
            }
        } failure:^(NSError *error) {
            if (completion)
            {
                completion(NO, error);
            }
        }];
    }
}

@end
