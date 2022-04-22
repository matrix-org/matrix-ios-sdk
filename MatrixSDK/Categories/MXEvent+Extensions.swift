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

@objc
public extension MXEvent {

    /// Flag indicating the receiver event should be highlighted
    /// - Parameter session: session instance to read notification rules from
    /// - Returns: true if clients should highlight the receiver event
    func shouldBeHighlighted(inSession session: MXSession) -> Bool {
        if sender == session.myUserId {
            //  do not highlight any event that the current user sent
            return false
        }

        let displayNameChecker = MXPushRuleDisplayNameCondtionChecker(matrixSession: session,
                                                                      currentUserDisplayName: nil)

        if displayNameChecker.isCondition(nil, satisfiedBy: self, roomState: nil, withJsonDict: nil) {
            return true
        }
        guard let rule = session.notificationCenter?.rule(matching: self, roomState: nil) else {
            return false
        }

        var isHighlighted = false

        // Check whether is there an highlight tweak on it
        for ruleAction in rule.actions ?? [] {
            guard let action = ruleAction as? MXPushRuleAction else { continue }
            guard action.actionType == MXPushRuleActionTypeSetTweak else { continue }
            guard action.parameters["set_tweak"] as? String == "highlight" else { continue }
            // Check the highlight tweak "value"
            // If not present, highlight. Else check its value before highlighting
            if nil == action.parameters["value"] || true == (action.parameters["value"] as? Bool) {
                isHighlighted = true
                break
            }
        }

        return isHighlighted
    }
    
}
