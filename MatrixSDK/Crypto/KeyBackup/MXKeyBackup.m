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
#import "MXKeyBackupPassword.h"
#import "MXSession.h"
#import "MXTools.h"
#import "MXBase64Tools.h"
#import "MXError.h"
#import "MXKeyProvider.h"
#import "MXRawDataKey.h"
#import "MXCrossSigning_Private.h"

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
    __weak MXCrypto *crypto;

    // The queue to run background tasks
    dispatch_queue_t cryptoQueue;

    // Observer to kMXKeyBackupDidStateChangeNotification when backupAllGroupSessions is progressing
    id backupAllGroupSessionsObserver;

    // Failure block when backupAllGroupSessions is progressing
    void (^backupAllGroupSessionsFailure)(NSError *error);
}

@end

@implementation MXKeyBackup

#pragma mark - SDK-Private methods -

- (instancetype)initWithCrypto:(MXCrypto *)theCrypto
{
    self = [self init];
    {
        _state = MXKeyBackupStateUnknown;
        crypto = theCrypto;
        cryptoQueue = crypto.cryptoQueue;
    }
    return self;
}

- (void)checkAndStartKeyBackup
{
    if (self.state != MXKeyBackupStateUnknown
        && self.state != MXKeyBackupStateDisabled
        && self.state != MXKeyBackupStateWrongBackUpVersion
        && self.state != MXKeyBackupStateNotTrusted)
    {
        // Try to start or restart the backup only if it is in unknown or bad state
        return;
    }

    self->_keyBackupVersion = nil;
    self.state = MXKeyBackupStateCheckingBackUpOnHomeserver;

    MXWeakify(self);
    [self versionFromCryptoQueue:nil success:^(MXKeyBackupVersion * _Nullable keyBackupVersion) {
        MXStrongifyAndReturnIfNil(self);

        [self checkAndStartWithKeyBackupVersion:keyBackupVersion];

    } failure:^(NSError * _Nonnull error) {
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXKeyBackup] checkAndStartKeyBackup: Failed to get current version: %@", error);
        self.state = MXKeyBackupStateUnknown;
    }];
}

- (void)checkAndStartWithKeyBackupVersion:(nullable MXKeyBackupVersion*)keyBackupVersion
{
    MXLogDebug(@"[MXKeyBackup] checkAndStartWithKeyBackupVersion: %@", keyBackupVersion.version);
 
    self->_keyBackupVersion = keyBackupVersion;
    if (!self.keyBackupVersion)
    {
        [self resetKeyBackupData];
        self.state = MXKeyBackupStateDisabled;
        return;
    }

    MXKeyBackupVersionTrust *trustInfo = [self trustForKeyBackupVersionFromCryptoQueue:keyBackupVersion];

    if (trustInfo.usable)
    {
        MXLogDebug(@"[MXKeyBackup] checkAndStartWithKeyBackupVersion: Found usable key backup. version: %@", keyBackupVersion.version);

        // Check the version we used at the previous app run
        NSString *versionInStore = crypto.store.backupVersion;
        if (versionInStore && ![versionInStore isEqualToString:keyBackupVersion.version])
        {
            MXLogDebug(@"[MXKeyBackup] -> clean the previously used version(%@)", versionInStore);
            [self resetKeyBackupData];
        }
        
        // Check private keys
        if (self.hasPrivateKeyInCryptoStore)
        {
            NSString *pKDecryptionPublicKey = [self pkDecrytionPublicKeyFromCryptoStore];
            
            if (![self checkPkDecryptionPublicKey:pKDecryptionPublicKey forKeyBackupVersion:keyBackupVersion])
            {
                MXLogDebug(@"[MXKeyBackup] -> clean local private key (%@)", pKDecryptionPublicKey);
                [crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
            }
        }
        
        MXLogDebug(@"[MXKeyBackup]    -> enabling key backups");
        [self enableKeyBackup:keyBackupVersion];
    }
    else
    {
        MXLogDebug(@"[MXKeyBackup] checkAndStartWithKeyBackupVersion: No usable key backup. version: %@", keyBackupVersion.version);

        if (crypto.store.backupVersion)
        {
            MXLogDebug(@"[MXKeyBackup]    -> disable the current version");
            [self resetKeyBackupData];
        }

        self.state = MXKeyBackupStateNotTrusted;
    }
}

/**
 Enable backing up of keys.

 @param version backup information object as returned by `[MXKeyBackup version]`.
 @return an error if the operation fails.
 */
- (NSError*)enableKeyBackup:(MXKeyBackupVersion*)version
{
    NSError *error;
    MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:version error:&error];
    if (!error)
    {
        _keyBackupVersion = version;
        self->crypto.store.backupVersion = version.version;
        _backupKey = [OLMPkEncryption new];
        [_backupKey setRecipientKey:authData.publicKey];

        self.state = MXKeyBackupStateReadyToBackUp;
        
        [self maybeSendKeyBackup];
    }

    return error;
}

- (void)resetKeyBackupData
{
    MXLogDebug(@"[MXKeyBackup] resetKeyBackupData");
    
    [self resetBackupAllGroupSessionsObjects];
    
    self->crypto.store.backupVersion = nil;
    [self->crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
   _backupKey = nil;

    // Reset backup markers
    [self->crypto.store resetBackupMarkers];
}

- (void)maybeSendKeyBackup
{
    if (_state == MXKeyBackupStateReadyToBackUp)
    {
        self.state = MXKeyBackupStateWillBackUp;

        MXLogDebug(@"[MXKeyBackup] maybeSendKeyBackup: ready to send keybackup");

        // Wait between 0 and 10 seconds, to avoid backup requests from
        // different clients hitting the server all at the same time when a
        // new key is sent
        NSUInteger delayInMs = arc4random_uniform(kMXKeyBackupWaitingTimeToSendKeyBackup);

        MXWeakify(self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInMs * NSEC_PER_MSEC)), cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            [self sendKeyBackup];
        });
    }
    else
    {
        MXLogDebug(@"[MXKeyBackup] maybeSendKeyBackup: Skip it because state: %@", @(_state));

        // If not already done, check for a valid backup version on the homeserver.
        // If one, maybeSendKeyBackup will be called again.
        [self checkAndStartKeyBackup];
    }
}

