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
#import "MXSession.h"
#import "MXTools.h"
#import "MXError.h"


#pragma mark - Constants definitions

NSString *const kMXKeyBackupDidStateChangeNotification = @"kMXKeyBackupDidStateChangeNotification";

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

    // Observer to kMXKeyBackupDidStateChangeNotification when backupAllGroupSessions is progressing
    id backupAllGroupSessionsObserver;

    // Failure block when backupAllGroupSessions is progressing
    void (^backupAllGroupSessionsFailure)(NSError *error);
}

@end

@implementation MXKeyBackup

#pragma mark - SDK-Private methods -

- (instancetype)initWithMatrixSession:(MXSession *)matrixSession
{
    self = [self init];
    {
        _state = MXKeyBackupStateUnknown;
        mxSession = matrixSession;
    }
    return self;
}

- (void)checkAndStartKeyBackup
{
    self.state = MXKeyBackupStateCheckingBackUpOnHomeserver;

    MXWeakify(self);
    [self version:^(MXKeyBackupVersion * _Nullable keyBackupVersion) {
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        dispatch_async(self->mxSession.crypto.cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            if (!keyBackupVersion)
            {
                NSLog(@"[MXKeyBackup] checkAndStartKeyBackup: Found no key backup version on the homeserver");
                [self disableKeyBackup];
                return;
            }

            MXWeakify(self);
            [self isKeyBackupTrusted:keyBackupVersion onComplete:^(MXKeyBackupVersionTrust * _Nonnull trustInfo) {
                MXStrongifyAndReturnIfNil(self);

                self.state = MXKeyBackupStateDisabled;

                if (trustInfo.usable)
                {
                    NSLog(@"[MXKeyBackup] checkAndStartKeyBackup: Found usable key backup. version: %@", keyBackupVersion.version);
                    if (!self.keyBackupVersion)
                    {
                        // Check the version we used at the previous app run
                        NSString *versionInStore = self->mxSession.crypto.store.backupVersion;
                        if (versionInStore && ![versionInStore isEqualToString:keyBackupVersion.version])
                        {
                            NSLog(@"[MXKeyBackup] -> clean the previously used version(%@)", versionInStore);
                            [self disableKeyBackup];
                        }

                        NSLog(@"[MXKeyBackup]    -> enabling key backups");
                        [self enableKeyBackup:keyBackupVersion];
                    }
                    else if ([self.keyBackupVersion.version isEqualToString:keyBackupVersion.version])
                    {
                        NSLog(@"[MXKeyBackup]    -> same backup version(%@). Keep using it", self.keyBackupVersion.version);
                    }
                    else
                    {
                        NSLog(@"[MXKeyBackup]    -> disable the current version(%@) and enabling the new one", self.keyBackupVersion.version);
                        [self disableKeyBackup];
                        [self enableKeyBackup:keyBackupVersion];
                    }
                }
                else
                {
                    NSLog(@"[MXKeyBackup] checkAndStartKeyBackup: No usable key backup. version: %@", keyBackupVersion.version);
                    if (!self.keyBackupVersion)
                    {
                        NSLog(@"[MXKeyBackup]    -> not enabling key backup");
                    }
                    else
                    {
                        NSLog(@"[MXKeyBackup]    -> disabling key backup");
                        [self disableKeyBackup];
                    }
                }
            }];
        });

    } failure:^(NSError * _Nonnull error) {
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        dispatch_async(self->mxSession.crypto.cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            NSLog(@"[MXKeyBackup] checkAndStartKeyBackup: Failed to get current version: %@", error);
            self.state = MXKeyBackupStateUnknown;
        });
    }];
}

/**
 Enable backing up of keys.

 @param keyBackupVersion backup information object as returned by `[MXKeyBackup version]`.
 @return an error if the operation fails.
 */
