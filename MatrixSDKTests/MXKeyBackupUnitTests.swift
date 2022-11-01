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

import XCTest

@testable import MatrixSDK

class MXKeyBackupUnitTests: XCTestCase {

    // MARK: - Curve25519

    func testCurve25519AlgorithmClass() throws {
        XCTAssertEqual(MXCurve25519KeyBackupAlgorithm.algorithmName, kMXCryptoCurve25519KeyBackupAlgorithm)
        XCTAssertTrue(MXCurve25519KeyBackupAlgorithm.isUntrusted)
    }

    func testCurve25519AuthData() throws {
        let publicKey = "abcdefg"
        let privateKeySalt = "hijklmno"
        let privateKeyIterations: UInt = 500000
        let signatures: [AnyHashable: Any] = [
            "something": [
                "ed25519:something": "hijklmnop"
            ]
        ]

        let json: [String: Any] = [
            "public_key": publicKey,
            "private_key_salt": privateKeySalt,
            "private_key_iterations": privateKeyIterations,
            "signatures": signatures
        ]

        guard let authData = MXCurve25519BackupAuthData(fromJSON: json),
        let authDataSignatures = authData.signatures else {
            XCTFail("Failed to setup test conditions")
            return
        }

        XCTAssertEqual(authData.publicKey, publicKey)
        XCTAssertEqual(authData.privateKeySalt, privateKeySalt)
        XCTAssertEqual(authData.privateKeyIterations, privateKeyIterations)
        XCTAssertTrue(NSDictionary(dictionary: signatures).isEqual(to: NSDictionary(dictionary: authDataSignatures) as! [AnyHashable : Any]))
        XCTAssertTrue(NSDictionary(dictionary: authData.jsonDictionary()).isEqual(to: NSDictionary(dictionary: json) as! [AnyHashable : Any]))
        XCTAssertNil(authData.signalableJSONDictionary["signatures"])
    }

    func testCurve25519KeyMatch() throws {
        var salt: NSString? = ""
        var iterations: UInt = 0
        var error: NSError? = nil
        let privateKey = try MXKeyBackupPassword.generatePrivateKey(withPassword: "password",
                                                                    salt: &salt,
                                                                    iterations: &iterations)
        let olmPkDecryption = OLMPkDecryption()
        let publicKey = olmPkDecryption.setPrivateKey(privateKey, error: &error)

        XCTAssertTrue(try MXCurve25519KeyBackupAlgorithm.keyMatches(privateKey, withAuthData: ["public_key": publicKey]))
    }

    func testCurve25519PreparationWithNoPassword() throws {
        let preparationInfoWithNoPass = try MXCurve25519KeyBackupAlgorithm.prepare(with: nil)
        guard let authDataWithNoPass = preparationInfoWithNoPass.authData as? MXCurve25519BackupAuthData else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertFalse(authDataWithNoPass.publicKey.isEmpty)
        XCTAssertNil(authDataWithNoPass.privateKeySalt)
        XCTAssertEqual(authDataWithNoPass.privateKeyIterations, 0)
    }

    func testCurve25519PreparationWithPassword() throws {
        let preparationInfoWithPass = try MXCurve25519KeyBackupAlgorithm.prepare(with: "password")
        guard let authDataWithPass = preparationInfoWithPass.authData as? MXCurve25519BackupAuthData else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertFalse(authDataWithPass.publicKey.isEmpty)
        XCTAssertNotNil(authDataWithPass.privateKeySalt)
        XCTAssertNotEqual(authDataWithPass.privateKeyIterations, 0)
    }

    func testCurve25519AuthDataGeneration() throws {
        let json: [String: Any] = [
            "public_key": "abcdefg",
            "signatures": [
                "something": [
                    "ed25519:something": "hijklmnop"
                ]
            ]
        ]

        guard let authData = try MXCurve25519KeyBackupAlgorithm.authData(fromJSON: json) as? MXCurve25519BackupAuthData,
              let signatures = authData.signatures else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertFalse(authData.publicKey.isEmpty)
        XCTAssertFalse(signatures.isEmpty)
    }

    func testCurve25519KeyBackupVersionCheck() throws {
        let json: [String: Any] = [
            "algorithm": kMXCryptoCurve25519KeyBackupAlgorithm,
            "auth_data": [
                "public_key": "abcdefg"
            ],
            "version": "1"
        ]

        guard let keyBackupVersion = MXKeyBackupVersion(fromJSON: json) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertTrue(MXCurve25519KeyBackupAlgorithm.check(keyBackupVersion))
    }

    func testCurve25519AlgorithmInstance() throws {
        var salt: NSString? = ""
        var iterations: UInt = 0
        let privateKey = try MXKeyBackupPassword.generatePrivateKey(withPassword: "password", salt: &salt, iterations: &iterations)

        let olmPkDecryption = OLMPkDecryption()
        var error: NSError? = nil
        let publicKey = olmPkDecryption.setPrivateKey(privateKey, error: &error)

        let crypto = MXLegacyCrypto()
        let json: [String: Any] = [
            "public_key": publicKey,
            "signatures": [
                "something": [
                    "ed25519:something": "hijklmnop"
                ]
            ]
        ]

        let authData = try MXCurve25519KeyBackupAlgorithm.authData(fromJSON: json)
        guard let algorithm = MXCurve25519KeyBackupAlgorithm(crypto: crypto,
                                                             authData: authData,
                                                             keyGetterBlock: { return privateKey }) else {
            return
        }
        XCTAssertTrue(try algorithm.keyMatches(privateKey))
    }

    // MARK: - Aes256