- (void)sendKeyBackup
{
    MXLogDebug(@"[MXKeyBackup] sendKeyBackup");

    // Get a chunk of keys to backup
    NSArray<MXOlmInboundGroupSession*> *sessions = [crypto.store inboundGroupSessionsToBackup:kMXKeyBackupSendKeysMaxCount];

    MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 1 - %@ sessions to back up", @(sessions.count));

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
        MXLogDebug(@"[MXKeyBackup] sendKeyBackup: Invalid state: %@", @(_state));
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

    MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 2 - Encrypting keys");

    // Gather data to send to the homeserver
    // roomId -> sessionId -> MXKeyBackupData
    NSMutableDictionary<NSString *,
        NSMutableDictionary<NSString *, MXKeyBackupData*> *> *roomsKeyBackup = [NSMutableDictionary dictionary];

    for (MXOlmInboundGroupSession *session in sessions)
    {
        MXKeyBackupData *keyBackupData = [self encryptGroupSession:session];

        if (keyBackupData)
        {
            if (!roomsKeyBackup[session.roomId])
            {
                roomsKeyBackup[session.roomId] = [NSMutableDictionary dictionary];
            }
            roomsKeyBackup[session.roomId][session.session.sessionIdentifier] = keyBackupData;
        }
    }

    MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 3 - Finalising data to send");

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

    MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 4 - Sending request");

    // Make the request
    MXWeakify(self);
    [crypto.matrixRestClient sendKeysBackup:keysBackupData version:_keyBackupVersion.version success:^{
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 5a - Request complete");

        // Mark keys as backed up
        [self->crypto.store markBackupDoneForInboundGroupSessions:sessions];

        if (sessions.count < kMXKeyBackupSendKeysMaxCount)
        {
            MXLogDebug(@"[MXKeyBackup] sendKeyBackup: All keys have been backed up");
            self.state = MXKeyBackupStateReadyToBackUp;
        }
        else
        {
            MXLogDebug(@"[MXKeyBackup] sendKeyBackup: Continue to back up keys");
            self.state = MXKeyBackupStateWillBackUp;

            [self sendKeyBackup];
        }

    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXKeyBackup] sendKeyBackup: 5b - sendKeysBackup failed. Error: %@", error);

        void (^backupAllGroupSessionsFailure)(NSError *error) = self->backupAllGroupSessionsFailure;

        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if ([mxError.errcode isEqualToString:kMXErrCodeStringBackupWrongKeysVersion])
        {
            [self resetKeyBackupData];
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

- (void)requestPrivateKeys:(void (^)(void))onComplete
{
    MXLogDebug(@"[MXKeyBackup] requestPrivateKeys");
          
    [self requestPrivateKeysToDeviceIds:nil success:^{
    } onPrivateKeysReceived:^{
        
        [self restoreKeyBackupAutomaticallyWithPrivateKey:onComplete];
        
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXKeyBackup] requestPrivateKeys. Error for requestPrivateKeys: %@", error);
        onComplete();
    }];
}

- (void)restoreKeyBackupAutomaticallyWithPrivateKey:(void (^)(void))onComplete
{
    // Check we have alreaded loaded the backup before going further
    MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically: Current backup version %@", self.keyBackupVersion);
    if (!self.keyBackupVersion)
    {
        // Backup not yet retrieved?
        [self forceRefresh:^(BOOL usingLastVersion) {
            if (self.keyBackupVersion)
            {
                // Try again
                [self restoreKeyBackupAutomaticallyWithPrivateKey:onComplete];
            }
        } failure:^(NSError * _Nonnull error) {
            MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically: Cannot fetch backup version. Error: %@", error);
        }];
        return;
    }
    
    // Check private keys
    if (!self.hasPrivateKeyInCryptoStore)
    {
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically. Error: No private key");
        onComplete();
        return;
    }
    
    // Check private keys validity
    NSString *pKDecryptionPublicKey = [self pkDecrytionPublicKeyFromCryptoStore];
    if (![self checkPkDecryptionPublicKey:pKDecryptionPublicKey forKeyBackupVersion:self.keyBackupVersion])
    {
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically. Error: Invalid private key (%@)", pKDecryptionPublicKey);
        [crypto.store deleteSecretWithSecretId:MXSecretId.keyBackup];
        onComplete();
        return;
    }
    
    // Do the restore operation in background
    [self restoreUsingPrivateKeyKeyBackup:self.keyBackupVersion room:nil session:nil success:^(NSUInteger total, NSUInteger imported) {
        
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically: Restored %@ keys out of %@", @(imported), @(total));
        onComplete();
        
    } failure:^(NSError * _Nonnull error) {
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically. Error for restoreKeyBackup: %@", error);
        onComplete();
    }];
}


#pragma mark - Public methods -

#pragma mark - Backup management

- (MXHTTPOperation *)version:(NSString *)version success:(void (^)(MXKeyBackupVersion * _Nullable))success failure:(void (^)(NSError * _Nonnull))failure
{
    return [self versionFromCryptoQueue:version success:^(MXKeyBackupVersion * _Nullable keyBackupVersion) {
        if (success)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                success(keyBackupVersion);
            });
        }
    } failure:^(NSError * _Nonnull error) {
        if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
    }];
}