- (NSError*)enableKeyBackup:(MXKeyBackupVersion*)version
{
    MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData modelFromJSON:version.authData];
    if (authData)
    {
        _keyBackupVersion = version;
        self->mxSession.crypto.store.backupVersion = version.version;
        _backupKey = [OLMPkEncryption new];
        [_backupKey setRecipientKey:authData.publicKey];

        self.state = MXKeyBackupStateReadyToBackUp;
        
        [self maybeSendKeyBackup];

        return nil;
    }

    return [NSError errorWithDomain:MXKeyBackupErrorDomain
                               code:MXKeyBackupErrorInvalidParametersCode
                           userInfo:@{
                                      NSLocalizedDescriptionKey: @"Invalid authentication data",
                                      }];
}

- (void)disableKeyBackup
{
    [self resetBackupAllGroupSessionsObjects];
    
    _keyBackupVersion = nil;
    self->mxSession.crypto.store.backupVersion = nil;
    _backupKey = nil;
    self.state = MXKeyBackupStateDisabled;

    // Reset backup markers
    [self->mxSession.crypto.store resetBackupMarkers];
}

- (void)maybeSendKeyBackup
{
    if (_state == MXKeyBackupStateReadyToBackUp)
    {
        self.state = MXKeyBackupStateWillBackUp;

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

        if (self.state == MXKeyBackupStateUnknown)
        {
            // If not already done, check for a valid backup version on the homeserver.
            // If one, maybeSendKeyBackup will be called again.
            [self checkAndStartKeyBackup];
        }
    }
}

- (void)sendKeyBackup
{
    NSLog(@"[MXKeyBackup] sendKeyBackup");

    // Get a chunk of keys to backup
    NSArray<MXOlmInboundGroupSession*> *sessions = [mxSession.crypto.store inboundGroupSessionsToBackup:kMXKeyBackupSendKeysMaxCount];

    NSLog(@"[MXKeyBackup] sendKeyBackup: 1 - %@ sessions to back up", @(sessions.count));

    if (!sessions.count)
    {
        // Backup is up to date
        self.state = MXKeyBackupStateReadyToBackUp;
        return;
    }

    if (_state == MXKeyBackupStateBackingUp)
    {
        // Do nothing if we are already backing up
        return;
    }

    // Sanity check
    if (!self.enabled || !_backupKey || !_keyBackupVersion)
    {
        NSLog(@"[MXKeyBackup] sendKeyBackup: Invalid state: %@", @(_state));
        if (backupAllGroupSessionsFailure)
        {
            NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                                 code:MXKeyBackupErrorInvalidStateCode
                                             userInfo:@{
                                                        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid state (%@) for making a backup", @(_state)]
                                                        }];
            backupAllGroupSessionsFailure(error);
        }
        return;
    }

    self.state = MXKeyBackupStateBackingUp;

    NSLog(@"[MXKeyBackup] sendKeyBackup: 2 - Encrypting keys");

    // Gather data to send to the homeserver
    // roomId -> sessionId -> MXKeyBackupData
    NSMutableDictionary<NSString *,
        NSMutableDictionary<NSString *, MXKeyBackupData*> *> *roomsKeyBackup = [NSMutableDictionary dictionary];

    for (MXOlmInboundGroupSession *session in sessions)
    {
        MXKeyBackupData *keyBackupData = [self encryptGroupSession:session];

        if (!roomsKeyBackup[session.roomId])
        {
            roomsKeyBackup[session.roomId] = [NSMutableDictionary dictionary];
        }
        roomsKeyBackup[session.roomId][session.session.sessionIdentifier] = keyBackupData;
    }

    NSLog(@"[MXKeyBackup] sendKeyBackup: 3 - Finalising data to send");

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

    NSLog(@"[MXKeyBackup] sendKeyBackup: 4 - Sending request");

    // Make the request
    MXWeakify(self);
    [mxSession.crypto.matrixRestClient sendKeysBackup:keysBackupData version:_keyBackupVersion.version success:^{
        MXStrongifyAndReturnIfNil(self);

        NSLog(@"[MXKeyBackup] sendKeyBackup: 5a - Request complete");

        // Mark keys as backed up
        for (MXOlmInboundGroupSession *session in sessions)
        {
            [self->mxSession.crypto.store markBackupDoneForInboundGroupSessionWithId:session.session.sessionIdentifier andSenderKey:session.senderKey];
        }

        if (sessions.count < kMXKeyBackupSendKeysMaxCount)
        {
            NSLog(@"[MXKeyBackup] sendKeyBackup: All keys have been backed up");
            self.state = MXKeyBackupStateReadyToBackUp;
        }
        else
        {
            NSLog(@"[MXKeyBackup] sendKeyBackup: Continue to back up keys");
            self.state = MXKeyBackupStateWillBackUp;

            [self sendKeyBackup];
        }

    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        NSLog(@"[MXKeyBackup] sendKeyBackup: 5b - sendKeysBackup failed. Error: %@", error);

        void (^backupAllGroupSessionsFailure)(NSError *error) = self->backupAllGroupSessionsFailure;

        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if ([mxError.errcode isEqualToString:kMXErrCodeStringBackupWrongKeysVersion])
        {
            [self disableKeyBackup];
            self.state = MXKeyBackupStateWrongBackUpVersion;
        }
        else
        {
            // Retry a bit later
            self.state = MXKeyBackupStateReadyToBackUp;
            [self maybeSendKeyBackup];
        }

        if (backupAllGroupSessionsFailure)
        {
            backupAllGroupSessionsFailure(error);
        }
    }];
}


