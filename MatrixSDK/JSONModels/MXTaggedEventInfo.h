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

#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXTaggedEventInfo : MXJSONModel

@property (nonatomic, nullable) NSArray<NSString*> *keywords;

/**
 The origin server timestamp in milliseconds.
*/
@property (nonatomic) uint64_t originServerTs;

/**
 The timestamp in milliseconds when this tag has been created.
*/
@property (nonatomic) uint64_t taggedAt;

@end

NS_ASSUME_NONNULL_END
