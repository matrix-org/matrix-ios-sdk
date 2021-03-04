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
typedef NSString *const MXRoomType NS_TYPED_EXTENSIBLE_ENUM;

static MXRoomType const MXRoomTypeRoomMSC1840 = @"org.matrix.msc1840.messaging";
static MXRoomType const MXRoomTypeRoom = @"m.message";
static MXRoomType const MXRoomTypeSpaceMSC1772 = @"org.matrix.msc1772.space";
static MXRoomType const MXRoomTypeSpace = @"m.space";
