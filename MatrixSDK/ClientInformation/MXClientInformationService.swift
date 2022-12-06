// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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
public class MXClientInformationService: NSObject {

    private weak var session: MXSession?
    private let bundle: Bundle

    public init(withSession session: MXSession,
                bundle: Bundle) {
        self.session = session
        self.bundle = bundle
    }

    public func updateData() {
        guard let session = session else {
            return
        }

        guard MXSDKOptions.sharedInstance().enableNewClientInformationFeature else {
            return deleteDataIfNeeded(on: session)
        }

        guard let updatedInfo = createClientInformation() else {
            return
        }

        let type = accountDataType(for: session)
        let currentInfo = session.accountData.accountData(forEventType: type)

        guard !NSDictionary(dictionary: updatedInfo).isEqual(to: currentInfo ?? [:]) else {
            MXLog.debug("[MXClientInformationService] refresh: no need to update")
            return
        }

        session.setAccountData(updatedInfo, forType: type) {
            MXLog.debug("[MXClientInformationService] refresh: updated successfully")
        } failure: { error in
            MXLog.debug("[MXClientInformationService] refresh: update failed: \(String(describing: error))")
        }
    }

    private func deleteDataIfNeeded(on session: MXSession) {
        let type = accountDataType(for: session)

        guard session.accountData.accountData(forEventType: type) != nil else {
            // not exists, no need to do anything
            MXLog.debug("[MXClientInformationService] removeDataIfNeeded: no need to remove")
            return
        }

        session.deleteAccountData(withType: type) {
            MXLog.debug("[MXClientInformationService] removeDataIfNeeded: removed successfully")
        } failure: { error in
            MXLog.debug("[MXClientInformationService] removeDataIfNeeded: remove failed: \(String(describing: error))")
        }
    }

    private func createClientInformation() -> [AnyHashable: String]? {
        guard let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        return [
            "name": "\(name) iOS",
            "version": version
        ]
    }

    private func accountDataType(for session: MXSession) -> String {
        guard let deviceId = session.myDeviceId else {
            fatalError("[MXClientInformationService] No device id")
        }
        return "\(kMXAccountDataTypeClientInformation).\(deviceId)"
    }
}
