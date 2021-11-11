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

import Foundation

/// MXSpaceChildrenSummary represents the wrapped result of the space API from MXSpaceService.
@objcMembers
public class MXSpaceChildrenSummary: NSObject {
    
    // MARK - Properties
    
    /// The queried space room summary. Can be nil in case of batched request
    public let spaceInfo: MXSpaceChildInfo?
    
    /// The child summaries of the queried space
    public let childInfos: [MXSpaceChildInfo]
    
    /// The token to supply in the `from` param of the next request in order to request more rooms. If this is absent, there are no more results.
    public let nextBatch: String?
    
    // MARK - Setup
    
    init(spaceInfo: MXSpaceChildInfo?, childInfos: [MXSpaceChildInfo], nextBatch: String?) {
        self.spaceInfo = spaceInfo
        self.childInfos = childInfos
        self.nextBatch = nextBatch
    }
}
