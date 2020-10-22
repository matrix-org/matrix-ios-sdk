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

@objcMembers
public class MXBackgroundPushRulesManager: NSObject {
    
    private let restClient: MXRestClient
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
            
            flatRules = tmpRules
        }
    }
    private var flatRules: [MXPushRule] = []
    private var eventMatchConditionChecker: MXPushRuleEventMatchConditionChecker
    private var memberCountConditionChecker: MXPushRuleRoomMemberCountConditionChecker
    private var permissionConditionChecker: MXPushRuleSenderNotificationPermissionConditionChecker
    
    public init(withRestClient restClient: MXRestClient) {
        self.restClient = restClient
        eventMatchConditionChecker = MXPushRuleEventMatchConditionChecker()
        memberCountConditionChecker = MXPushRuleRoomMemberCountConditionChecker(matrixSession: nil)
        permissionConditionChecker = MXPushRuleSenderNotificationPermissionConditionChecker(matrixSession: nil)
        super.init()
        restClient.pushRules { (response) in
            switch response {
            case .success(let response):
                self.pushRulesResponse = response
            case .failure:
                break
            }
        }
    }
    
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
    
    public func isRoomMentionsOnly(_ roomId: String) -> Bool {
        // Check push rules at room level
        guard let rule = self.getRoomPushRule(forRoom: roomId) else {
            return false
        }
        
        for ruleAction in rule.actions {
            guard let action = ruleAction as? MXPushRuleAction else { continue }
            if action.actionType == MXPushRuleActionTypeDontNotify {
                return rule.enabled
            }
        }

        return false
    }
    
    public func pushRule(matching event: MXEvent,
                         roomState: MXRoomState,
                         currentUserDisplayName: String?) -> MXPushRule? {
        //  return nil if current user's event
        if event.sender == restClient.credentials.userId {
            return nil
        }
        
        let displayNameChecker = MXPushRuleDisplayNameCondtionChecker(matrixSession: nil,
                                                                      currentUserDisplayName: currentUserDisplayName)
        
        let conditionCheckers: [MXPushRuleConditionType: MXPushRuleConditionChecker] = [
            MXPushRuleConditionTypeEventMatch: eventMatchConditionChecker,
            MXPushRuleConditionTypeContainsDisplayName: displayNameChecker,
            MXPushRuleConditionTypeRoomMemberCount: memberCountConditionChecker,
            MXPushRuleConditionTypeSenderNotificationPermission: permissionConditionChecker
        ]
        
        let eventDictionary = event.jsonDictionary()
        
        let equivalentCondition = MXPushRuleCondition()
        equivalentCondition.kindType = MXPushRuleConditionTypeEventMatch
        
        for rule in flatRules.filter({ $0.enabled }) {
            var conditionsOk: Bool = true
            var runEquivalent: Bool = false
            
            switch rule.kind {
            case __MXPushRuleKindOverride, __MXPushRuleKindUnderride:
                conditionsOk = true
                
                for condition in rule.conditions {
                    guard let condition = condition as? MXPushRuleCondition else { continue }
                    if let checker = conditionCheckers[condition.kindType] {
                        conditionsOk = checker.isCondition(condition,
                                                           satisfiedBy: event,
                                                           roomState: roomState,
                                                           withJsonDict: eventDictionary)
                        if !conditionsOk {
                            // Do not need to go further
                            break
                        }
                    } else {
                        conditionsOk = false
                    }
                }
                break
            case __MXPushRuleKindContent:
                equivalentCondition.parameters = [
                    "key": "content.body",
                    "pattern": rule.pattern as Any
                ]
                runEquivalent = true
                break
            case __MXPushRuleKindRoom:
                equivalentCondition.parameters = [
                    "key": "room_id",
                    "pattern": rule.ruleId as Any
                ]
                runEquivalent = true
                break
            case __MXPushRuleKindSender:
                equivalentCondition.parameters = [
                    "key": "user_id",
                    "pattern": rule.ruleId as Any
                ]
                runEquivalent = true
                break
            default:
                break
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
    
    private func setupCheckers() {
        
    }
    
    private func getRoomPushRule(forRoom roomId: String) -> MXPushRule? {
        guard let rules = pushRulesResponse?.global.room else {
            return nil
        }
        
        for rule in rules {
            guard let pushRule = rule as? MXPushRule else { continue }
            // the rule id is the room Id
            // it is the server trick to avoid duplicated rule on the same room.
            if pushRule.ruleId == roomId {
                return pushRule
            }
        }

        return nil
    }
    
}

extension MXPushRuleConditionType: Hashable {}
