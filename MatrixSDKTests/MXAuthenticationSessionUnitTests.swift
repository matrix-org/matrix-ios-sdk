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

import XCTest

import MatrixSDK

class MXAuthenticationSessionUnitTests: XCTestCase {

    func testParsing() throws {
        
        let json: [String: Any] = [
            "completed": [],
            "session": "2134",
            "flows": [
                ["type": "m.login.password",
                 "stages": [],
                ],
                ["type": "m.login.sso",
                 "stages": [],
                 MXLoginSSOFlowIdentityProvidersKey: [
                    ["id": "gitlab",
                     "name": "GitLab"
                    ],
                    ["id": "github",
                     "name": "GitHub",
                     "icon": "https://github/icon.png"
                    ]
                 ]
                ],
                ["type": "m.login.cas",
                 "stages": [],
                 "identity_providers": []
                ]
            ],
            "params": [
            ]
        ]
        
        let authenticationSession = MXAuthenticationSession(fromJSON: json)
                       
        guard let flows = authenticationSession?.flows else {
            XCTFail("flows shouldn not be nil")
            return
        }
        
        XCTAssertEqual(flows.count, 3)
        
        if let ssoFlow = flows.first(where: { $0.type == kMXLoginFlowTypeSSO }) {
            
            if let loginSSOFlow = ssoFlow as? MXLoginSSOFlow {
                
                XCTAssertEqual(loginSSOFlow.identityProviders.count, 2)
                
                if let gitlabProvider = loginSSOFlow.identityProviders.first(where: { $0.identifier == "gitlab" }) {
                    
                    XCTAssertEqual(gitlabProvider.name, "GitLab")
                    XCTAssertNil(gitlabProvider.icon)
                } else {
                    XCTFail("Fail to find GitLab provider")
                }
                
                if let githubProvider = loginSSOFlow.identityProviders.first(where: { $0.identifier == "github" }) {
                    
                    XCTAssertEqual(githubProvider.name, "GitHub")
                    XCTAssertEqual(githubProvider.icon, "https://github/icon.png")
                } else {
                    XCTFail("Fail to find GitHub provider")
                }
                
            } else {
                XCTFail("The SSO flow is not member of class MXLoginSSOFlow")
            }
                        
        } else {
            XCTFail("Fail to find SSO flow")
        }
        
        if let casFlow = flows.first(where: { $0.type == kMXLoginFlowTypeCAS }) {
            
            if let loginSSOFlow = casFlow as? MXLoginSSOFlow {
                
                XCTAssertTrue(loginSSOFlow.identityProviders.isEmpty)
                                
            } else {
                XCTFail("The CAS flow is not member of class MXLoginSSOFlow")
            }
            
        } else {
            XCTFail("Fail to find CAS flow")
        }
        
        if let passwordFlow = flows.first(where: { $0.type == kMXLoginFlowTypePassword }) {
            
            XCTAssertFalse(passwordFlow is MXLoginSSOFlow)
        } else {
            XCTFail("Fail to find password flow")
        }
        
    }
}
