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

#import "MXCallEventContent.h"

NS_ASSUME_NONNULL_BEGIN

@class MXAssertedIdentityModel;

/**
 `MXCallAssertedIdentityEventContent` represents the content of an `m.call.asserted_identity` event.
 */
@interface MXCallAssertedIdentityEventContent : MXCallEventContent

/**
 An object giving information about the transfer target.
 */
@property (nonatomic, nullable) MXAssertedIdentityModel *assertedIdentity;


@end

NS_ASSUME_NONNULL_END
