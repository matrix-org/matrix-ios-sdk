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

#import "MXRecoveryKey.h"
#import "MXSession.h"
#import "MXTools.h"
#import "MXBase64Tools.h"
#import "MXError.h"
#import "MXKeyProvider.h"
#import "MXRawDataKey.h"
#import "MXSharedHistoryKeyService.h"
#import "MXKeyBackupEngine.h"
#import "MatrixSDKSwiftHeader.h"

#pragma mark - Constants definitions

NSString *const kMXKeyBackupDidStateChangeNotification = @"kMXKeyBackupDidStateChangeNotification";

/**
 Maximum delay in ms in `[MXKeyBackup maybeSendKeyBackup]`.
 */
NSUInteger const kMXKeyBackupWaitingTimeToSendKeyBackup = 10000;

@interface MXKeyBackup ()
{
    // The queue to run background tasks
    dispatch_queue_t cryptoQueue;

    // Observer to kMXKeyBackupDidStateChangeNotification when backupAllGroupSessions is progressing
    id backupAllGroupSessionsObserver;

    // Failure block when backupAllGroupSessions is progressing
    void (^backupAllGroupSessionsFailure)(NSError *error);
}

@property (nonatomic, strong) id<MXKeyBackupEngine> engine;
@property (nonatomic, strong) MXRestClient *restClient;

@end

@implementation MXKeyBackup

#pragma mark - SDK-Private methods -

