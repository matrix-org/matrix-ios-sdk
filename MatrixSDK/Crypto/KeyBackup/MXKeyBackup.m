/*
 Copyright 2018 New Vector Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXKeyBackup.h"
#import "MXKeyBackup_Private.h"

#import "MXCrypto_Private.h"

#import <OLMKit/OLMKit.h>
#import "MXRecoveryKey.h"
#import "MXSession.h"   // TODO: To remove
#import "MXTools.h"

/**
 Maximum delay in ms in `[MXKeyBackup maybeSendKeyBackup]`.
 */
NSUInteger const kMXKeyBackupWaitingTimeToSendKeyBackup = 10000;

/**
 Maximum number of keys to send at a time to the homeserver.
 */
NSUInteger const kMXKeyBackupSendKeysMaxCount = 100;


@interface MXKeyBackup ()
{
    MXSession *mxSession;
    
    // track whether this device's megolm keys are being backed up incrementally
    // to the server or not.
    // XXX: this should probably have a single source of truth from OlmAccount
// +    this.backupInfo = null; // The info dict from /room_keys/version
// +   this.backupKey = null; // The encryption key object
//    this._checkedForBackup = false; // Have we checked the server for a backup we can use?
// X  this._sendingBackups = false; // Are we currently sending backups?
}

@end

@implementation MXKeyBackup

#pragma mark - SDK-Private methods

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession
{
    self = [self init];
    {
        _state = MXKeyBackupStateDisabled;
        mxSession = matrixSession;
    }
    return self;
}

- (BOOL)enableKeyBackup:(MXKeyBackupVersion*)version
{
    MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData modelFromJSON:version.authData];
    if (authData)
    {
        _keyBackupVersion = version;
        _backupKey = [OLMPkEncryption new];
        [_backupKey setRecipientKey:authData.publicKey];

        self.state = MXKeyBackupStateReadyToBackup;
        
        [self maybeSendKeyBackup];
    }

    // wdty?
    return _backupKey;
}

- (void)disableKeyBackup
{
    _keyBackupVersion = nil;
    _backupKey = nil;
    self.state = MXKeyBackupStateDisabled;

    // Reset backup markers
    [self->mxSession.crypto.store resetBackupMarkers];
}

- (void)maybeSendKeyBackup
{
    if (_state == MXKeyBackupStateReadyToBackup)
    {
        self.state = MXKeyBackupStateWillBackup;

        // Wait between 0 and 10 seconds, to avoid backup requests from
        // different clients hitting the server all at the same time when a
        // new key is sent
        NSUInteger delayInMs = arc4random_uniform(kMXKeyBackupWaitingTimeToSendKeyBackup);

        MXWeakify(self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInMs * NSEC_PER_MSEC)), mxSession.crypto.cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            [self sendKeyBackup];
        });
    }
    else
    {
        NSLog(@"[MXKeyBackup] maybeSendKeyBackup: Skip it because state: %@", @(_state));
    }
}

- (void)sendKeyBackup
{
    NSArray<MXOlmInboundGroupSession*> *sessions = [mxSession.crypto.store inboundGroupSessionsToBackup:kMXKeyBackupSendKeysMaxCount];

    NSLog(@"[MXKeyBackup] sendKeyBackup: %@ sessions to back up", @(sessions.count));

    if (!sessions.count)
    {
        // Backup is up to date
        return;
    }

    if (_state == MXKeyBackupStateBackingUp || _state == MXKeyBackupStateDisabled)
    {
        // Do nothing if we are already backing up or if the backup has been disabled
        return;
    }

    // Sanity check
    if (!_backupKey || !_keyBackupVersion)
    {
        NSLog(@"[MXKeyBackup] sendKeyBackup: Invalide state: %@", @(_state));
    }

    // Gather data to send to the homeserver
    // roomId -> sessionId -> MXKeyBackupData
    NSMutableDictionary<NSString *,
        NSMutableDictionary<NSString *, MXKeyBackupData*> *> *roomsKeyBackup = [NSMutableDictionary dictionary];

    for (MXOlmInboundGroupSession *session in sessions)
    {
        // Gather information for each key
        // TODO: userId?
        MXDeviceInfo *device = [mxSession.crypto.deviceList deviceWithIdentityKey:session.senderKey forUser:nil andAlgorithm:kMXCryptoMegolmAlgorithm];

        // Build the m.megolm_backup.v1.curve25519-aes-sha2 data as defined at
        // https://github.com/uhoreg/matrix-doc/blob/e2e_backup/proposals/1219-storing-megolm-keys-serverside.md#mmegolm_backupv1curve25519-aes-sha2-key-format
        MXMegolmSessionData *sessionData = session.exportSessionData;
        NSDictionary *sessionBackupData = @{
                                            @"algorithm": sessionData.algorithm,
                                            @"sender_key": sessionData.senderKey,
                                            @"sender_claimed_keys": sessionData.senderClaimedKeys,
                                            @"forwarding_curve25519_key_chain": sessionData.forwardingCurve25519KeyChain ?  sessionData.forwardingCurve25519KeyChain : @[],
                                            @"session_key": sessionData.sessionKey
                                            };
        OLMPkMessage *encryptedSessionBackupData = [_backupKey encryptMessage:[MXTools serialiseJSONObject:sessionBackupData] error:nil];

        // Build backup data for that key
        MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
        keyBackupData.firstMessageIndex = session.session.firstKnownIndex;
        keyBackupData.forwardedCount = session.forwardingCurve25519KeyChain.count;
        keyBackupData.verified = device.verified;
        keyBackupData.sessionData = @{
                                      @"ciphertext": encryptedSessionBackupData.ciphertext,
                                      @"mac": encryptedSessionBackupData.mac,
                                      @"ephemeral": encryptedSessionBackupData.ephemeralKey,
                                      };

        if (!roomsKeyBackup[session.roomId])
        {
            roomsKeyBackup[session.roomId] = [NSMutableDictionary dictionary];
        }
        roomsKeyBackup[session.roomId][sessionData.sessionId] = keyBackupData;
    }

    // Finalise data to send
    NSMutableDictionary<NSString*, MXRoomKeysBackupData*> *rooms = [NSMutableDictionary dictionary];
    for (NSString *roomId in roomsKeyBackup)
    {
        NSMutableDictionary<NSString*, MXKeyBackupData*> *roomSessions = [NSMutableDictionary dictionary];
        for (NSString *sessionId in roomsKeyBackup[roomId])
        {
            roomSessions[sessionId] = roomsKeyBackup[roomId][sessionId];
        }
        MXRoomKeysBackupData *roomKeysBackupData = [MXRoomKeysBackupData new];
        roomKeysBackupData.sessions = roomSessions;

        rooms[roomId] = roomKeysBackupData;
    }

    MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
    keysBackupData.rooms = rooms;

    // Make the request
    MXWeakify(self);
    [mxSession.crypto.matrixRestClient sendKeysBackup:keysBackupData version:_keyBackupVersion.version success:^{
        MXStrongifyAndReturnIfNil(self);

        self.state = MXKeyBackupStateReadyToBackup;

        if (sessions.count < kMXKeyBackupSendKeysMaxCount)
        {
            NSLog(@"[MXKeyBackup] sendKeyBackup: All keys have been backed up");
        }
        else
        {
            NSLog(@"[MXKeyBackup] sendKeyBackup: Continue to back up keys");
            [self sendKeyBackup];
        }

    } failure:^(NSError *error) {
        // TODO: Manage failure
        NSLog(@"[MXKeyBackup] sendKeyBackup: sendKeysBackup failed. Error: %@", error);
    }];
}