#pragma mark - Public methods -

#pragma mark - Backup management

- (MXHTTPOperation *)version:(void (^)(MXKeyBackupVersion * _Nullable))success failure:(void (^)(NSError * _Nonnull))failure
{
    // Use mxSession.matrixRestClient to respond to the main thread as this method is public
    return [mxSession.matrixRestClient keyBackupVersion:success failure:^(NSError *error) {

        // Workaround because the homeserver currently returns  M_NOT_FOUND when there is
        // no key backup
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if ([mxError.errcode isEqualToString:kMXErrCodeStringNotFound])
        {
            if (success)
            {
                success(nil);
            }
        }
        else if (failure)
        {
            failure(error);
        }
    }];
}

- (void)isKeyBackupTrusted:(MXKeyBackupVersion *)keyBackupVersion onComplete:(void (^)(MXKeyBackupVersionTrust * _Nonnull))onComplete
{
    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSString *myUserId = self->mxSession.myUser.userId;

        MXKeyBackupVersionTrust *keyBackupVersionTrust = [MXKeyBackupVersionTrust new];

        MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData modelFromJSON:keyBackupVersion.authData];
        if (!keyBackupVersion.algorithm || !authData
            || !authData.publicKey || !authData.signatures)
        {
            NSLog(@"[MXKeyBackup] isKeyBackupTrusted: Key backup is absent or missing required data");
            dispatch_async(dispatch_get_main_queue(), ^{
                onComplete(keyBackupVersionTrust);
            });
            return;
        }

        NSDictionary *mySigs = authData.signatures[myUserId];
        if (mySigs.count == 0)
        {
            NSLog(@"[MXKeyBackup] isKeyBackupTrusted: Ignoring key backup because it lacks any signatures from this user");
            dispatch_async(dispatch_get_main_queue(), ^{
                onComplete(keyBackupVersionTrust);
            });
            return;
        }

        NSMutableArray<MXKeyBackupVersionTrustSignature*> *signatures = [NSMutableArray array];
        for (NSString *keyId in mySigs)
        {
            // XXX: is this how we're supposed to get the device id?
            NSString *deviceId;
            NSArray<NSString *> *components = [keyId componentsSeparatedByString:@":"];
            if (components.count == 2)
            {
                deviceId = components[1];
            }

            MXDeviceInfo *device;
            if (deviceId)
            {
                device = [self->mxSession.crypto.deviceList storedDevice:myUserId deviceId:deviceId];
            }
            if (!device)
            {
                NSLog(@"[MXKeyBackup] isKeyBackupTrusted: Ignoring signature from unknown key %@", deviceId);
                continue;
            }

            NSError *error;
            BOOL valid = [self->mxSession.crypto.olmDevice verifySignature:device.fingerprint JSON:authData.signalableJSONDictionary signature:mySigs[keyId] error:&error];

            if (!valid)
            {
                NSLog(@"[MXKeyBackup] isKeyBackupTrusted: Bad signature from device %@: %@", device.deviceId, error);
            }
            else if (device.verified)
            {
                keyBackupVersionTrust.usable = YES;
            }

            MXKeyBackupVersionTrustSignature *signature = [MXKeyBackupVersionTrustSignature new];
            signature.device = device;
            signature.valid = valid;

            [signatures addObject:signature];
        }

        keyBackupVersionTrust.signatures = signatures;

        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(keyBackupVersionTrust);
        });
    });
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
        authData.signatures = [self->mxSession.crypto signObject:authData.signalableJSONDictionary];

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
                                   success:(void (^)(MXKeyBackupVersion *keyBackupVersion))success
                                   failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    [self setState:MXKeyBackupStateEnabling];

    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        MXKeyBackupVersion *keyBackupVersion = [MXKeyBackupVersion new];
        keyBackupVersion.algorithm = keyBackupCreationInfo.algorithm;
        keyBackupVersion.authData = keyBackupCreationInfo.authData.JSONDictionary;

        MXHTTPOperation *operation2 = [self->mxSession.crypto.matrixRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            // Reset backup markers
            [self->mxSession.crypto.store resetBackupMarkers];

            keyBackupVersion.version = version;

            NSError *error = [self enableKeyBackup:keyBackupVersion];

            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error)
                {
                    success(keyBackupVersion);
                }
                else if (failure)
                {
                    failure(error);
                }
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