- (MXHTTPOperation *)versionFromCryptoQueue:(NSString *)version success:(void (^)(MXKeyBackupVersion * _Nullable))success failure:(void (^)(NSError * _Nonnull))failure
{
    return [crypto.matrixRestClient keyBackupVersion:version success:success failure:^(NSError *error) {

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

- (void)prepareKeyBackupVersionWithPassword:(NSString *)password
                                    success:(void (^)(MXMegolmBackupCreationInfo * _Nonnull))success
                                    failure:(void (^)(NSError * _Nonnull))failure
{
    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        OLMPkDecryption *decryption = [OLMPkDecryption new];

        NSError *error;
        __block MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData new];
        if (password)
        {
            // Generate a private key from the password
            NSString *salt;
            NSUInteger iterations;
            NSData *privateKey = [MXKeyBackupPassword generatePrivateKeyWithPassword:password
                                                                                salt:&salt
                                                                          iterations:&iterations
                                                                               error:&error];
            if (!error)
            {
                authData.publicKey = [decryption setPrivateKey:privateKey error:&error];
                authData.privateKeySalt = salt;
                authData.privateKeyIterations = iterations;
            }
        }
        else
        {
            authData.publicKey = [decryption generateKey:&error];
        }

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
        
        MXMegolmBackupCreationInfo *keyBackupCreationInfo = [MXMegolmBackupCreationInfo new];
        keyBackupCreationInfo.algorithm = kMXCryptoMegolmBackupAlgorithm;
        keyBackupCreationInfo.authData = authData;
        keyBackupCreationInfo.recoveryKey = [MXRecoveryKey encode:decryption.privateKey];
        
        NSString *myUserId = self->crypto.matrixRestClient.credentials.userId;
        NSMutableDictionary *signatures = [NSMutableDictionary dictionary];
        
        NSDictionary *deviceSignature = [self->crypto signObject:authData.signalableJSONDictionary];
        [signatures addEntriesFromDictionary:deviceSignature[myUserId]];
        
        if ([self->crypto.crossSigning canCrossSign] == NO)
        {
            authData.signatures = @{myUserId: signatures};
            keyBackupCreationInfo.authData = authData;
            
            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success(keyBackupCreationInfo);
                });
            }
            
            return;
        }
        
        [self->crypto.crossSigning signObject:authData.signalableJSONDictionary withKeyType:MXCrossSigningKeyType.master success:^(NSDictionary *signedObject) {
            
            [signatures addEntriesFromDictionary:signedObject[@"signatures"][myUserId]];
            
            authData.signatures = @{myUserId: signatures};
            keyBackupCreationInfo.authData = authData;
            
            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success(keyBackupCreationInfo);
                });
            }
        } failure:^(NSError *error) {
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }];
    });
}

- (MXHTTPOperation*)createKeyBackupVersion:(MXMegolmBackupCreationInfo*)keyBackupCreationInfo
                                   success:(void (^)(MXKeyBackupVersion *keyBackupVersion))success
                                   failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    [self setState:MXKeyBackupStateEnabling];

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        MXKeyBackupVersion *keyBackupVersion = [MXKeyBackupVersion new];
        keyBackupVersion.algorithm = keyBackupCreationInfo.algorithm;
        keyBackupVersion.authData = keyBackupCreationInfo.authData.JSONDictionary;

        MXHTTPOperation *operation2 = [self->crypto.matrixRestClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {

            // Store the fresh new private key
            [self storePrivateKeyWithRecoveryKey:keyBackupCreationInfo.recoveryKey];
            
            // Reset backup markers
            [self->crypto.store resetBackupMarkers];

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
        
        [operation mutateTo:operation2];
    });

    return operation;
}

- (MXHTTPOperation*)deleteKeyBackupVersion:(NSString*)version
                                   success:(void (^)(void))success
                                   failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // If we're currently backing up to this backup... stop.
        // (We start using it automatically in createKeyBackupVersion
        // so this is symmetrical).
        if ([self.keyBackupVersion.version isEqualToString:version])
        {
            [self resetKeyBackupData];
            self->_keyBackupVersion = nil;
            self.state = MXKeyBackupStateUnknown;
        }

        MXWeakify(self);
        MXHTTPOperation *operation2 = [self->crypto.matrixRestClient deleteKeyBackupVersion:version success:^{
            MXStrongifyAndReturnIfNil(self);

            // Do not stay in MXKeyBackupStateUnknown but check what is available on the homeserver
            if (self.state == MXKeyBackupStateUnknown)
            {
                [self checkAndStartKeyBackup];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                success();
            });

        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);

            // Do not stay in MXKeyBackupStateUnknown but check what is available on the homeserver
            if (self.state == MXKeyBackupStateUnknown)
            {
                [self checkAndStartKeyBackup];
            }

            if (failure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }];
        
        [operation mutateTo:operation2];
    });

    return operation;
}

