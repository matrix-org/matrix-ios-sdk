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

/// MXRoomType identifies the type of room as decribed in MSC1840 (see https://github.com/matrix-org/matrix-doc/pull/1840).
typedef NS_ENUM(NSInteger, MXRoomType) {
    // The MXRoomTypeNone can be used when the value of the room type is nil or empty and you do not want to associate a room type for this case (See MXRoomSummaryUpdater.defaultRoomType).
    MXRoomTypeNone,
    MXRoomTypeRoom,
    MXRoomTypeSpace,
    MXRoomTypeVideo,
    // The room type is custom. Refer to the room type string version.
    MXRoomTypeCustom
};

/// MXRoomTypeString identifies the known room type string values
typedef NSString *const MXRoomTypeString NS_TYPED_EXTENSIBLE_ENUM;

static MXRoomTypeString const MXRoomTypeStringRoomMSC1840 = @"org.matrix.msc1840.messaging";
static MXRoomTypeString const MXRoomTypeStringRoom = @"m.message";
static MXRoomTypeString const MXRoomTypeStringSpace = @"m.space";
static MXRoomTypeString const MXRoomTypeStringVideo = @"io.element.video";
