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


let MXDehydrationAlgorithm = "org.matrix.msc2697.v1.olm.libolm_pickle"

@objcMembers
public class MXDehydrationManager: NSObject {
    private enum Constants {
        static let MXDehydrationManagerErrorDomain = "org.matrix.MXDehydrationManager"
        static let MXDehydrationManagerCryptoInitialisedError = -1
    }

    private let session: MXSession
    private var inProgress = false
    private(set) var exportedOlmDeviceToImport: MXExportedOlmDevice?
    
    public init(session: MXSession) {
        self.session = session
    }
    
    public func dehydrateDevice(completion: @escaping (MXResponse<String?>) -> Void) {
        guard !inProgress else {
            MXLog.debug("[MXDehydrationManager] dehydrateDevice: Dehydration already in progress -- not starting new dehydration")
            completion(.success(nil))
            return
        }
        
        guard session.crypto != nil else {
            MXLog.debug("[MXSession] rehydrateDevice: Cannot dehydrate device without crypto has been initialized.")
            completion(.failure(NSError(domain: Constants.MXDehydrationManagerErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey:"Cannot dehydrate device without crypto has been initialized."])))
            return
        }
        
        let keyData = MXKeyProvider.sharedInstance().requestKeyForData(ofType: MXDehydrationServiceKeyDataType, isMandatory: false, expectedKeyType: .rawData)
        
        guard keyData != nil else {
            MXLog.debug("[MXDehydrationManager] dehydrateDevice: No dehydrated key.")
            completion(.success(nil))
            return
        }

        inProgress = true;
        
        let key = (keyData as! MXRawDataKey).key
        
//        let account = OLMAccount();

//        let account = OLMA
//        OLMAccount *account = [[OLMAccount alloc] initNewAccount];
//        NSDictionary *e2eKeys = [account identityKeys];
//
//        NSUInteger maxKeys = [account maxOneTimeKeys];
//        [account generateOneTimeKeys:maxKeys / 2];
//
//        // [account account.generateFallbackKey];
//
//        MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: account created %@", account.identityKeys);
//
//        // dehydrate the account and store it on the server
//        NSError *error = nil;
//        MXDehydratedDevice *dehydratedDevice = [MXDehydratedDevice new];
//        dehydratedDevice.account = [account serializeDataWithKey:key error:&error];
//        dehydratedDevice.algorithm = MXDehydrationAlgorithm;
//
//        if (error)
//        {
//            inProgress = NO;
//            MXLogError(@"[MXDehydrationManager] dehydrateDevice: account serialization failed: %@", error);
//            failure(error);
//            return;
//        }
//
//        [session.crypto.matrixRestClient setDehydratedDevice:dehydratedDevice withDisplayName:@"Backup device" success:^(NSString *deviceId) {
//            MXLogDebug(@"[MXDehydrationManager] dehydrateDevice: preparing device keys for device %@ (current device ID %@)", deviceId, self->session.crypto.myDevice.deviceId);
//            MXDeviceInfo *deviceInfo = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
//            deviceInfo.userId = self->session.crypto.matrixRestClient.credentials.userId;
//            deviceInfo.keys = @{
//                [NSString stringWithFormat:@"ed25519:%@", deviceId]: e2eKeys[@"ed25519"],
//                [NSString stringWithFormat:@"curve25519:%@", deviceId]: e2eKeys[@"curve25519"]
//            };
//            deviceInfo.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
//
//            NSString *signature = [account signMessage:[MXCryptoTools canonicalJSONDataForJSON:deviceInfo.signalableJSONDictionary]];
//            deviceInfo.signatures = @{
//                                    self->session.crypto.matrixRestClient.credentials.userId: @{
//                                            [NSString stringWithFormat:@"ed25519:%@", deviceInfo.deviceId]: signature
//                                        }
//                                    };
//
//            if ([self->session.crypto.crossSigning secretIdFromKeyType:MXCrossSigningKeyType.selfSigning])
//            {
//                [self->session.crypto.crossSigning signDevice:deviceInfo success:^{
//                    [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
//                } failure:^(NSError * _Nonnull error) {
//                    MXLogWarning(@"[MXDehydrationManager] failed to cross-sign dehydrated device data: %@", error);
//                    [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
//                }];
//            } else {
//                [self uploadDeviceInfo:deviceInfo forAccount:account success:success failure:failure];
//            }
//        } failure:^(NSError *error) {
//            self->inProgress = NO;
//            MXLogError(@"[MXDehydrationManager] failed to push dehydrated device data: %@", error);
//            failure(error);
//        }];
    }
}

// MARK: - Objective-C interface
extension MXDehydrationManager {
    
    public func dehydrateDevice(success: @escaping (_ deviceId: String?) -> Void, failure: @escaping (_ error: Error) -> Void) {
        return self.dehydrateDevice { (deviceId) in
            uncurryResponse(deviceId, success: success, failure: failure)
        }
    }
}

