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

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 `MXRoomLastMessage` is a model class to store some lastMessage properties for room summary objects.
 */
@interface MXRoomLastMessage : NSObject <NSCoding>

/**
 Event identifier of the last message.
 */
@property (nonatomic, copy, readonly) NSString *eventId;

/**
 Timestamp of the last message.
 */
@property (nonatomic, assign, readonly) uint64_t originServerTs;

- (instancetype)initWithEventId:(NSString *)eventId originServerTs:(uint64_t)originServerTs;

@end

NS_ASSUME_NONNULL_END
