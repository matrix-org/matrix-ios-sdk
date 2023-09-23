// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

/// Background push rules manager. Does work independent from a `MXNotificationCenter`.
@objcMembers public class MXBackgroundPushRulesManager: NSObject {
    
    private let credentials: MXCredentials
    private var pushRulesResponse: MXPushRulesResponse? {
        didSet {
            var tmpRules: [MXPushRule] = []
            
            if let global = pushRulesResponse?.global {
                if let rules = global.override as? [MXPushRule] {
                    tmpRules.append(contentsOf: rules)
                }
                if let rules = global.content as? [MXPushRule] {
                    tmpRules.append(contentsOf: rules)
                }
                if let rules = global.room as? [MXPushRule] {
                    tmpRules.append(contentsOf: rules)
                }
                if let rules = global.sender as? [MXPushRule] {
                    tmpRules.append(contentsOf: rules)
                }
                if let rules = global.underride as? [MXPushRule] {
                    tmpRules.append(contentsOf: rules)
                }
            }
            
            // vector-im/element-ios/issues/7636
            // Intentionally disable new backend push rules as they're not handle properly and break notification sounds
            flatRules = tmpRules.filter { $0.ruleId != ".m.rule.is_user_mention" && $0.ruleId != ".m.rule.is_room_mention" }
        }
    }
    private var flatRules: [MXPushRule] = []
    private var eventMatchConditionChecker: MXPushRuleEventMatchConditionChecker
    private var memberCountConditionChecker: MXPushRuleRoomMemberCountConditionChecker
    private var permissionConditionChecker: MXPushRuleSenderNotificationPermissionConditionChecker
    
    /// Initializer.
    /// - Parameter credentials: Credentials to use when fetching initial push rules.
    public init(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        eventMatchConditionChecker = MXPushRuleEventMatchConditionChecker()
        memberCountConditionChecker = MXPushRuleRoomMemberCountConditionChecker(matrixSession: nil)
        permissionConditionChecker = MXPushRuleSenderNotificationPermissionConditionChecker(matrixSession: nil)
        super.init()
    }
    
    /// Handle account data from a sync response.
    /// - Parameter accountData: The account data to be handled.
    public func handleAccountData(_ accountData: [AnyHashable: Any]) {
        guard let events = accountData["events"] as? [[AnyHashable: Any]] else { return }
        events.forEach { (event) in
            if let type = event["type"] as? String,
                type == kMXAccountDataTypePushRules,
                let content = event["content"] as? [AnyHashable: Any] {
                self.pushRulesResponse = MXPushRulesResponse(fromJSON: content)
            }
        }
    }
    
    /// Check whether the given room is mentions only.
    /// - Parameter roomId: The room identifier to be checked
    /// - Returns: If the room is mentions only.
    public func isRoomMentionsOnly(_ roomId: String) -> Bool {
        // Check push rules at room level
        guard let rule = self.getRoomPushRule(forRoom: roomId) else {
            return false
        }
        
        // Support for MSC3987: The dont_notify push rule action is deprecated.
        if rule.actions.isEmpty {
            return rule.enabled
        }
        
        // Compatibility support.
        for ruleAction in rule.actions {
            guard let action = ruleAction as? MXPushRuleAction else { continue }
            if action.actionType == MXPushRuleActionTypeDontNotify {
                return rule.enabled
            }
        }

        return false
    }
    
    /// Fetch push rule matching an event.
    /// - Parameters:
    ///   - event: The event to be matched.
    ///   - roomState: Room state.
    ///   - currentUserDisplayName: Display name of the current user.
    /// - Returns: Push rule matching the event.
    public func pushRule(matching event: MXEvent,
                         roomState: MXRoomState,
                         currentUserDisplayName: String?) -> MXPushRule? {
        //  return nil if current user's event
        if event.sender == credentials.userId {
            return nil
        }
        
        let displayNameChecker = MXPushRuleDisplayNameCondtionChecker(matrixSession: nil,
                                                                      currentUserDisplayName: currentUserDisplayName)
        
        let conditionCheckers: [MXPushRuleConditionType: MXPushRuleConditionChecker] = [
            .eventMatch: eventMatchConditionChecker,
            .containsDisplayName: displayNameChecker,
            .roomMemberCount: memberCountConditionChecker,
            .senderNotificationPermission: permissionConditionChecker
        ]
        // getting the unencrypted event if present or fallback
        let eventDictionary = (event.clear ?? event).jsonDictionary()
        let equivalentCondition = MXPushRuleCondition()
        
        for rule in flatRules.filter({ $0.enabled }) {
            var conditionsOk: Bool = true
            var runEquivalent: Bool = false
            
            guard let kind = MXPushRuleKind(identifier: rule.kind) else {
                continue
            }
            
            switch kind {
            case .override, .underride:
                conditionsOk = true
                
                for condition in rule.conditions {
                    guard let condition = condition as? MXPushRuleCondition else { continue }
                    let conditionType = MXPushRuleConditionType(identifier: condition.kind)
                    if let checker = conditionCheckers[conditionType] {
                        conditionsOk = checker.isCondition(condition,
                                                           satisfiedBy: event,
                                                           roomState: roomState,
                                                           withJsonDict: eventDictionary)
                        if !conditionsOk {
                            //  Do not need to go further
                            break
                        }
                    } else {
                        conditionsOk = false
                    }
                }
            case .content:
                equivalentCondition.parameters = [
                    "key": "content.body",
                    "pattern": rule.pattern as Any
                ]
                runEquivalent = true
            case .room:
                equivalentCondition.parameters = [
                    "key": "room_id",
                    "pattern": rule.ruleId as Any
                ]
                runEquivalent = true
            case .sender:
                equivalentCondition.parameters = [
                    "key": "user_id",
                    "pattern": rule.ruleId as Any
                ]
                runEquivalent = true
            }
            
            if runEquivalent {
                conditionsOk = eventMatchConditionChecker.isCondition(equivalentCondition,
                                                                      satisfiedBy: event,
                                                                      roomState: roomState,
                                                                      withJsonDict: eventDictionary)
            }
            
            if conditionsOk {
                return rule
            }
        }
        
        return nil
    }
    
    //  MARK: - Private
    
    private func getRoomPushRule(forRoom roomId: String) -> MXPushRule? {
        guard let rules = pushRulesResponse?.global.room as? [MXPushRule] else {
            return nil
        }
        
        return rules.first(where: { roomId == $0.ruleId })
    }
    
}