- (instancetype)initWithEngine:(id<MXKeyBackupEngine>)engine
                    restClient:(MXRestClient *)restClient
                         queue:(dispatch_queue_t)queue
{
    self = [self init];
    if (self)
    {
        _state = MXKeyBackupStateUnknown;
        _engine = engine;
        _restClient = restClient;
        cryptoQueue = queue;
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

        MXLogErrorDetails(@"[MXKeyBackup] checkAndStartKeyBackup: Failed to get current version", error);
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

    MXKeyBackupVersionTrust *trustInfo = [self.engine trustForKeyBackupVersion:keyBackupVersion];

    if (trustInfo.usable)
    {
        MXLogDebug(@"[MXKeyBackup] checkAndStartWithKeyBackupVersion: Found usable key backup. version: %@", keyBackupVersion.version);

        // Check the version we used at the previous app run
        NSString *versionInStore = self.engine.version;
        if (versionInStore && ![versionInStore isEqualToString:keyBackupVersion.version])
        {
            MXLogDebug(@"[MXKeyBackup] -> clean the previously used version(%@)", versionInStore);
            [self resetKeyBackupData];
        }
        
        MXLogDebug(@"[MXKeyBackup]    -> enabling key backups");
        [self enableKeyBackup:keyBackupVersion];
    }
    else
    {
        MXLogDebug(@"[MXKeyBackup] checkAndStartWithKeyBackupVersion: No usable key backup. version: %@", keyBackupVersion.version);

        if (self.engine.version)
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
    if (![self.engine enableBackupWithKeyBackupVersion:version error:&error])
    {
        return error;
    }
    _keyBackupVersion = version;
    self.state = MXKeyBackupStateReadyToBackUp;
        
    [self maybeSendKeyBackup];

    return nil;
}

- (void)resetKeyBackupData
{
    MXLogDebug(@"[MXKeyBackup] resetKeyBackupData");
    
    [self resetBackupAllGroupSessionsObjects];
    [self.engine disableBackup];
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
        MXLogDebug(@"[MXKeyBackup] maybeSendKeyBackup: Skip it because state: %@", [self descriptionForState:_state]);

        // If not already done, check for a valid backup version on the homeserver.
        // If one, maybeSendKeyBackup will be called again.
        [self checkAndStartKeyBackup];
    }
}

- (void)sendKeyBackup
{
    MXLogDebug(@"[MXKeyBackup] sendKeyBackup");
    
    if (!self.engine.hasKeysToBackup)
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
    if (!self.enabled || !_keyBackupVersion)
    {
        MXLogDebug(@"[MXKeyBackup] sendKeyBackup: Invalid state: %@", [self descriptionForState:_state]);
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

    MXLogDebug(@"[MXKeyBackup] sendKeyBackup: Backing up keys");

    MXWeakify(self);
    [self.engine backupKeysWithSuccess:^{
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXKeyBackup] sendKeyBackup: Request complete");

        if (!self.engine.hasKeysToBackup)
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

        MXLogErrorDetails(@"[MXKeyBackup] sendKeyBackup: backupRoomKeysSuccess failed", error);

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
            MXLogErrorDetails(@"[MXKeyBackup] restoreKeyBackupAutomatically: Cannot fetch backup version", error);
        }];
        return;
    }
    
    // Check private keys
    if (![self.engine hasValidPrivateKeyForKeyBackupVersion:self.keyBackupVersion])
    {
        MXLogError(@"[MXKeyBackup] restoreKeyBackupAutomatically. Error: No valid private key");
        onComplete();
        return;
    }
    
    // Do the restore operation in background
    [self restoreUsingPrivateKeyKeyBackup:self.keyBackupVersion room:nil session:nil success:^(NSUInteger total, NSUInteger imported) {
        
        MXLogDebug(@"[MXKeyBackup] restoreKeyBackupAutomatically: Restored %@ keys out of %@", @(imported), @(total));
        onComplete();
        
    } failure:^(NSError * _Nonnull error) {
        MXLogErrorDetails(@"[MXKeyBackup] restoreKeyBackupAutomatically. Error for restoreKeyBackup", error);
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
    return [self.restClient keyBackupVersion:version success:success failure:^(NSError *error) {

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
                                  algorithm:(NSString *)algorithm
                                    success:(void (^)(MXMegolmBackupCreationInfo * _Nonnull))success
                                    failure:(void (^)(NSError * _Nonnull))failure
{
    MXWeakify(self);
    dispatch_async(cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        [self.engine prepareKeyBackupVersionWithPassword:password algorithm:algorithm success:success failure:failure];
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

        MXHTTPOperation *operation2 = [self.restClient createKeyBackupVersion:keyBackupVersion success:^(NSString *version) {
            keyBackupVersion.version = version;
            
            // Disable current backup
            [self.engine disableBackup];

            // Store the fresh new private key
            NSData *privateKey = [self privateKeyForRecoveryKey:keyBackupCreationInfo.recoveryKey];
            if (privateKey)
            {
                [self.engine savePrivateKey:privateKey version:keyBackupVersion.version];
            }

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
        MXHTTPOperation *operation2 = [self.restClient deleteKeyBackupVersion:version success:^{
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
        MXLogDebug(@"[MXKeyBackup] forceRefresh: Invalid state (%@) to force the refresh", [self descriptionForState:_state]);
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
        
        NSProgress *progress = self.engine.backupProgress;
        dispatch_async(dispatch_get_main_queue(), ^{
            backupProgress(progress);
        });
     });
}


#pragma mark - Backup restoring

- (NSData *)privateKeyForRecoveryKey:(NSString *)recoveryKey
{
    NSError *error;
    NSData *privateKey = [MXRecoveryKey decode:recoveryKey error:&error];
    if (error || !privateKey)
    {
        MXLogErrorDetails(@"[MXKeyBackup] privateKeyForRecoveryKey: Cannot create private key from recovery key: %@", error);
        return nil;
    }
    return privateKey;
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
        NSData *privateKey = [self.engine validPrivateKeyForRecoveryKey:recoveryKey forKeyBackupVersion:keyBackupVersion error:&error];
        if (error || !privateKey)
        {
            MXLogErrorDetails(@"[MXKeyBackup] restoreKeyBackup: Invalid recovery key", error);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(error);
                });
            }
            return;
        }

        MXHTTPOperation *operation2 = [self restoreKeyBackup:keyBackupVersion withPrivateKey:privateKey room:roomId session:sessionId success:^(NSUInteger total, NSUInteger imported) {

            // Catch the private key from the recovery key and store it locally
            NSData *privateKey = [self privateKeyForRecoveryKey:recoveryKey];
            if ([self.keyBackupVersion.version isEqualToString:keyBackupVersion.version] && privateKey)
            {
                [self.engine savePrivateKey:privateKey version:keyBackupVersion.version];
            }

            if (success)
            {
                success(total, imported);
            }
        } failure:failure];

        [operation mutateTo:operation2];
    });

    return operation;
}

- (MXHTTPOperation*)restoreKeyBackup:(MXKeyBackupVersion*)keyBackupVersion
                      withPrivateKey:(NSData*)privateKey
                                room:(nullable NSString*)roomId
                             session:(nullable NSString*)sessionId
                             success:(nullable void (^)(NSUInteger total, NSUInteger imported))success
                             failure:(nullable void (^)(NSError *error))failure
{
    // Get backup from the homeserver
    MXWeakify(self);
    return [self keyBackupForSession:sessionId inRoom:roomId version:keyBackupVersion.version success:^(MXKeysBackupData *keysBackupData) {
        MXStrongifyAndReturnIfNil(self);
        [self.engine importKeysWithKeysBackupData:keysBackupData
                                       privateKey:privateKey
                                 keyBackupVersion:keyBackupVersion
                                          success:success
                                          failure:failure];
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
        NSString *recoveryKey = [self.engine recoveryKeyFromPassword:password inKeyBackupVersion:keyBackupVersion error:&error];

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

        if (![self.engine hasValidPrivateKeyForKeyBackupVersion:keyBackupVersion])
        {
            MXLogError(@"[MXKeyBackup] restoreUsingPrivateKeyKeyBackup. Error: Private key does not match");
            if (failure)
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
            return;
        }

        // Launch the restore
        MXHTTPOperation *operation2 = [self restoreKeyBackup:keyBackupVersion withPrivateKey:self.engine.privateKey room:roomId session:sessionId success:success failure:failure];
        [operation mutateTo:operation2];
    });
    
    return operation;
}

- (BOOL)hasPrivateKeyInCryptoStore
{
    return self.engine.privateKey != nil;
}

- (NSProgress *)importProgress
{
    return self.engine.importProgress;
}

#pragma mark - Backup trust

- (void)trustForKeyBackupVersion:(MXKeyBackupVersion *)keyBackupVersion onComplete:(void (^)(MXKeyBackupVersionTrust * _Nonnull))onComplete
{
    dispatch_async(cryptoQueue, ^{

        MXKeyBackupVersionTrust *keyBackupVersionTrust = [self.engine trustForKeyBackupVersion:keyBackupVersion];

        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(keyBackupVersionTrust);
        });
    });
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

        NSString *myUserId = self.restClient.credentials.userId;

        // Get auth data to update it
        NSError *error;
        id<MXBaseKeyBackupAuthData> authData = [self.engine authDataFromKeyBackupVersion:keyBackupVersion error:&error];
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
            NSDictionary *deviceSignatures = [self.engine signObject:authData.signalableJSONDictionary][myUserId];
            [myUserSignatures addEntriesFromDictionary:deviceSignatures];
        }
        else
        {
            NSString *myDeviceId = self.restClient.credentials.deviceId;
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
        MXHTTPOperation *operation2 = [self.restClient updateKeyBackupVersion:newKeyBackupVersion success:^(void) {

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
        NSData *privateKey = [self.engine validPrivateKeyForRecoveryKey:recoveryKey forKeyBackupVersion:keyBackupVersion error:&error];
        if (!error && privateKey)
        {
            MXHTTPOperation *operation2 = [self trustKeyBackupVersion:keyBackupVersion trust:YES success:success failure:failure];
            [operation mutateTo:operation2];
        }
        else
        {
            MXLogErrorDetails(@"[MXKeyBackup] trustKeyBackupVersion:withRecoveryKey: Invalid recovery key", error);

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
        NSString *recoveryKey = [self.engine recoveryKeyFromPassword:password inKeyBackupVersion:keyBackupVersion error:&error];

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

- (BOOL)isSecretValid:(NSString*)secret forKeyBackupVersion:(MXKeyBackupVersion*)keyBackupVersion
{
    NSData *privateKey = [MXBase64Tools dataFromBase64:secret];
    NSString *recoveryKey = [MXRecoveryKey encode:privateKey];
    
    NSError *error;
    NSData *validPrivateKey = [self.engine validPrivateKeyForRecoveryKey:recoveryKey forKeyBackupVersion:keyBackupVersion error:&error];
    if (error)
    {
        MXLogErrorDetails(@"[MXKeyBackup] isSecretValid: Error %@", error);
        return NO;
    }
    return [privateKey isEqualToData:validPrivateKey];
}

#pragma mark - Backup state

- (BOOL)enabled
{
    return _state >= MXKeyBackupStateReadyToBackUp && self.engine.enabled;
}

- (BOOL)hasKeysToBackup
{
    return [self.engine hasKeysToBackup];
}

- (BOOL)canBeRefreshed
{
    return _state != MXKeyBackupStateUnknown && _state != MXKeyBackupStateCheckingBackUpOnHomeserver;
}

#pragma mark - Private methods -

- (void)setState:(MXKeyBackupState)state
{
    MXLogDebug(@"[MXKeyBackup] setState: %@ -> %@", [self descriptionForState:_state], [self descriptionForState:state]);

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
        operation = [self.restClient keysBackup:version success:success failure:failure];
    }
    else if (!sessionId)
    {
        operation = [self.restClient keysBackupInRoom:roomId version:version success:^(MXRoomKeysBackupData *roomKeysBackupData) {

            MXKeysBackupData *keysBackupData = [MXKeysBackupData new];
            keysBackupData.rooms = @{
                                     roomId: roomKeysBackupData
                                     };

            success(keysBackupData);

        } failure:failure];
    }
    else
    {
        operation =  [self.restClient keyBackupForSession:sessionId inRoom:roomId version:version success:^(MXKeyBackupData *keyBackupData) {

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

- (NSString *)descriptionForState:(MXKeyBackupState)state
{
    switch (state) {
        case MXKeyBackupStateUnknown:
            return @"Unknown";
        case MXKeyBackupStateCheckingBackUpOnHomeserver:
            return @"CheckingBackUpOnHomeserver";
        case MXKeyBackupStateWrongBackUpVersion:
            return @"WrongBackUpVersion";
        case MXKeyBackupStateDisabled:
            return @"Disabled";
        case MXKeyBackupStateNotTrusted:
            return @"NotTrusted";
        case MXKeyBackupStateEnabling:
            return @"Enabling";
        case MXKeyBackupStateReadyToBackUp:
            return @"ReadyToBackUp";
        case MXKeyBackupStateWillBackUp:
            return @"WillBackUp";
        case MXKeyBackupStateBackingUp:
            return @"BackingUp";
    };
}

@end
