// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import <MatrixSDK/MatrixSDK.h>

NS_ASSUME_NONNULL_BEGIN

/**
 This class describes a third party protocol instance.
 */
@interface MXThirdPartyProtocolInstance : MXJSONModel

/**
 The network identifier.
 */
@property (nonatomic) NSString *networkId;

/**
 The fields (domain...).
 */
@property (nonatomic) NSDictionary<NSString*, NSObject*> *fields;

/**
 The instance id.
 */
@property (nonatomic) NSString *instanceId;

/**
 The description.
 */
@property (nonatomic) NSString *desc;

/**
 The dedicated bot.
 */
@property (nonatomic) NSString *botUserId;

/**
 The icon URL.
 */
@property (nonatomic) NSString *icon;

@end

NS_ASSUME_NONNULL_END
