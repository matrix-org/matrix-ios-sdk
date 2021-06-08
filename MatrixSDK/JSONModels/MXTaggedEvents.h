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

#import "MXTaggedEventInfo.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Room tags defined by Matrix spec.
 */
FOUNDATION_EXPORT NSString *const kMXTaggedEventFavourite;
FOUNDATION_EXPORT NSString *const kMXTaggedEventHidden;

@interface MXTaggedEvents : MXJSONModel

/**
 The event tags.
 */
@property (nonatomic) NSDictionary<NSString*, NSDictionary<NSString*, NSDictionary*>* > *tags;

- (void)tagEvent:(NSString *)eventId taggedEventInfo:(MXTaggedEventInfo *)info tag:(NSString *)tag;
- (void)untagEvent:(NSString *)eventId tag:(NSString *)tag;

@end

NS_ASSUME_NONNULL_END
