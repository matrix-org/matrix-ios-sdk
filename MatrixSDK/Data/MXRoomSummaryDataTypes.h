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

#ifndef MXRoomSummaryDataTypes_h
#define MXRoomSummaryDataTypes_h

typedef NS_OPTIONS(NSInteger, MXRoomSummaryDataTypes)
{
    MXRoomSummaryDataTypesInvited = 1 << 0,
    MXRoomSummaryDataTypesFavorited = 1 << 1,
    MXRoomSummaryDataTypesDirect = 1 << 2,
    MXRoomSummaryDataTypesLowPriority = 1 << 3,
    MXRoomSummaryDataTypesServerNotice = 1 << 4,
    MXRoomSummaryDataTypesHidden = 1 << 5,
    MXRoomSummaryDataTypesSpace = 1 << 6,
    MXRoomSummaryDataTypesConferenceUser = 1 << 7,
    MXRoomSummaryDataTypesUnread = 1 << 8
};

#endif /* MXRoomSummaryDataTypes_h */