    func testAes256AlgorithmClass() throws {
        XCTAssertEqual(MXAes256KeyBackupAlgorithm.algorithmName, kMXCryptoAes256KeyBackupAlgorithm)
        XCTAssertFalse(MXAes256KeyBackupAlgorithm.isUntrusted)
    }

    func testAes256AuthData() throws {
        let iv = "abcdefg"
        let mac = "abcdefgtyu"
        let privateKeySalt = "hijklmno"
        let privateKeyIterations: UInt = 500000
        let signatures: [AnyHashable: Any] = [
            "something": [
                "ed25519:something": "hijklmnop"
            ]
        ]

        let json: [String: Any] = [
            "iv": iv,
            "mac": mac,
            "private_key_salt": privateKeySalt,
            "private_key_iterations": privateKeyIterations,
            "signatures": signatures
        ]

        guard let authData = MXAes256BackupAuthData(fromJSON: json),
              let authDataSignatures = authData.signatures else {
            XCTFail("Failed to setup test conditions")
            return
        }

        XCTAssertEqual(authData.iv, iv)
        XCTAssertEqual(authData.mac, mac)
        XCTAssertEqual(authData.privateKeySalt, privateKeySalt)
        XCTAssertEqual(authData.privateKeyIterations, privateKeyIterations)
        XCTAssertTrue(NSDictionary(dictionary: signatures).isEqual(to: NSDictionary(dictionary: authDataSignatures) as! [AnyHashable : Any]))
        XCTAssertTrue(NSDictionary(dictionary: authData.jsonDictionary()).isEqual(to: NSDictionary(dictionary: json) as! [AnyHashable : Any]))
        XCTAssertNil(authData.signalableJSONDictionary["signatures"])
    }

    func testAes256KeyMatch() throws {
        var salt: NSString? = ""
        var iterations: UInt = 0
        let privateKey = try MXKeyBackupPassword.generatePrivateKey(withPassword: "password",
                                                                    salt: &salt,
                                                                    iterations: &iterations)
        let secretContent = try MXSecretStorage().encryptedZeroString(withPrivateKey: privateKey, iv: nil)

        guard let mac = secretContent.mac, let iv = secretContent.iv else {
            XCTFail("Failed to setup test conditions")
            return
        }

        XCTAssertTrue(try MXAes256KeyBackupAlgorithm.keyMatches(privateKey, withAuthData: [:]))
        XCTAssertTrue(try MXAes256KeyBackupAlgorithm.keyMatches(privateKey, withAuthData: ["mac": mac, "iv": iv]))
    }

    func testAes256PreparationWithNoPassword() throws {
        let preparationInfoWithNoPass = try MXAes256KeyBackupAlgorithm.prepare(with: nil)
        guard let authDataWithNoPass = preparationInfoWithNoPass.authData as? MXAes256BackupAuthData else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertNotNil(authDataWithNoPass.iv)
        XCTAssertNotNil(authDataWithNoPass.mac)
        XCTAssertNil(authDataWithNoPass.privateKeySalt)
        XCTAssertEqual(authDataWithNoPass.privateKeyIterations, 0)
    }

    func testAes256PreparationWithPassword() throws {
        let preparationInfoWithPass = try MXAes256KeyBackupAlgorithm.prepare(with: "password")
        guard let authDataWithPass = preparationInfoWithPass.authData as? MXAes256BackupAuthData else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertNotNil(authDataWithPass.iv)
        XCTAssertNotNil(authDataWithPass.mac)
        XCTAssertNotNil(authDataWithPass.privateKeySalt)
        XCTAssertNotEqual(authDataWithPass.privateKeyIterations, 0)
    }

    func testAes256AuthDataGeneration() throws {
        let json: [String: Any] = [
            "iv": "abcdefg",
            "mac": "asdbasdsd",
            "signatures": [
                "something": [
                    "ed25519:something": "hijklmnop"
                ]
            ]
        ]

        guard let authData = try MXAes256KeyBackupAlgorithm.authData(fromJSON: json) as? MXAes256BackupAuthData,
              let signatures = authData.signatures else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertNotNil(authData.iv)
        XCTAssertNotNil(authData.mac)
        XCTAssertFalse(signatures.isEmpty)
    }

    func testAes256KeyBackupVersionCheck() throws {
        let json: [String: Any] = [
            "algorithm": kMXCryptoAes256KeyBackupAlgorithm,
            "auth_data": [
                "iv": "abcdefgh",
                "mac": "zdkcsdfsdf"
            ],
            "version": "1"
        ]

        guard let keyBackupVersion = MXKeyBackupVersion(fromJSON: json) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertTrue(MXAes256KeyBackupAlgorithm.check(keyBackupVersion))
    }

    func testAes256AlgorithmInstance() throws {
        var salt: NSString? = ""
        var iterations: UInt = 0
        let privateKey = try MXKeyBackupPassword.generatePrivateKey(withPassword: "password",
                                                                    salt: &salt,
                                                                    iterations: &iterations)
        let secretContent = try MXSecretStorage().encryptedZeroString(withPrivateKey: privateKey, iv: nil)

        guard let mac = secretContent.mac, let iv = secretContent.iv else {
            XCTFail("Failed to setup test conditions")
            return
        }

        let crypto = MXLegacyCrypto()
        let json: [String: Any] = [
            "iv": iv,
            "mac": mac,
            "signatures": [
                "something": [
                    "ed25519:something": "hijklmnop"
                ]
            ]
        ]

        let authData = try MXAes256KeyBackupAlgorithm.authData(fromJSON: json)
        guard let algorithm = MXAes256KeyBackupAlgorithm(crypto: crypto,
                                                         authData: authData,
                                                         keyGetterBlock: { return privateKey }) else {
            return
        }
        XCTAssertTrue(try algorithm.keyMatches(privateKey))
    }

}
