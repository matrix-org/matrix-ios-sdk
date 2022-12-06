/*
 Copyright 2016 OpenMarket Ltd
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

#import "MXAccountData.h"

#import "MXJSONModel.h"
#import "MXRestClient.h"

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

@interface MXAccountData ()
{
    /**
     This dictionary stores "account_data" data in a flat manner.
     */
    NSMutableDictionary<NSString *, id> *accountDataDict;
}
@end

@implementation MXAccountData

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        accountDataDict = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithAccountData:(NSDictionary<NSString *,id> *)accountData
{
    self = [self init];
    if (self)
    {
        NSArray<NSDictionary<NSString *, id> *> *events;
        MXJSONModelSetArray(events, accountData[@"events"]);
        
        for (NSDictionary<NSString *, id> *event in events)
        {
            [self updateWithEvent:event];
        }
    }
    return self;
}

- (void)updateWithEvent:(NSDictionary<NSString *, id> *)event
{
    [self updateDataWithType:event[@"type"] data:event[@"content"]];
}

- (void)updateDataWithType:(NSString *)type data:(NSDictionary *)data
{
    accountDataDict[type] = data;
}

- (void)deleteDataWithType:(NSString *)type
{
    [accountDataDict removeObjectForKey:type];
}

- (NSDictionary *)accountDataForEventType:(NSString*)eventType
{
    return accountDataDict[eventType];
}

- (NSDictionary<NSString *,id> *)allAccountDataEvents
{
    return accountDataDict.copy;
}

- (NSDictionary<NSString *, id> *)accountData
{
    // Rebuild the dictionary as sent by the homeserver
    NSMutableArray<NSDictionary<NSString *, id> *> *events = [NSMutableArray array];
    for (NSString *type in accountDataDict)
    {
        [events addObject:@{
                            @"type": type,
                            @"content": accountDataDict[type]
                            }];
    }
    return @{@"events": events};
}

+ (NSString *)localNotificationSettingsKeyForDeviceWithId:(NSString*)deviceId
{
    return [kMXAccountDataLocalNotificationKeyPrefix stringByAppendingString:deviceId];
}

- (NSDictionary <NSString *, id>*)localNotificationSettingsForDeviceWithId:(NSString*)deviceId
{
    if (!deviceId)
    {
        return nil;
    }
    
    
    NSString *deviceNotificationKey = [MXAccountData localNotificationSettingsKeyForDeviceWithId:deviceId];
    NSDictionary <NSString *, id>*deviceNotificationSettings;
    MXJSONModelSetDictionary(deviceNotificationSettings, accountDataDict[deviceNotificationKey]);
    return deviceNotificationSettings;
}

@end
