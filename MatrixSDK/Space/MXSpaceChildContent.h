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
#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

/// MXSpaceChildContent represents the state event content of space child event type (MXEventType.spaceChild).
@interface MXSpaceChildContent : MXJSONModel

/// Key which gives a list of candidate servers that can be used to join the room
/// Children where via is not present are ignored.
@property (nonatomic, strong, nullable) NSArray<NSString*>* via;

/// The order key is a string which is used to provide a default ordering of siblings in the room list.
/// (Rooms are sorted based on a lexicographic ordering of order values; rooms with no order come last.
/// orders which are not strings, or do not consist solely of ascii characters in the range \x20 (space) to \x7F (~),
/// or consist of more than 50 characters, are forbidden and should be ignored if received.)
@property (nonatomic, strong, nullable) NSString *order;

/// The auto_join flag on a child listing allows a space admin to list the sub-spaces and rooms in that space which should be automatically joined by members of that space.
/// (This is not a force-join, which are descoped for a future MSC; the user can subsequently part these room if they desire.)
/// `NO` by default.
@property (nonatomic) BOOL autoJoin;

/// If `suggested` is set to `true`, that indicates that the child should be advertised to members of the space by the client. This could be done by showing them eagerly in the room list.
/// This is should be ignored if `auto_join` is set to `true`.
/// `NO` by default.
@property (nonatomic) BOOL suggested;

@end

NS_ASSUME_NONNULL_END