- (MXHTTPOperation*)forceRefresh:(nullable void (^)(BOOL valid))success
                         failure:(nullable void (^)(NSError *error))failure
{
    if (_state == MXKeyBackupStateUnknown || _state == MXKeyBackupStateCheckingBackUpOnHomeserver)
    {
        MXLogDebug(@"[MXKeyBackup] forceRefresh: Invalid state (%@) to force the refresh", @(_state));
        if (failure)
        {
            NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                                 code:MXKeyBackupErrorInvalidStateCode
                                             userInfo:@{
                                                 NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid state (%@) to force the refresh of the backup", @(_state)]
                                             }];
            failure(error);
        }
        return nil;
    }
    
    // Fetch the last backup version on the server, compare it to the backup version
    // currently used. If versions are not the same, the current backup is forgotten and
    // checkAndStartKeyBackup is called in order to restart on the last version on the HS.
    MXWeakify(self);
    return [self versionFromCryptoQueue:nil success:^(MXKeyBackupVersion * _Nullable serverKeyBackupVersion) {
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        dispatch_async(self->cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);

            BOOL usingLastVersion = NO;

            if ((serverKeyBackupVersion && [serverKeyBackupVersion.version isEqualToString:self.keyBackupVersion.version])
                || (serverKeyBackupVersion == self.keyBackupVersion)) // both nil
            {
                usingLastVersion = YES;
            }
            else
            {
                MXLogDebug(@"[MXKeyBackup] forceRefresh: New version detected on the homeserver. New version: %@. Old version: %@", serverKeyBackupVersion.version, self.keyBackupVersion.version);
                usingLastVersion = NO;

                // Stop current backup or start a new one
                self->_keyBackupVersion = nil;
                [self resetKeyBackupData];
                self.state = MXKeyBackupStateUnknown;
                [self checkAndStartWithKeyBackupVersion:serverKeyBackupVersion];
            }

            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success(usingLastVersion);
                });
            }

        });

    } failure:failure];
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

        MXLogDebug(@"[MXKeyBackup] backupAllGroupSessions: backupProgress: %@", backupProgress);

        if (progress)
        {
            progress(backupProgress);
        }

        if (backupProgress.finished)
        {
            MXLogDebug(@"[MXKeyBackup] backupAllGroupSessions: complete");
            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success();
                });
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
                    dispatch_async(dispatch_get_main_queue(), ^{
                        progress(backupProgress);
                    });
                }

                if (self.state == MXKeyBackupStateReadyToBackUp)
                {
                    [self resetBackupAllGroupSessionsObjects];

                    if (success)
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            success();
                        });
                    }
                }
            }];
        }];

        dispatch_async(self->cryptoQueue, ^{
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
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSUInteger keys = [self->crypto.store inboundGroupSessionsCount:NO];
        NSUInteger backedUpkeys = [self->crypto.store inboundGroupSessionsCount:YES];

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

- (MXHTTPOperation*)restoreKeyBackup:(MXKeyBackupVersion*)keyBackupVersion
                     withRecoveryKey:(NSString*)recoveryKey
                                room:(nullable NSString*)roomId
                             session:(nullable NSString*)sessionId
                             success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                             failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXLogDebug(@"[MXKeyBackup] restoreKeyBackup with recovery key: From backup version: %@", keyBackupVersion.version);

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Check if the recovery is valid before going any further
        NSError *error;
        [self isValidRecoveryKey:recoveryKey forKeyBackupVersion:keyBackupVersion error:&error];
        if (error)
        {
            MXLogDebug(@"[MXKeyBackup] restoreKeyBackup: Invalid recovery key. Error: %@", error);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }

        // Get the PK decryption instance
        // The operation always succeeds if the recovery key is valid
        OLMPkDecryption *decryption = [self pkDecryptionFromRecoveryKey:recoveryKey error:&error];
        if (decryption)
        {
            MXHTTPOperation *operation2 = [self restoreKeyBackup:keyBackupVersion withPkDecryption:decryption room:roomId session:sessionId success:^(NSUInteger total, NSUInteger imported) {
                
                // Catch the private key from the recovery key and store it locally
                if ([self.keyBackupVersion.version isEqualToString:keyBackupVersion.version])
                {
                    [self storePrivateKeyWithRecoveryKey:recoveryKey];
                }
                
                if (success)
                {
                    success(total, imported);
                }
            } failure:failure];
            [operation mutateTo:operation2];
        }
        else if (failure)
        {
            failure(error);
        }
    });

    return operation;
}

- (MXHTTPOperation*)restoreKeyBackup:(MXKeyBackupVersion*)keyBackupVersion
                    withPkDecryption:(OLMPkDecryption*)decryption
                                room:(nullable NSString*)roomId
                             session:(nullable NSString*)sessionId
                             success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                             failure:(nullable void (^)(NSError *error))failure
{
    // Get backup from the homeserver
    MXWeakify(self);
    return [self keyBackupForSession:sessionId inRoom:roomId version:keyBackupVersion.version success:^(MXKeysBackupData *keysBackupData) {
        MXStrongifyAndReturnIfNil(self);
        
        NSMutableArray<MXMegolmSessionData*> *sessionDatas = [NSMutableArray array];
        
        // Restore that data
        NSUInteger sessionsFromHSCount = 0;
        for (NSString *roomId in keysBackupData.rooms)
        {
            for (NSString *sessionId in keysBackupData.rooms[roomId].sessions)
            {
                sessionsFromHSCount++;
                MXKeyBackupData *keyBackupData = keysBackupData.rooms[roomId].sessions[sessionId];
                
                MXMegolmSessionData *sessionData = [self decryptKeyBackupData:keyBackupData forSession:sessionId inRoom:roomId withPkDecryption:decryption];
                
                if (sessionData)
                {
                    [sessionDatas addObject:sessionData];
                }
            }
        }
        
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackup: Decrypted %@ keys out of %@ from the backup store on the homeserver", @(sessionDatas.count), @(sessionsFromHSCount));
        
        // Do not trigger a backup for them if they come from the backup version we are using
        BOOL backUp = ![keyBackupVersion.version isEqualToString:self.keyBackupVersion.version];
        if (backUp)
        {
            MXLogDebug(@"[MXKeyBackup] restoreKeyBackup: Those keys will be backed up to backup version: %@", self.keyBackupVersion.version);
        }
        
        // Import them into the crypto store
        [self->crypto importMegolmSessionDatas:sessionDatas backUp:backUp success:success failure:^(NSError *error) {
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
}

- (MXHTTPOperation*)restoreKeyBackup:(MXKeyBackupVersion*)keyBackupVersion
                        withPassword:(NSString*)password
                                room:(nullable NSString*)roomId
                             session:(nullable NSString*)sessionId
                             success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                             failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXLogDebug(@"[MXKeyBackup] restoreKeyBackup with password: From backup version: %@", keyBackupVersion.version);

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Retrieve the private key from the password
        NSError *error;
        NSString *recoveryKey = [self recoveryKeyFromPassword:password inKeyBackupVersion:keyBackupVersion error:&error];

        if (!error)
        {
            MXHTTPOperation *operation2 = [self restoreKeyBackup:keyBackupVersion withRecoveryKey:recoveryKey room:roomId session:sessionId success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }
    });

    return operation;
}

- (MXHTTPOperation*)restoreUsingPrivateKeyKeyBackup:(MXKeyBackupVersion*)keyBackupVersion
                                               room:(nullable NSString*)roomId
                                            session:(nullable NSString*)sessionId
                                            success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                                            failure:(nullable void (^)(NSError *error))failure
{
    MXHTTPOperation *operation = [MXHTTPOperation new];
    
    MXLogDebug(@"[MXKeyBackup] restoreUsingPrivateKeyKeyBackup: From backup version: %@", keyBackupVersion.version);
    
    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        // Get the PK decryption instance
        OLMPkDecryption *decryption = [self pkDecryptionFromCryptoStore];
        
        // Validate the local private key
        if (decryption)
        {
            NSString *pKDecryptionPublicKey = [self pkDecrytionPublicKeyFromCryptoStore];
            if (![self checkPkDecryptionPublicKey:pKDecryptionPublicKey forKeyBackupVersion:keyBackupVersion])
            {
                MXLogDebug(@"[MXKeyBackup] restoreUsingPrivateKeyKeyBackup. Error: Invalid private key (%@) for %@", pKDecryptionPublicKey, keyBackupVersion);
                decryption = nil;
            }
        }
        
        if (decryption)
        {
            // Launch the restore
            MXHTTPOperation *operation2 = [self restoreKeyBackup:keyBackupVersion withPkDecryption:decryption room:roomId session:sessionId success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else if (failure)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                                     code:MXKeyBackupErrorInvalidOrMissingLocalPrivateKey
                                                 userInfo:@{
                                                            NSLocalizedDescriptionKey: @"Backup: No valid private key"
                                                            }];
                failure(error);
            });
        }
    });
    
    return operation;
}

