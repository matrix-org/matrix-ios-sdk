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

struct PollBuilder {
    func build(pollStartEventContent: MXEventContentPollStart, events: [MXEvent], currentUserIdentifer: String? = nil) -> PollProtocol {
        
        let poll = Poll()
        
        poll.text = pollStartEventContent.question
        poll.maxAllowedSelections = pollStartEventContent.maxSelections.uintValue
        poll.kind = (pollStartEventContent.kind == kMXMessageContentKeyExtensiblePollKindUndisclosed ? .undisclosed : .disclosed)
        
        var answerOptionIdentifiers = [String]()
        poll.answerOptions = pollStartEventContent.answerOptions.map { answerOption in
            answerOptionIdentifiers.append(answerOption.uuid)
            
            let option = PollAnswerOption()
            option.id = answerOption.uuid
            option.text = answerOption.text
            return option
        }
        
        let stopEvent = events.filter { $0.type == kMXEventTypeStringPollEnd }.first
        poll.isClosed = (stopEvent != nil)
        
        var filteredEvents = events.filter { event in
            guard
                let eventContent = event.content, event.type == kMXEventTypeStringPollResponse,
                let answer = eventContent[kMXMessageContentKeyExtensiblePollResponse] as? [String: [String]],
                let _ = answer[kMXMessageContentKeyExtensiblePollAnswers] else {
                return false
            }
            
            // Remove responses submitted after the poll was closed
            if let stopOriginServerTs = stopEvent?.originServerTs, event.originServerTs > stopOriginServerTs {
                return false
            }
            
            return true
        }
        
        // Sort them by the server timestamp, newest first
        filteredEvents.sort { firstEvent, secondEvent in
            return firstEvent.originServerTs > secondEvent.originServerTs
        }
        
        let answersGroupedByUser = filteredEvents.reduce([String: [String]]()) { result, event in
            guard let userIdentifier = event.sender,
                  let eventContent = event.content,
                  let answer = eventContent[kMXMessageContentKeyExtensiblePollResponse] as? [String: [String]],
                  let answerIdentifiers = answer[kMXMessageContentKeyExtensiblePollAnswers],
                  !result.keys.contains(userIdentifier) else {
                return result
            }
            
            var result = result
            result[userIdentifier] = answerIdentifiers
            return result
        }
        
        var currentUserAnswers: [String]?
        var winningCount: UInt = 0
        let countedAnswers = answersGroupedByUser.reduce([String: UInt]()) { result, groupedUserAnswers in
            // Remove responses with no answers or more than allowed
            guard !groupedUserAnswers.value.isEmpty, groupedUserAnswers.value.count <= poll.maxAllowedSelections else {
                return result
            }
            
            // Remove responses that contain invalid answer identifiers
            guard !groupedUserAnswers.value.map({ answerOptionIdentifiers.contains($0) }).isEmpty else {
                return result
            }
            
            var result = result
            for answerIdentifier in Array(Set(groupedUserAnswers.value)) { //Remove duplicates
                let count  = (result[answerIdentifier] ?? 0) + 1
                result[answerIdentifier] = count
                if count > winningCount {
                    winningCount = count
                }
            }
            
            if groupedUserAnswers.key == currentUserIdentifer {
                currentUserAnswers = groupedUserAnswers.value
            }
            
            return result
        }
        
        for case let answerOption as PollAnswerOption in poll.answerOptions {
            answerOption.count = countedAnswers[answerOption.id] ?? 0
            answerOption.isWinner = (answerOption.count > 0 && answerOption.count == winningCount)
            answerOption.isCurrentUserSelection = (currentUserAnswers?.contains(answerOption.id) ?? false)
        }
        
        return poll
    }
    
}