- (MXHTTPOperation*)deleteKeyBackupVersion:(NSString*)version
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
        if ([self.keyBackupVersion.version isEqualToString:version])
        {
            [self disableKeyBackup];
            self.state = MXKeyBackupStateUnknown;
        }

        MXHTTPOperation *operation2 = [self->mxSession.crypto.matrixRestClient deleteKeysFromBackup:version success:^{

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


#pragma mark - Backup storing

- (void)backupAllGroupSessions:(nullable void (^)(void))success
                      progress:(nullable void (^)(NSProgress *backupProgress))progress
                       failure:(nullable void (^)(NSError *error))failure;
{
    // Get a status right now
    MXWeakify(self);
    [self backupProgress:^(NSProgress * _Nonnull backupProgress) {
        MXStrongifyAndReturnIfNil(self);

        // Reset previous state if any
        [self resetBackupAllGroupSessionsObjects];

        NSLog(@"[MXKeyBackup] backupAllGroupSessions: backupProgress: %@", backupProgress);

        if (progress)
        {
            progress(backupProgress);
        }

        if (backupProgress.finished)
        {
            NSLog(@"[MXKeyBackup] backupAllGroupSessions: complete");
            if (success)
            {
                success();
            }
            return;
        }

        // Listen to `self.state` change to determine when to call onBackupProgress and onComplete
        MXWeakify(self);
        self->backupAllGroupSessionsObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKeyBackupDidStateChangeNotification object:self queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
            MXStrongifyAndReturnIfNil(self);

            [self backupProgress:^(NSProgress * _Nonnull backupProgress) {

                if (progress)
                {
                    progress(backupProgress);
                }

                if (self.state == MXKeyBackupStateReadyToBackUp)
                {
                    [self resetBackupAllGroupSessionsObjects];

                    if (success)
                    {
                        success();
                    }
                }
            }];
        }];

        dispatch_async(self->mxSession.crypto.cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            // Listen to error
            if (failure)
            {
                MXWeakify(self);
                self->backupAllGroupSessionsFailure = ^(NSError *error) {
                    MXStrongifyAndReturnIfNil(self);

                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure(error);
                    });

                    [self resetBackupAllGroupSessionsObjects];
                };
            }

            [self sendKeyBackup];
        });
    }];
}