- (BOOL)hasPrivateKeyInCryptoStore
{
    return [crypto.store secretWithSecretId:MXSecretId.keyBackup] != nil;
}


#pragma mark - Backup trust

- (void)trustForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion onComplete:(void (^)(MXKeyBackupVersionTrust * _Nonnull))onComplete
{
    dispatch_async(cryptoQueue, ^{

        MXKeyBackupVersionTrust *keyBackupVersionTrust = [self trustForKeyBackupVersionFromCryptoQueue:keyBackupVersion];

        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(keyBackupVersionTrust);
        });
    });
}

- (MXKeyBackupVersionTrust *)trustForKeyBackupVersionFromCryptoQueue:(MXKeyBackupVersion *)keyBackupVersion
{
    NSString *myUserId = crypto.matrixRestClient.credentials.userId;

    MXKeyBackupVersionTrust *keyBackupVersionTrust = [MXKeyBackupVersionTrust new];

    NSError *error;
    MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogDebug(@"[MXKeyBackup] trustForKeyBackupVersion: Key backup is absent or missing required data");
        return keyBackupVersionTrust;
    }

    NSDictionary *mySigs = authData.signatures[myUserId];
    if (mySigs.count == 0)
    {
        MXLogDebug(@"[MXKeyBackup] trustForKeyBackupVersion: Ignoring key backup because it lacks any signatures from this user");
        return keyBackupVersionTrust;
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

        if (deviceId)
        {
            BOOL valid = NO;

            MXDeviceInfo *device = [self->crypto.deviceList storedDevice:myUserId deviceId:deviceId];
            if (device)
            {
                NSError *error;
                valid = [self->crypto.olmDevice verifySignature:device.fingerprint JSON:authData.signalableJSONDictionary signature:mySigs[keyId] error:&error];

                if (!valid)
                {
                    MXLogDebug(@"[MXKeyBackup] trustForKeyBackupVersion: Bad signature from device %@: %@", device.deviceId, error);
                }
                else if (device.trustLevel.isVerified)
                {
                    keyBackupVersionTrust.usable = YES;
                }
                
                MXKeyBackupVersionTrustSignature *signature = [MXKeyBackupVersionTrustSignature new];
                signature.deviceId = deviceId;
                signature.device = device;
                signature.valid = valid;
                [signatures addObject:signature];
            }
            else // Try interpreting it as the MSK public key
            {
                NSError *error;
                BOOL valid = [crypto.crossSigning.crossSigningTools pkVerifyObject:authData.JSONDictionary userId:myUserId publicKey:deviceId error:&error];
                
                if (!valid)
                {
                    MXLogDebug(@"[MXKeyBackup] trustForKeyBackupVersion: Signature with unknown key %@", deviceId);
                }
                else
                {
                    MXKeyBackupVersionTrustSignature *signature = [MXKeyBackupVersionTrustSignature new];
                    signature.keys = deviceId;
                    signature.valid = valid;
                    [signatures addObject:signature];
                }
            }
        }
    }

    keyBackupVersionTrust.signatures = signatures;

    return keyBackupVersionTrust;
}

