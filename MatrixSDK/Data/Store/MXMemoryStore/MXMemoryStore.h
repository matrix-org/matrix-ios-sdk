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

#import "MXStore.h"

#import "MXMemoryRoomStore.h"

#import <OLMKit/OLMKit.h>

#import "MXUsersDevicesMap.h"
#import "MXDeviceInfo.h"

/**
 `MXMemoryStore` is an implementation of the `MXStore` interface that stores events in memory.
 */
@interface MXMemoryStore : NSObject <MXStore>
{
    @protected
    NSMutableDictionary *roomStores;

    // All matrix users known by the user
    // The keys are user ids.
    NSMutableDictionary <NSString*, MXUser*> *users;

    // Dict of dict of MXReceiptData indexed by userId
    NSMutableDictionary *receiptsByRoomId;

    // The user credentials
    MXCredentials *credentials;

    // Crypto
    // The olm account
    OLMAccount *olmAccount;

    // All users devices keys
    MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap;

    // The algorithms used in rooms
    NSMutableDictionary<NSString*, NSString*> *roomsAlgorithms;

    // The olm sessions (<device identity key> -> (<olm session id> -> <olm session>)
    NSMutableDictionary<NSString* /*deviceKey*/,
        NSMutableDictionary<NSString * /*olmSessionId*/,OLMSession *>*> *olmSessions;

    // The inbound group megolm sessions (<senderKey> -> (<inbound group session id> -> <inbound group megolm session>)
    NSMutableDictionary<NSString* /*senderKey*/,
        NSMutableDictionary<NSString * /*inboundGroupSessionId*/,MXOlmInboundGroupSession *>*> *inboundGroupSessions;
}

#pragma mark - protected operations

/**
 Interface to create or retrieve a MXMemoryRoomStore type object.
 
 @param roomId the id for the MXMemoryRoomStore object.
 @return the MXMemoryRoomStore instance.
 */
- (MXMemoryRoomStore*)getOrCreateRoomStore:(NSString*)roomId;

@end