- (void)resetBackupAllGroupSessionsObjects
{
    if (backupAllGroupSessionsObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:backupAllGroupSessionsObserver];
        backupAllGroupSessionsObserver = nil;
    }
    backupAllGroupSessionsFailure = nil;
}

- (void)backupProgress:(void (^)(NSProgress *backupProgress))backupProgress
{
    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSUInteger keys = [self->mxSession.crypto.store inboundGroupSessionsCount:NO];
        NSUInteger backedUpkeys = [self->mxSession.crypto.store inboundGroupSessionsCount:YES];

        NSProgress *progress = [NSProgress progressWithTotalUnitCount:keys];
        progress.completedUnitCount = backedUpkeys;

        dispatch_async(dispatch_get_main_queue(), ^{
            backupProgress(progress);
        });
     });
}


#pragma mark - Backup restoring

+ (BOOL)isValidRecoveryKey:(NSString*)recoveryKey
{
    NSError *error;
    NSData *privateKeyOut = [MXRecoveryKey decode:recoveryKey error:&error];

    return !error && privateKeyOut;
}

- (MXHTTPOperation*)restoreKeyBackup:(NSString*)version
                         recoveryKey:(NSString*)recoveryKey
                                room:(nullable NSString*)roomId
                             session:(nullable NSString*)sessionId
                             success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                             failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    NSLog(@"[MXKeyBackup] restoreKeyBackup: From backup version: %@", version);

    MXWeakify(self);
    dispatch_async(mxSession.crypto.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Get a PK decryption instance
        NSError *error;
        OLMPkDecryption *decryption = [self pkDecryptionFromRecoveryKey:recoveryKey error:&error];
        if (error)
        {
            NSLog(@"[MXKeyBackup] restoreKeyBackup: Invalid recovery key. Error: %@", error);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }

        // Get backup from the homeserver
        MXWeakify(self);
        MXHTTPOperation *operation2 = [self keyBackupForSession:sessionId inRoom:roomId version:version success:^(MXKeysBackupData *keysBackupData) {
            MXStrongifyAndReturnIfNil(self);

            NSMutableArray<MXMegolmSessionData*> *sessionDatas = [NSMutableArray array];

            // Restore that data
            for (NSString *roomId in keysBackupData.rooms)
            {
                for (NSString *sessionId in keysBackupData.rooms[roomId].sessions)
                {
                    MXKeyBackupData *keyBackupData = keysBackupData.rooms[roomId].sessions[sessionId];

                    MXMegolmSessionData *sessionData = [self decryptKeyBackupData:keyBackupData forSession:sessionId inRoom:roomId withPkDecryption:decryption];

                    if (sessionData)
                    {
                        [sessionDatas addObject:sessionData];
                    }
                }
            }

            NSLog(@"[MXKeyBackup] restoreKeyBackup: Got %@ keys from the backup store on the homeserver", @(sessionDatas.count));

            // Do not trigger a backup for them if they come from the backup version we are using
            BOOL backUp = ![version isEqualToString:self.keyBackupVersion.version];
            if (backUp)
            {
                NSLog(@"[MXKeyBackup] restoreKeyBackup: Those keys will be backed up to backup version: %@", self.keyBackupVersion.version);
            }

            // Import them into the crypto store
            [self->mxSession.crypto importMegolmSessionDatas:sessionDatas backUp:backUp success:success failure:^(NSError *error) {
                if (failure)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure(error);
                    });
                }
            }];

        } failure:^(NSError *error) {
            if (failure)
            {
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


#pragma mark - Backup state

- (BOOL)enabled
{
    return _state >= MXKeyBackupStateReadyToBackUp;
}


#pragma mark - Private methods -

- (void)setState:(MXKeyBackupState)state
{
    NSLog(@"[MXKeyBackup] setState: %@ -> %@", @(_state), @(state));

    _state = state;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXKeyBackupDidStateChangeNotification object:self];
    });
}