- (MXHTTPOperation *)trustKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                                     trust:(BOOL)trust
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError * _Nonnull))failure
{
    MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:trust: %@. trust: %@", keyBackupVersion.version, @(trust));

    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSString *myUserId = self->crypto.matrixRestClient.credentials.userId;

        // Get auth data to update it
        NSError *error;
        MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:&error];
        if (error)
        {
            MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:trust: Key backup is missing required data");

            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }

        // Get current signatures
        NSMutableDictionary<NSString*, NSString*> *myUserSignatures;
        if (authData.signatures[myUserId])
        {
            myUserSignatures = [NSMutableDictionary dictionaryWithDictionary:authData.signatures[myUserId]];
        }
        else
        {
            myUserSignatures = [NSMutableDictionary dictionary];
        }

        // Add or remove current device signature
        if (trust)
        {
            NSDictionary *deviceSignatures = [self->crypto signObject:authData.signalableJSONDictionary][myUserId];
            [myUserSignatures addEntriesFromDictionary:deviceSignatures];
        }
        else
        {
            NSString *myDeviceId = self->crypto.store.deviceId;
            NSString *deviceSignKeyId = [NSString stringWithFormat:@"ed25519:%@", myDeviceId];
            [myUserSignatures removeObjectForKey:deviceSignKeyId];
        }

        // Create an updated version of MXKeyBackupVersion
        NSMutableDictionary<NSString*, NSDictionary*> *newSignatures = [authData.signatures mutableCopy];
        newSignatures[myUserId] = myUserSignatures;
        authData.signatures = newSignatures;

        MXKeyBackupVersion *newKeyBackupVersion = [keyBackupVersion copy];
        newKeyBackupVersion.authData = authData.JSONDictionary;

        // And send it to the homeserver
        MXHTTPOperation *operation2 = [self->crypto.matrixRestClient updateKeyBackupVersion:newKeyBackupVersion success:^(void) {

            // Relaunch the state machine on this updated backup version
            [self checkAndStartWithKeyBackupVersion:newKeyBackupVersion];
            
            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success();
                });
            }
        } failure:^(NSError *error) {
            
            MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:trust: Error: %@", error);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }];
        [operation mutateTo:operation2];
    });

    return operation;
}

- (MXHTTPOperation *)trustKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                           withRecoveryKey:(NSString *)recoveryKey
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError * _Nonnull))failure
{
    MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:withRecoveryKey: %@", keyBackupVersion.version);

    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSError *error;
        [self isValidRecoveryKey:recoveryKey forKeyBackupVersion:keyBackupVersion error:&error];
        if (!error)
        {
            MXHTTPOperation *operation2 = [self trustKeyBackupVersion:keyBackupVersion trust:YES success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:withRecoveryKey: Invalid recovery key. Error: %@", error);

            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }
    });

    return operation;
}

- (MXHTTPOperation *)trustKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion
                              withPassword:(NSString *)password
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError * _Nonnull))failure
{
    MXLogDebug(@"[MXKeyBackup] trustKeyBackupVersion:withPassword: %@", keyBackupVersion.version);

    MXHTTPOperation *operation = [MXHTTPOperation new];

    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSError *error;
        NSString *recoveryKey = [self recoveryKeyFromPassword:password inKeyBackupVersion:keyBackupVersion error:&error];

        if (!error)
        {
            // Check trust using the recovery key
            MXHTTPOperation *operation2 = [self trustKeyBackupVersion:keyBackupVersion withRecoveryKey:recoveryKey success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
        }
    });

    return operation;
}


#pragma mark - Private keys sharing

- (void)requestPrivateKeysToDeviceIds:(nullable NSArray<NSString*>*)deviceIds
                              success:(void (^)(void))success
                onPrivateKeysReceived:(void (^)(void))onPrivateKeysReceived
                              failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXKeyBackup] requestPrivateKeysToDeviceIds: %@", deviceIds);

    MXWeakify(self);
    [crypto.secretShareManager requestSecret:MXSecretId.keyBackup toDeviceIds:deviceIds success:^(NSString * _Nonnull requestId) {
    } onSecretReceived:^BOOL(NSString * _Nonnull secret) {
        MXStrongifyAndReturnValueIfNil(self, NO);
        
        BOOL isSecretValid = !self.keyBackupVersion     // Accept the secret if the backup is not known yet
        || [self isSecretValid:secret forKeyBackupVersion:self.keyBackupVersion];
        
        MXLogDebug(@"[MXKeyBackup] requestPrivateKeysToDeviceIds: Got key. isSecretValid: %@", @(isSecretValid));
        if (isSecretValid)
        {
            [self->crypto.store storeSecret:secret withSecretId:MXSecretId.keyBackup];
            onPrivateKeysReceived();
        }
        return isSecretValid;
    } failure:failure];
}

- (BOOL)isSecretValid:(NSString*)secret forKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
{
    BOOL isSecretValid = NO;
    
    NSData *privateKey = [MXBase64Tools dataFromBase64:secret];
    NSString *pKDecryptionPublicKey = [self pkDecrytionPublicKeyFromPrivateKey:privateKey];
    if ([self checkPkDecryptionPublicKey:pKDecryptionPublicKey forKeyBackupVersion:keyBackupVersion])
    {
        isSecretValid = YES;
    }
    
    return isSecretValid;
}


#pragma mark - Backup state

- (BOOL)enabled
{
    return _state >= MXKeyBackupStateReadyToBackUp;
}

- (BOOL)hasKeysToBackup
{
    return [crypto.store inboundGroupSessionsToBackup:1].count > 0;
}


#pragma mark - Private methods -

