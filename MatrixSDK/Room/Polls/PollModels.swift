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

public enum PollKind {
    case disclosed
    case undisclosed
}

public protocol PollAnswerOptionProtocol {
    var id: String { get }
    var text: String { get }
    var count: UInt { get }
    var isWinner: Bool { get }
    var isCurrentUserSelection: Bool { get }
}

public protocol PollProtocol {
    var id: String { get }
    var text: String { get }
    var answerOptions: [PollAnswerOptionProtocol] { get }
    var kind: PollKind { get }
    var startDate: Date { get }
    var maxAllowedSelections: UInt { get }
    var isClosed: Bool { get }
    var totalAnswerCount: UInt { get }
    var hasBeenEdited: Bool { get }
    var hasDecryptionError: Bool { get }
}

class PollAnswerOption: PollAnswerOptionProtocol {
    var id: String = ""
    var text: String = ""
    var count: UInt = 0
    var isWinner: Bool = false
    var isCurrentUserSelection: Bool = false
}

class Poll: PollProtocol {
    var id: String = ""
    var text: String = ""
    var answerOptions: [PollAnswerOptionProtocol] = []
    var kind: PollKind = .disclosed
    var startDate: Date = .distantPast
    var maxAllowedSelections: UInt = 1
    var isClosed: Bool = false
    var hasBeenEdited: Bool = false
    var hasDecryptionError: Bool = false
    
    var totalAnswerCount: UInt {
        answerOptions.reduce(0) { $0 + $1.count }
    }
}
