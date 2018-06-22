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

#import <Realm/Realm.h>

#pragma mark - Defines & Constants

extern const struct MXRealmReceiptAttributes {
    __unsafe_unretained NSString *eventId;
    __unsafe_unretained NSString *userId;
    __unsafe_unretained NSString *roomId;
    __unsafe_unretained NSString *timestamp;
} MXRealmReceiptAttributes;

#pragma mark - Interface

/**
 `MXRealmReceipt` is a Realm entity for a read receipt.
 */
@interface MXRealmReceipt : RLMObject

@property NSString *eventId;
@property NSString *userId;
@property NSString *roomId;
@property double timestamp; // in millisecond

@end