- (void)setState:(MXKeyBackupState)state
{
    MXLogDebug(@"[MXKeyBackup] setState: %@ -> %@", @(_state), @(state));

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
        operation = [crypto.matrixRestClient keysBackup:version success:success failure:failure];
    }
    else if (!sessionId)
    {
        operation = [crypto.matrixRestClient keysBackupInRoom:roomId version:version success:^(MXRoomKeysBackupData *roomKeysBackupData) {

            MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
            keysBackupData.rooms = @{
                                     roomId: roomKeysBackupData
                                     };

            success(keysBackupData);

        } failure:failure];
    }
    else
    {
        operation =  [crypto.matrixRestClient keyBackupForSession:sessionId inRoom:roomId version:version success:^(MXKeyBackupData *keyBackupData) {

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
    // Extract the private key
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

- (NSString*)pkPublicKeyFromRecoveryKey:(NSString*)recoveryKey error:(NSError **)error
{
    NSString *pkPublicKey;

    // Extract the private key
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:error];

    // Built the PK decryption with it
    OLMPkDecryption *decryption;
    if (privateKey)
    {
        decryption = [OLMPkDecryption new];
        pkPublicKey = [decryption setPrivateKey:privateKey error:error];
    }

    return pkPublicKey;
}

- (void)storePrivateKeyWithRecoveryKey:(NSString*)recoveryKey
{
    NSError *error;
    OLMPkDecryption *decryption = [self pkDecryptionFromRecoveryKey:recoveryKey error:&error];
    if (!decryption)
    {
        MXLogDebug(@"[MXKeyBackup] storePrivateKeyWithRecoveryKey] Cannot create OLMPkDecryption. Error: %@", error);
        return;
    }
    
    NSString *privateKeyBase64 = [MXBase64Tools unpaddedBase64FromData:decryption.privateKey];
    [crypto.store storeSecret:privateKeyBase64 withSecretId:MXSecretId.keyBackup];
}

- (nullable NSData*)privateKeyFromCryptoStore
{
    NSString *privateKeyBase64 = [self->crypto.store secretWithSecretId:MXSecretId.keyBackup];
    if (!privateKeyBase64)
    {
        MXLogDebug(@"[MXCrossSigning] privateKeyFromCryptoStore. Error: No secret in crypto store");
        return nil;
    }
    
    return [MXBase64Tools dataFromBase64:privateKeyBase64];
}

- (nullable OLMPkDecryption*)pkDecryptionFromCryptoStore
{
    NSData *privateKey = self.privateKeyFromCryptoStore;

    // Built the PK decryption with it
    OLMPkDecryption *decryption;
    if (privateKey)
    {
        NSError *error;
        decryption = [OLMPkDecryption new];
        [decryption setPrivateKey:privateKey error:&error];
        
        if (error)
        {
            MXLogDebug(@"[MXCrossSigning] pkDecryptionFromCryptoStore failed. Error: %@", error);
        }
    }

    return decryption;
}

- (nullable NSString*)pkDecrytionPublicKeyFromCryptoStore
{
    NSData *privateKey = self.privateKeyFromCryptoStore;
    return [self pkDecrytionPublicKeyFromPrivateKey:privateKey];
}

- (nullable NSString*)pkDecrytionPublicKeyFromPrivateKey:(NSData*)privateKey
{
    NSString *pkPublicKey;
    
    // Built the PK decryption with it
    OLMPkDecryption *decryption;
    if (privateKey)
    {
        NSError *error;
        decryption = [OLMPkDecryption new];
        pkPublicKey = [decryption setPrivateKey:privateKey error:&error];
        
        if (error)
        {
            MXLogDebug(@"[MXCrossSigning] pkDecrytionPublicKeyFromPrivateKey failed. Error: %@", error);
        }
    }
    
    return pkPublicKey;
}

- (BOOL)checkPkDecryptionPublicKey:(NSString*)pKDecryptionPublicKey forKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
{
    BOOL checkPkDecryptionPublicKey = NO;
    
    NSError *error;
    MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:&error];
    if ([pKDecryptionPublicKey isEqualToString:authData.publicKey])
    {
        checkPkDecryptionPublicKey = YES;
    }
    
    if (error)
    {
        MXLogDebug(@"[MXCrossSigning] checkPkDecryptionPublicKey: Error: %@", error);
    }
    
    return checkPkDecryptionPublicKey;
}

- (nullable OLMPkSigning*)pkSigningFromPrivateKey:(NSData*)privateKey withExpectedPublicKey:(NSString*)expectedPublicKey
{
    NSError *error;
    OLMPkSigning *pkSigning = [[OLMPkSigning alloc] init];
    NSString *gotPublicKey = [pkSigning doInitWithSeed:privateKey error:&error];
    if (error)
    {
        MXLogDebug(@"[MXCrossSigning] pkSigningFromPrivateKey failed to build PK signing. Error: %@", error);
        return nil;
    }
    
    if (![gotPublicKey isEqualToString:expectedPublicKey])
    {
        MXLogDebug(@"[MXCrossSigning] pkSigningFromPrivateKey failed. Keys do not match: %@ vs %@", gotPublicKey, expectedPublicKey);
        return nil;
    }
    
    return pkSigning;
}

- (MXKeyBackupData*)encryptGroupSession:(MXOlmInboundGroupSession*)session
{
    // Build the m.megolm_backup.v1.curve25519-aes-sha2 data as defined at
    // https://github.com/uhoreg/matrix-doc/blob/e2e_backup/proposals/1219-storing-megolm-keys-serverside.md#mmegolm_backupv1curve25519-aes-sha2-key-format
    MXMegolmSessionData *sessionData = session.exportSessionData;
    if (![self checkMXMegolmSessionData:sessionData])
    {
        MXLogDebug(@"[MXKeyBackup] encryptGroupSession: Error: Invalid MXMegolmSessionData for %@", session.senderKey);
        return nil;
    }
    
    NSDictionary *sessionBackupData = @{
                                        @"algorithm": sessionData.algorithm,
                                        @"sender_key": sessionData.senderKey,
                                        @"sender_claimed_keys": sessionData.senderClaimedKeys,
                                        @"forwarding_curve25519_key_chain": sessionData.forwardingCurve25519KeyChain ?  sessionData.forwardingCurve25519KeyChain : @[],
                                        @"session_key": sessionData.sessionKey
                                        };
    OLMPkMessage *encryptedSessionBackupData = [_backupKey encryptMessage:[MXTools serialiseJSONObject:sessionBackupData] error:nil];
    if (![self checkOLMPkMessage:encryptedSessionBackupData])
    {
        MXLogDebug(@"[MXKeyBackup] encryptGroupSession: Error: Invalid OLMPkMessage for %@", session.senderKey);
        return nil;
    }

    // Gather information for each key
    MXDeviceInfo *device = [crypto.deviceList deviceWithIdentityKey:session.senderKey andAlgorithm:kMXCryptoMegolmAlgorithm];

    // Build backup data for that key
    MXKeyBackupData *keyBackupData = [MXKeyBackupData new];
    keyBackupData.firstMessageIndex = session.session.firstKnownIndex;
    keyBackupData.forwardedCount = session.forwardingCurve25519KeyChain.count;
    keyBackupData.verified = device ? device.trustLevel.isVerified : NO;
    keyBackupData.sessionData = @{
                                  @"ciphertext": encryptedSessionBackupData.ciphertext,
                                  @"mac": encryptedSessionBackupData.mac,
                                  @"ephemeral": encryptedSessionBackupData.ephemeralKey,
                                  };

    return keyBackupData;
}

// Sanity checks on MXMegolmSessionData
- (BOOL)checkMXMegolmSessionData:(MXMegolmSessionData*)sessionData
{
    if (!sessionData.algorithm)
    {
        MXLogDebug(@"[MXKeyBackup] checkMXMegolmSessionData: missing algorithm");
        return NO;
    }
    if (!sessionData.senderKey)
    {
        MXLogDebug(@"[MXKeyBackup] checkMXMegolmSessionData: missing senderKey");
        return NO;
    }
    if (!sessionData.senderClaimedKeys)
    {
        MXLogDebug(@"[MXKeyBackup] checkMXMegolmSessionData: missing senderClaimedKeys");
        return NO;
    }
    if (!sessionData.sessionKey)
    {
        MXLogDebug(@"[MXKeyBackup] checkMXMegolmSessionData: missing sessionKey");
        return NO;
    }
    
    return YES;
}

// Sanity checks on OLMPkMessage
- (BOOL)checkOLMPkMessage:(OLMPkMessage*)message
{
    if (!message.ciphertext)
    {
        MXLogDebug(@"[MXKeyBackup] checkOLMPkMessage: missing ciphertext");
        return NO;
    }
    if (!message.mac)
    {
        MXLogDebug(@"[MXKeyBackup] checkOLMPkMessage: missing mac");
        return NO;
    }
    if (!message.ephemeralKey)
    {
        MXLogDebug(@"[MXKeyBackup] checkOLMPkMessage: missing ephemeralKey");
        return NO;
    }

    return YES;
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
            MXLogDebug(@"[MXKeyBackup] decryptKeyBackupData: Failed to decrypt session from backup. Error: %@", error);
        }
    }

    return sessionData;
}