#pragma mark - Public methods

- (MXHTTPOperation *)version:(void (^)(MXKeyBackupVersion * _Nonnull))success failure:(void (^)(NSError * _Nonnull))failure
{
    return [mxSession.matrixRestClient keyBackupVersion:success failure:failure];
}

- (void)prepareKeyBackupVersion:(void (^)(MXMegolmBackupCreationInfo *keyBackupCreationInfo))success
                        failure:(nullable void (^)(NSError *error))failure;
{
    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        OLMPkDecryption *decryption = [OLMPkDecryption new];

        NSError *error;
        MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData new];
        authData.publicKey = [decryption generateKey:&error];
        if (error)
        {
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }
        authData.signatures = [self->mxSession.crypto signObject:authData.JSONDictionary];

        MXMegolmBackupCreationInfo *keyBackupCreationInfo = [MXMegolmBackupCreationInfo new];
        keyBackupCreationInfo.algorithm = kMXCryptoMegolmBackupAlgorithm;
        keyBackupCreationInfo.authData = authData;
        keyBackupCreationInfo.recoveryKey = [MXRecoveryKey encode:decryption.privateKey];

        dispatch_async(dispatch_get_main_queue(), ^{
            success(keyBackupCreationInfo);
        });
    });
}

- (MXHTTPOperation*)createKeyBackupVersion:(MXMegolmBackupCreationInfo*)keyBackupCreationInfo
                                   success:(void (^)(void))success
                                   failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    [self setState:MXKeyBackupStateEnabling];

    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Reset backup markers
        [self->mxSession.crypto.store resetBackupMarkers];

        MXKeyBackupVersion *keyBackupVersion = [MXKeyBackupVersion new];
        keyBackupVersion.algorithm = keyBackupCreationInfo.algorithm;
        keyBackupVersion.authData = keyBackupCreationInfo.authData.JSONDictionary;

        MXHTTPOperation *operation2 = [self->mxSession.crypto.matrixRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            keyBackupVersion.version = version;

            [self enableKeyBackup:keyBackupVersion];

            dispatch_async(dispatch_get_main_queue(), ^{
                success();
            });

        } failure:^(NSError *error) {
            if (failure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }];

        if (operation2)
        {
            [operation mutateTo:operation2];
        }
    });

    return operation;
}

- (MXHTTPOperation*)deleteKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
                                   success:(void (^)(void))success
                                   failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // If we're currently backing up to this backup... stop.
        // (We start using it automatically in createKeyBackupVersion
        // so this is symmetrical).
        if ([self.keyBackupVersion.JSONDictionary isEqualToDictionary:keyBackupVersion.JSONDictionary])
        {
            //[self disableKeyBackup];
        }

        MXHTTPOperation *operation2 = [self->mxSession.crypto.matrixRestClient deleteKeysFromBackup:keyBackupVersion.version success:^{

            dispatch_async(dispatch_get_main_queue(), ^{
                success();
            });

        } failure:^(NSError *error) {
            if (failure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }];

        if (operation2)
        {
            [operation mutateTo:operation2];
        }
    });

    return operation;
}

- (BOOL)enabled
{
    return _state != MXKeyBackupStateDisabled;
}


#pragma mark - Private methods

- (void)setState:(MXKeyBackupState)state
{
    _state = state;

    dispatch_async(dispatch_get_main_queue(), ^{
        // TODO
    });
}

@end
