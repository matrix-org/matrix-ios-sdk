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

class Poll {
    enum Kind {
        case disclosed
        case undisclosed
    }
    
    class AnswerOption {
        var id: String!
        var text: String!
        
        var count: UInt = 0
        var isWinner: Bool = false
        var isCurrentUserSelection: Bool = false
        
        init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }
    
    var text: String!
    var answerOptions: [AnswerOption]!
    
    var kind: Kind = .disclosed
    var maxAllowedSelections: UInt = 1
    var isClosed: Bool = false
    
    var totalAnswerCount: UInt {
        return self.answerOptions.reduce(0) { $0 + $1.count}
    }
}