// Same method as [MXRestClient keysBackupInRoom] except that it accepts nullable
// parameters and always returns a MXKeysBackupData object
- (MXHTTPOperation*)keyBackupForSession:(nullable NSString*)sessionId
                                 inRoom:(nullable NSString*)roomId
                                version:(NSString*)version
                                success:(void (^)(MXKeysBackupData *keysBackupData))success
                                failure:(void (^)(NSError *error))failure;
{
    MXHTTPOperation *operation;

    if (!sessionId && !roomId)
    {
        operation = [mxSession.crypto.matrixRestClient keysBackup:version success:success failure:failure];
    }
    else if (!sessionId)
    {
        operation = [mxSession.crypto.matrixRestClient keysBackupInRoom:roomId version:version success:^(MXRoomKeysBackupData *roomKeysBackupData) {

            MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
            keysBackupData.rooms = @{
                                     roomId: roomKeysBackupData
                                     };

            success(keysBackupData);

        } failure:failure];
    }
    else
    {
        operation =  [mxSession.crypto.matrixRestClient keyBackupForSession:sessionId inRoom:roomId version:version success:^(MXKeyBackupData *keyBackupData) {

            MXRoomKeysBackupData *roomKeysBackupData = [MXRoomKeysBackupData new];
            roomKeysBackupData.sessions = @{
                                            sessionId: keyBackupData
                                            };

            MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
            keysBackupData.rooms = @{
                                     roomId: roomKeysBackupData
                                     };

            success(keysBackupData);

        } failure:failure];
    }

    return operation;
}

- (OLMPkDecryption*)pkDecryptionFromRecoveryKey:(NSString*)recoveryKey error:(NSError **)error
{
    // Extract the primary key
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:error];

    // Built the PK decryption with it
    OLMPkDecryption *decryption;
    if (privateKey)
    {
        decryption = [OLMPkDecryption new];
        [decryption setPrivateKey:privateKey error:error];
    }

    return decryption;
}

- (MXKeyBackupData*)encryptGroupSession:(MXOlmInboundGroupSession*)session
{
    // Gather information for each key
    MXDeviceInfo *device = [mxSession.crypto.deviceList deviceWithIdentityKey:session.senderKey andAlgorithm:kMXCryptoMegolmAlgorithm];

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

    return keyBackupData;
}

- (MXMegolmSessionData*)decryptKeyBackupData:(MXKeyBackupData*)keyBackupData forSession:(NSString*)sessionId inRoom:(NSString*)roomId withPkDecryption:(OLMPkDecryption*)decryption
{
    MXMegolmSessionData *sessionData;

    NSString *ciphertext, *mac, *ephemeralKey;

    MXJSONModelSetString(ciphertext, keyBackupData.sessionData[@"ciphertext"]);
    MXJSONModelSetString(mac, keyBackupData.sessionData[@"mac"]);
    MXJSONModelSetString(ephemeralKey, keyBackupData.sessionData[@"ephemeral"]);

    if (ciphertext && mac && ephemeralKey)
    {
        OLMPkMessage *encrypted = [[OLMPkMessage alloc] initWithCiphertext:ciphertext mac:mac ephemeralKey:ephemeralKey];

        NSError *error;
        NSString *text = [decryption decryptMessage:encrypted error:&error];

        if (!error)
        {
            NSDictionary *sessionBackupData = [MXTools deserialiseJSONString:text];

            if (sessionBackupData)
            {
                MXJSONModelSetMXJSONModel(sessionData, MXMegolmSessionData, sessionBackupData);

                sessionData.sessionId = sessionId;
                sessionData.roomId = roomId;
            }
        }
        else
        {
            NSLog(@"[MXKeyBackup] decryptKeyBackupData: Failed to decrypt session from backup. Error: %@", error);
        }
    }

    return sessionData;
}

@end