/**
 Extract megolm back up authentication data from a backup.

 @param keyBackupVersion the key backup
 @param error the encountered error in case of failure.
 @return the authentication if found and valid.
 */
- (nullable MXMegolmBackupAuthData *)megolmBackupAuthDataFromKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion error:(NSError**)error
{
    MXMegolmBackupAuthData *authData = [MXMegolmBackupAuthData modelFromJSON:keyBackupVersion.authData];
    if (keyBackupVersion.algorithm && authData.publicKey && authData.signatures)
    {
        return authData;
    }
    else
    {
        MXLogDebug(@"[MXKeyBackup] megolmBackupAuthDataFromKeyBackupVersion: Key backup is missing required data");

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorMissingAuthDataCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Key backup is missing required data"
                                            }];

        return nil;
    }
}

/**
 Compute the recovery key from a password and key backup auth data.

 @param password the password.
 @param keyBackupVersion the backup and its auth data.
 @param error the encountered error in case of failure.
 @return the recovery key if successful.
 */
- (nullable NSString*)recoveryKeyFromPassword:(NSString*)password inKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion error:(NSError **)error
{
    // Extract MXMegolmBackupAuthData
    MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:error];
    if (*error)
    {
        return nil;
    }

    if (!authData.privateKeySalt || !authData.privateKeyIterations)
    {
        MXLogDebug(@"[MXKeyBackup] recoveryFromPassword: Salt and/or iterations not found in key backup auth data");
        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorMissingPrivateKeySaltCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Salt and/or iterations not found in key backup auth data"
                                            }];
        return nil;
    }


    // Extract the recovery key from the passphrase
    NSData *recoveryKeyData = [MXKeyBackupPassword retrievePrivateKeyWithPassword:password salt:authData.privateKeySalt iterations:authData.privateKeyIterations error:error];
    if (*error)
    {
        MXLogDebug(@"[MXKeyBackup] recoveryFromPassword: retrievePrivateKeyWithPassword failed: %@", *error);
        return nil;
    }

    return [MXRecoveryKey encode:recoveryKeyData];
}

/**
 Check if a recovery key matches key backup authentication data.

 @param recoveryKey the recovery key to challenge.
 @param keyBackupVersion the backup and its auth data.
 @param error the encountered error in case of failure.
 @return YES if successful.
 */
- (BOOL)isValidRecoveryKey:(NSString*)recoveryKey forKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion error:(NSError **)error
{
    // Build PK decryption instance with the recovery key
    NSString *publicKey = [self pkPublicKeyFromRecoveryKey:recoveryKey error:error];
    if (*error)
    {
        MXLogDebug(@"[MXKeyBackup] isValidRecoveryKey: Invalid recovery key. Error: %@", *error);

        // Return a generic error
        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorInvalidRecoveryKeyCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Invalid recovery key or password"
                                            }];
        return NO;
    }

    // Get the public key defined in the backup
    MXMegolmBackupAuthData *authData = [self megolmBackupAuthDataFromKeyBackupVersion:keyBackupVersion error:error];
    if (*error)
    {
        MXLogDebug(@"[MXKeyBackup] isValidRecoveryKey: Key backup is missing required data");
        return NO;
    }

    // Compare both
    if (![publicKey isEqualToString:authData.publicKey])
    {
        MXLogDebug(@"[MXKeyBackup] isValidRecoveryKey: Public keys mismatch");

        *error = [NSError errorWithDomain:MXKeyBackupErrorDomain
                                     code:MXKeyBackupErrorInvalidRecoveryKeyCode
                                 userInfo:@{
                                            NSLocalizedDescriptionKey: @"Invalid recovery key or password"
                                            }];
        return NO;
    }

    return YES;
}

@end
