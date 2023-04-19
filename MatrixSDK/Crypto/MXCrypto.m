/*
 Copyright 2016 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2018 New Vector Ltd
 Copyright 2020 The Matrix.org Foundation C.I.C

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

#import "MXCrypto.h"

#import "MXCrypto_Private.h"

#import "MXSession.h"
#import "MXTools.h"

#import "MXOlmDevice.h"
#import "MXUsersDevicesMap.h"
#import "MXDeviceInfo.h"
#import "MXKey.h"

#import "MXRealmCryptoStore.h"
#import "MXCryptoMigration.h"

#import "MXMegolmSessionData.h"
#import "MXMegolmExportEncryption.h"

#import "MXOutgoingRoomKeyRequestManager.h"
#import "MXIncomingRoomKeyRequestManager.h"

#import "MXSecretStorage_Private.h"
#import "MXSecretShareManager_Private.h"
#import "MXRecoveryService_Private.h"

#import "MXKeyVerificationManager_Private.h"
#import "MXDeviceInfo_Private.h"
#import "MXCrossSigningInfo_Private.h"
#import "MXCrossSigning_Private.h"

#import "NSArray+MatrixSDK.h"

#import "MXDeviceListResponse.h"

#import "MatrixSDKSwiftHeader.h"
#import "MXSharedHistoryKeyService.h"
#import "MXNativeKeyBackupEngine.h"

#warning File has not been annotated with nullability, see MX_ASSUME_MISSING_NULLABILITY_BEGIN

/**
 The store to use for crypto.
 */
#define MXCryptoStoreClass MXRealmCryptoStore

NSString *const kMXCryptoRoomKeyRequestNotification = @"kMXCryptoRoomKeyRequestNotification";
NSString *const kMXCryptoRoomKeyRequestNotificationRequestKey = @"kMXCryptoRoomKeyRequestNotificationRequestKey";
NSString *const kMXCryptoRoomKeyRequestCancellationNotification = @"kMXCryptoRoomKeyRequestCancellationNotification";
NSString *const kMXCryptoRoomKeyRequestCancellationNotificationRequestKey = @"kMXCryptoRoomKeyRequestCancellationNotificationRequestKey";

NSString *const MXDeviceListDidUpdateUsersDevicesNotification = @"MXDeviceListDidUpdateUsersDevicesNotification";

static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotification             = @"kMXCryptoOneTimeKeyClaimCompleteNotification";
static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey   = @"kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey";
static NSString *const kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey     = @"kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey";


#ifdef MX_CRYPTO

// Frequency with which to check & upload one-time keys
NSTimeInterval kMXCryptoUploadOneTimeKeysPeriod = 60.0; // one minute
NSTimeInterval kMXCryptoMinForceSessionPeriod = 3600.0; // one hour

@interface MXLegacyCrypto () <MXRecoveryServiceDelegate, MXUnrequestedForwardedRoomKeyManagerDelegate>
{
    // MXEncrypting instance for each room.
    NSMutableDictionary<NSString*, id<MXEncrypting>> *roomEncryptors;

    // A map from algorithm to MXDecrypting instance, for each room
    NSMutableDictionary<NSString* /* roomId */,
        NSMutableDictionary<NSString* /* algorithm */, id<MXDecrypting>>*> *roomDecryptors;

    // Listener on memberships changes
    id roomMembershipEventsListener;

    // The one-time keys count sent by /sync
    // -1 means the information was not sent by the server
    NSUInteger oneTimeKeyCount;

    // Last time we check available one-time keys on the homeserver
    NSDate *lastOneTimeKeyCheck;

    // The current one-time key operation, if any
    MXHTTPOperation *uploadOneTimeKeysOperation;

    // The operation used for crypto starting requests
    MXHTTPOperation *startOperation;

    // The manager for sending room key requests
    MXOutgoingRoomKeyRequestManager *outgoingRoomKeyRequestManager;

    // The manager for incoming room key requests
    MXIncomingRoomKeyRequestManager *incomingRoomKeyRequestManager;
    
    // The manager for unrequested m.forwarded_room_keys
    MXUnrequestedForwardedRoomKeyManager *unrequestedForwardedRoomKeyManager;
    
    // The date of the last time we forced establishment
    // of a new session for each user:device.
    MXUsersDevicesMap<NSDate*> *lastNewSessionForcedDates;
    
    // The dedicated queue used for decryption.
    // This queue is used to get the key from the crypto store and decrypt the event. No more.
    // Thus, it can respond quicker than cryptoQueue for this operation that must return
    // synchronously for MXSession.
    dispatch_queue_t decryptionQueue;
    
    // The queue to manage bulk import and export of keys.
    // It only reads and writes keys from and to the crypto store.
    dispatch_queue_t cargoQueue;
    
    // The list of devices (by their identity key) we are establishing
    // an olm session with.
    NSMutableArray<NSString*> *ensureOlmSessionsInProgress;
    
    // Migration tool
    MXCryptoMigration *cryptoMigration;
}

// The current fallback key operation, if any
@property(nonatomic, strong) MXHTTPOperation *uploadFallbackKeyOperation;

@end

#endif

@implementation MXLegacyCrypto

@synthesize backup = _backup;
@synthesize crossSigning = _crossSigning;
@synthesize keyVerificationManager = _keyVerificationManager;
@synthesize recoveryService = _recoveryService;

+ (id<MXCrypto>)createCryptoWithMatrixSession:(MXSession *)mxSession
                                        error:(NSError **)error
{
    __block id<MXCrypto> crypto;

#ifdef MX_CRYPTO
    dispatch_queue_t cryptoQueue = [MXLegacyCrypto dispatchQueueForUser:mxSession.matrixRestClient.credentials.userId];
    dispatch_sync(cryptoQueue, ^{

        MXCryptoStoreClass *cryptoStore = [MXCryptoStoreClass createStoreWithCredentials:mxSession.matrixRestClient.credentials];
        cryptoStore.cryptoVersion = MXCryptoVersionLast;
        crypto = [[MXLegacyCrypto alloc] initWithMatrixSession:mxSession cryptoQueue:cryptoQueue andStore:cryptoStore];

    });
#endif

    return crypto;
}

+ (void)initializeCryptoWithMatrixSession:(MXSession *)mxSession
                        migrationProgress:(void (^)(double))migrationProgress
                                 complete:(void (^)(id<MXCrypto> crypto, NSError *error))complete
{
#ifdef MX_CRYPTO
    [self initalizeLegacyCryptoWithMatrixSession:mxSession complete:complete];
#else
    complete(nil);
#endif
}

+ (void)initalizeLegacyCryptoWithMatrixSession:(MXSession*)mxSession complete:(void (^)(id<MXCrypto> crypto, NSError *error))complete
{
#ifdef MX_CRYPTO

    MXLogDebug(@"[MXCrypto] checkCryptoWithMatrixSession for %@", mxSession.matrixRestClient.credentials.userId);

    dispatch_queue_t cryptoQueue = [MXLegacyCrypto dispatchQueueForUser:mxSession.matrixRestClient.credentials.userId];
    dispatch_async(cryptoQueue, ^{

        //  clear the read-only store
        [MXCryptoStoreClass deleteReadonlyStoreWithCredentials:mxSession.credentials];
        
        if ([MXCryptoStoreClass hasDataForCredentials:mxSession.matrixRestClient.credentials])
        {
            MXLogDebug(@"[MXCrypto] checkCryptoWithMatrixSession: Crypto store exists");

            // If it already exists, init store and crypto
            MXCryptoStoreClass *cryptoStore = [[MXCryptoStoreClass alloc] initWithCredentials:mxSession.matrixRestClient.credentials];

            MXLogDebug(@"[MXCrypto] checkCryptoWithMatrixSession: Crypto store initialized");

            id<MXCrypto> crypto = [[MXLegacyCrypto alloc] initWithMatrixSession:mxSession cryptoQueue:cryptoQueue andStore:cryptoStore];

            dispatch_async(dispatch_get_main_queue(), ^{
                complete(crypto, nil);
            });
        }
        else if ([MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession
                 // Without the device id provided by the hs, the crypto does not work
                 && mxSession.matrixRestClient.credentials.deviceId)
        {
            MXLogDebug(@"[MXCrypto] checkCryptoWithMatrixSession: Need to create the store");

            // Create it
            MXCryptoStoreClass *cryptoStore = [MXCryptoStoreClass createStoreWithCredentials:mxSession.matrixRestClient.credentials];
            cryptoStore.cryptoVersion = MXCryptoVersionLast;
            id<MXCrypto> crypto = [[MXLegacyCrypto alloc] initWithMatrixSession:mxSession cryptoQueue:cryptoQueue andStore:cryptoStore];

            dispatch_async(dispatch_get_main_queue(), ^{
                complete(crypto, nil);
            });
        }
        else
        {
            // Else do not enable crypto
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(nil, nil);
            });
        }

    });

#else
    complete(nil, nil);
#endif
}

+ (void)rehydrateExportedOlmDevice:(MXExportedOlmDevice*)exportedOlmDevice
                   withCredentials:(MXCredentials *)credentials
                          complete:(void (^)(BOOL success))complete;
{
#ifdef MX_CRYPTO
    dispatch_queue_t cryptoQueue = [MXLegacyCrypto dispatchQueueForUser:credentials.userId];
    dispatch_async(cryptoQueue, ^{
        if ([MXCryptoStoreClass hasDataForCredentials:credentials])
        {
            MXLogErrorDetails(@"the exported Olm device shouldn't exist locally", @{
                @"device_id": credentials.deviceId ?: @"unknown"
            });
            complete(false);
            return;
        }
        
        // Create a new store for the given credentials
        MXCryptoStoreClass *cryptoStore = [MXCryptoStoreClass createStoreWithCredentials:credentials];
        cryptoStore.cryptoVersion = MXCryptoVersionLast;
        
        // store the exported olm account
        NSError *error = nil;
        OLMAccount *olmAccount = [[OLMAccount alloc] initWithSerializedData:exportedOlmDevice.pickledAccount key:exportedOlmDevice.pickleKey error:&error];
        [cryptoStore setAccount:olmAccount];
        
        complete(error == nil);
    });
#else
    complete(false);
#endif
}

- (void)deleteStore:(void (^)(void))onComplete;
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        [MXCryptoStoreClass deleteStoreWithCredentials:self.mxSession.matrixRestClient.credentials];

        if (onComplete)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                onComplete();
            });
        }
    });
#endif
}

- (void)start:(void (^)(void))success
      failure:(void (^)(NSError *error))failure
{

#ifdef MX_CRYPTO
    MXLogDebug(@"[MXCrypto] start");

    // The session must be initialised enough before starting this module
    if (!_mxSession.myUser.userId)
    {
        MXLogError(@"[MXCrypto] start. ERROR: mxSession.myUser.userId cannot be nil");
        failure(nil);
        return;
    }
    
    // Check migration
    if ([cryptoMigration shouldMigrate])
    {
        MXWeakify(self);
        [cryptoMigration migrateWithSuccess:^{
            MXStrongifyAndReturnIfNil(self);
            
            // Migration is done
            self->cryptoMigration = nil;
            [self start:success failure:failure];
            
        } failure:^(NSError * _Nonnull error) {
            MXStrongifyAndReturnIfNil(self);
            
            // We have no mandatory migration for now
            // We can try again at the next MXCrypto startup
            MXLogDebug(@"[MXCrypto] start. Migration failed. Ignore it for now");
            self->cryptoMigration = nil;
            [self start:success failure:failure];
        }];
        return;
    }
    else
    {
        cryptoMigration = nil;
    }

    // Start uploading user device keys
    MXWeakify(self);
    startOperation = [self uploadDeviceKeys:^(MXKeysUploadResponse *keysUploadResponse) {
        MXStrongifyAndReturnIfNil(self);

        if (!self->startOperation)
        {
            return;
        }

        // Upload our one-time keys
        // TODO: matrix-js-sdk does not do it anymore and waits for the completion
        // of /sync (see comments of the other usage of maybeUploadOneTimeKeys in
        // this file)
        // On iOS, for test purpose, we still need to know when the OTKs are sent
        // so that we can start sending message to a device.
        // Keep maybeUploadOneTimeKeys for the moment.
        MXWeakify(self);
        [self maybeUploadOneTimeKeys:^{
            MXStrongifyAndReturnIfNil(self);

            MXLogDebug(@"[MXCrypto] start ###########################################################");
            MXLogDebug(@"[MXCrypto] uploadDeviceKeys done for %@: ", self.mxSession.myUserId);

            MXLogDebug(@"[MXCrypto]    - device id  : %@", self.store.deviceId);
            MXLogDebug(@"[MXCrypto]    - ed25519    : %@", self.olmDevice.deviceEd25519Key);
            MXLogDebug(@"[MXCrypto]    - curve25519 : %@", self.olmDevice.deviceCurve25519Key);
            MXLogDebug(@"[MXCrypto] ");
            MXLogDebug(@"[MXCrypto] Store: %@", self.store);
            MXLogDebug(@"[MXCrypto] ");

            [self->_crossSigning refreshStateWithSuccess:nil failure:nil];
            
            [self->outgoingRoomKeyRequestManager start];

            [self->_backup checkAndStartKeyBackup];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self->startOperation = nil;
                success();
            });


        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);

            MXLogErrorDetails(@"[MXCrypto] start. Error in maybeUploadOneTimeKeys", @{
                @"error": error ?: @"unknown"
            });
            dispatch_async(dispatch_get_main_queue(), ^{
                self->startOperation = nil;
                failure(error);
            });
        }];

    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);

        MXLogErrorDetails(@"[MXCrypto] start. Error in uploadDeviceKeys", @{
            @"error": error ?: @"unknown"
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            self->startOperation = nil;
            failure(error);
        });
    }];

#endif
}

- (void)close:(BOOL)deleteStore
{
#ifdef MX_CRYPTO

    MXLogDebug(@"[MXCrypto] close. store: %@", _store);

    [_mxSession removeListener:roomMembershipEventsListener];

    [startOperation cancel];
    startOperation = nil;

    if (_myDevice == nil)
    {
        MXLogDebug(@"[MXCrypto] close: already closed");
        return;
    }

    MXWeakify(self);
    dispatch_sync(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Cancel pending one-time keys upload
        [self->uploadOneTimeKeysOperation cancel];
        self->uploadOneTimeKeysOperation = nil;
        
        [self.uploadFallbackKeyOperation cancel];
        self.uploadFallbackKeyOperation = nil;

        [self->outgoingRoomKeyRequestManager close];
        self->outgoingRoomKeyRequestManager = nil;
        
        [self->unrequestedForwardedRoomKeyManager close];
        self->outgoingRoomKeyRequestManager = nil;

        if (deleteStore)
        {
            [MXCryptoStoreClass deleteStoreWithCredentials:self.mxSession.matrixRestClient.credentials];
        }

        self->_olmDevice = nil;
        self->_cryptoQueue = nil;
        self->_store = nil;

        [self.deviceList close];
        self->_deviceList = nil;
        
        [self.matrixRestClient close];
        self->_matrixRestClient = nil;

        [self->roomEncryptors removeAllObjects];
        self->roomEncryptors = nil;

        [self->roomDecryptors removeAllObjects];
        self->roomDecryptors = nil;
        
        self->_backup = nil;
        self->_keyVerificationManager = nil;
        self->_recoveryService = nil;
        self->_secretStorage = nil;
        self->_secretShareManager = nil;
        self->_crossSigning = nil;
        
        self->_myDevice = nil;

        MXLogDebug(@"[MXCrypto] close: done");
    });

#endif
}

- (MXHTTPOperation *)encryptEventContent:(NSDictionary *)eventContent withType:(MXEventTypeString)eventType inRoom:(MXRoom *)room
                                 success:(void (^)(NSDictionary *, NSString *))success
                                 failure:(void (^)(NSError *))failure
{
#ifdef MX_CRYPTO

    MXLogDebug(@"[MXCrypto] encryptEventContent");

    NSDate *startDate = [NSDate date];

    // Create an empty operation that will be mutated later
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];

    // Pick the list of recipients based on the membership list.

    // TODO: there is a race condition here! What if a new user turns up
    // just as you are sending a secret message?

    MXWeakify(self);
    [room state:^(MXRoomState *roomState) {
        MXStrongifyAndReturnIfNil(self);

        MXWeakify(self);
        [room members:^(MXRoomMembers *roomMembers) {
            MXStrongifyAndReturnIfNil(self);

            NSMutableArray *userIds = [NSMutableArray array];
            NSArray<MXRoomMember *> *encryptionTargetMembers = [roomMembers encryptionTargetMembers:roomState.historyVisibility];
            for (MXRoomMember *roomMember in encryptionTargetMembers)
            {
                [userIds addObject:roomMember.userId];
            }

            MXWeakify(self);
            dispatch_async(self.cryptoQueue, ^{
                MXStrongifyAndReturnIfNil(self);

                NSString *algorithm;
                id<MXEncrypting> alg = self->roomEncryptors[room.roomId];

                MXLogDebug(@"[MXCrypto] encryptEventContent: with %@ for %@ users", roomState.encryptionAlgorithm, @(userIds.count));

                if (!alg)
                {
                    // If the crypto has been enabled after the initialSync (the global one or the one for this room),
                    // the algorithm has not been initialised yet. So, do it now from room state information
                    algorithm = roomState.encryptionAlgorithm;
                    if (!algorithm)
                    {
                        algorithm = [self->_store algorithmForRoom:room.roomId];
                        MXLogWarning(@"[MXCrypto] encryptEventContent: roomState.encryptionAlgorithm is nil for room %@. Try to use algorithm in the crypto store: %@", room.roomId, algorithm);
                    }
                    
                    if (algorithm)
                    {
                        [self setEncryptionInRoom:room.roomId withMembers:userIds algorithm:algorithm inhibitDeviceQuery:NO];
                        alg = self->roomEncryptors[room.roomId];
                    }
                }
                else
                {
                    // For log purpose
                    algorithm = NSStringFromClass(alg.class);
                }

                // Sanity check (we don't expect an encrypted content here).
                if (alg && [eventType isEqualToString:kMXEventTypeStringRoomEncrypted] == NO)
                {
#ifdef DEBUG
                    MXLogDebug(@"[MXCrypto] encryptEventContent: content: %@", eventContent);
#endif

                    MXHTTPOperation *operation2 = [alg encryptEventContent:eventContent eventType:eventType forUsers:userIds success:^(NSDictionary *encryptedContent) {

                        MXLogDebug(@"[MXCrypto] encryptEventContent: Success in %.0fms using sessionId: %@",
                              [[NSDate date] timeIntervalSinceDate:startDate] * 1000,
                              encryptedContent[@"session_id"]);

                        dispatch_async(dispatch_get_main_queue(), ^{
                            success(encryptedContent, kMXEventTypeStringRoomEncrypted);
                        });

                    } failure:^(NSError *error) {
                        MXLogErrorDetails(@"[MXCrypto] encryptEventContent: Error", @{
                            @"error": error ?: @"unknown"
                        });

                        dispatch_async(dispatch_get_main_queue(), ^{
                            failure(error);
                        });
                    }];

                    // Mutate the HTTP operation if an HTTP is required for the encryption
                    [operation mutateTo:operation2];
                }
                else
                {
                    MXLogDebug(@"[MXCrypto] encryptEventContent: Invalid algorithm");

                    NSError *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                         code:MXDecryptingErrorUnableToEncryptCode
                                                     userInfo:@{
                                                                NSLocalizedDescriptionKey: MXDecryptingErrorUnableToEncrypt,
                                                                NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:MXDecryptingErrorUnableToEncryptReason, algorithm]
                                                                }];

                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure(error);
                    });
                }
            });

        } failure:failure];
    }];

    return operation;

#else
    return nil;
#endif
}

- (void)hasKeysToDecryptEvent:(MXEvent *)event onComplete:(void (^)(BOOL))onComplete
{
#ifdef MX_CRYPTO
    
    // We need to go to decryptionQueue only to use getRoomDecryptor
    // Other subsequent calls are thread safe because of the implementation of MXCryptoStore
    dispatch_async(decryptionQueue, ^{
        NSString *algorithm = event.wireContent[@"algorithm"];
        id<MXDecrypting> alg = [self getRoomDecryptor:event.roomId algorithm:algorithm];
        
        BOOL hasKeys = [alg hasKeysToDecryptEvent:event];
        onComplete(hasKeys);
    });
    
#endif
}

- (MXEventDecryptionResult *)decryptEvent:(MXEvent *)event inTimeline:(NSString*)timeline
{
    MXEventDecryptionResult *result;
    
    if (!event.content.count)
    {
        MXLogDebug(@"[MXCrypto] decryptEvent: No content to decrypt in event %@ (isRedacted: %@). Event: %@", event.eventId, @(event.isRedactedEvent), event.JSONDictionary);
        result = [[MXEventDecryptionResult alloc] init];
        result.clearEvent = event.content;
        return result;
    }
    
    NSString *algorithm = event.wireContent[@"algorithm"];
    id<MXDecrypting> alg = [self getRoomDecryptor:event.roomId algorithm:algorithm];
    if (!alg)
    {
        MXLogDebug(@"[MXCrypto] decryptEvent: Unable to decrypt %@ with algorithm %@. Event: %@", event.eventId, algorithm, event.JSONDictionary);
        
        result = [MXEventDecryptionResult new];
        result.error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                           code:MXDecryptingErrorUnableToDecryptCode
                                       userInfo:@{
                                           NSLocalizedDescriptionKey: MXDecryptingErrorUnableToDecrypt,
                                           NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:MXDecryptingErrorUnableToDecryptReason, event, algorithm]
                                       }];
    }
    else
    {
        result = [alg decryptEvent:event inTimeline:timeline];
        if (result.error)
        {
            NSDictionary *details = @{
                @"event_id": event.eventId ?: @"unknown",
                @"error": result.error ?: @"unknown"
            };
            MXLogErrorDetails(@"[MXCrypto] decryptEvent", details);
            MXLogDebug(@"[MXCrypto] decryptEvent: Unable to decrypt event %@", event.JSONDictionary);
            
            if ([result.error.domain isEqualToString:MXDecryptingErrorDomain]
                && result.error.code == MXDecryptingErrorBadEncryptedMessageCode)
            {
                dispatch_async(self.cryptoQueue, ^{
                    [self markOlmSessionForUnwedgingInEvent:event];
                });
            }
        }
    }
    
    return result;
}

- (void)decryptEvents:(NSArray<MXEvent*> *)events
           inTimeline:(NSString*)timeline
           onComplete:(void (^)(NSArray<MXEventDecryptionResult *>*))onComplete
{
    dispatch_async(decryptionQueue, ^{
        NSMutableArray<MXEventDecryptionResult *> *results = [NSMutableArray arrayWithCapacity:events.count];
        
        // TODO: Implement bulk decryption to speed up the process.
        // We need a [MXDecrypting decryptEvents:] method to limit the number of back and forth with olm/megolm module.
        for (MXEvent *event in events)
        {
            [results addObject:[self decryptEvent:event inTimeline:timeline]];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(results);
        });
    });
}

- (MXHTTPOperation*)ensureEncryptionInRoom:(NSString*)roomId
                                   success:(void (^)(void))success
                                   failure:(void (^)(NSError *error))failure
{
    // Create an empty operation that will be mutated later
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];

#ifdef MX_CRYPTO
    MXRoom *room = [_mxSession roomWithRoomId:roomId];
    if (room.summary.isEncrypted)
    {
        MXWeakify(self);
        [room state:^(MXRoomState *roomState) {
            MXStrongifyAndReturnIfNil(self);

            MXWeakify(self);
            [room members:^(MXRoomMembers *roomMembers) {
                MXStrongifyAndReturnIfNil(self);

                // Get user ids in this room
                NSMutableArray *userIds = [NSMutableArray array];
                NSArray<MXRoomMember *> *encryptionTargetMembers = [roomMembers encryptionTargetMembers:roomState.historyVisibility];
                for (MXRoomMember *member in encryptionTargetMembers)
                {
                    [userIds addObject:member.userId];
                }

                MXWeakify(self);
                dispatch_async(self.cryptoQueue, ^{
                    MXStrongifyAndReturnIfNil(self);

                    NSString *algorithm;
                    id<MXEncrypting> alg = self->roomEncryptors[room.roomId];

                    if (!alg)
                    {
                        // The algorithm has not been initialised yet. So, do it now from room state information
                        algorithm = roomState.encryptionAlgorithm;
                        if (algorithm)
                        {
                            [self setEncryptionInRoom:room.roomId withMembers:userIds algorithm:algorithm inhibitDeviceQuery:NO];
                            alg = self->roomEncryptors[room.roomId];
                        }
                    }

                    if (alg)
                    {
                        // Check we have everything to encrypt events
                        MXHTTPOperation *operation2 = [alg ensureSessionForUsers:userIds success:^(NSObject *sessionInfo) {

                            if (success)
                            {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    success();
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
                        
                        [operation mutateTo:operation2];
                    }
                    else if (failure)
                    {
                        NSError *error = [NSError errorWithDomain:MXDecryptingErrorDomain
                                                             code:MXDecryptingErrorUnableToEncryptCode
                                                         userInfo:@{
                                                                    NSLocalizedDescriptionKey: MXDecryptingErrorUnableToEncrypt,
                                                                    NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:MXDecryptingErrorUnableToEncryptReason, algorithm]
                                                                    }];

                        dispatch_async(dispatch_get_main_queue(), ^{
                            failure(error);
                        });
                    }
                });


            } failure:failure];
        }];
    }
    else
#endif
    {
        if (success)
        {
            success();
        }
    }

    return operation;
}

- (void)discardOutboundGroupSessionForRoomWithRoomId:(NSString*)roomId onComplete:(void (^)(void))onComplete
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(self.cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        [self.olmDevice discardOutboundGroupSessionForRoomWithRoomId:roomId];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete();
        });
    });
#else
    onComplete();
#endif
}

- (void)handleDeviceListsChanges:(MXDeviceListResponse*)deviceLists
{
#ifdef MX_CRYPTO

    if (deviceLists.changed.count == 0 && deviceLists.left.count == 0)
    {
        // Don't go further if there is nothing to process
        return;
    }

    MXLogDebug(@"[MXCrypto] handleDeviceListsChanges (changes: %@, left: %@):\nchanges: %@\nleft: %@", @(deviceLists.changed.count), @(deviceLists.left.count),
          deviceLists.changed, deviceLists.left);

    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Flag users to refresh
        for (NSString *userId in deviceLists.changed)
        {
            [self.deviceList invalidateUserDeviceList:userId];
        }

        for (NSString *userId in deviceLists.left)
        {
            [self.deviceList stopTrackingDeviceList:userId];
        }

        // don't flush the outdated device list yet - we do it once we finish
        // processing the sync.
    });

#endif
}

- (void)handleRoomKeyEvent:(MXEvent*)event onComplete:(void (^)(void))onComplete
{
    // Use decryptionQueue as synchronisation because decryptions require room keys
    dispatch_async(decryptionQueue, ^{
        [self onRoomKeyEvent:event];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete();
        });
    });
}

- (void)handleDeviceOneTimeKeysCount:(NSDictionary<NSString *, NSNumber*>*)deviceOneTimeKeysCount
{
#ifdef MX_CRYPTO

    if (deviceOneTimeKeysCount.count == 0)
    {
        // Don't go further if there is nothing to process
        return;
    }

    MXLogDebug(@"[MXCrypto] handleDeviceOneTimeKeysCount: %@ keys on the homeserver", deviceOneTimeKeysCount[kMXKeySignedCurve25519Type]);

    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSNumber *currentCount;
        MXJSONModelSetNumber(currentCount, deviceOneTimeKeysCount[kMXKeySignedCurve25519Type]);

        if (currentCount)
        {
            self->oneTimeKeyCount = [currentCount unsignedIntegerValue];
        }
    });

#endif
}

- (void)handleDeviceUnusedFallbackKeys:(NSArray<NSString *> *)deviceFallbackKeys
{
#ifdef MX_CRYPTO
    if (deviceFallbackKeys == nil) {
        return;
    }
    
    if ([deviceFallbackKeys containsObject:kMXKeySignedCurve25519Type]) {
        return;
    }
    
    if (self.uploadFallbackKeyOperation)
    {
        MXLogDebug(@"[MXCrypto] handleDeviceUnusedFallbackKeys: Fallback key upload already in progress.");
        return;
    }
    
    // We will be checking this often enough for it not to warrant automatic retries.
    self.uploadFallbackKeyOperation = [self generateAndUploadFallbackKey];
#endif
}

- (void)handleSyncResponse:(MXSyncResponse *)syncResponse onComplete:(void (^)(void))onComplete
{
    // Not implemented, the default `MXCrypto` instead uses more specific functions
    // such as `handleRoomKeyEvent` and `handleDeviceUnusedFallbackKeys`. The method
    // is possibly used by `MXCrypto` subclasses.
    onComplete();
}

- (void)onSyncCompleted:(NSString *)oldSyncToken nextSyncToken:(NSString *)nextSyncToken catchingUp:(BOOL)catchingUp
{
#ifdef MX_CRYPTO

    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        if (!oldSyncToken)
        {
            MXLogDebug(@"[MXCrypto] onSyncCompleted: Completed initial sync");

            // If we have a deviceSyncToken, we can tell the deviceList to
            // invalidate devices which have changed since then.
            NSString *oldDeviceSyncToken = self.store.deviceSyncToken;
            if (oldDeviceSyncToken)
            {
                MXLogDebug(@"[MXCrypto] onSyncCompleted: invalidating device list from deviceSyncToken: %@", oldDeviceSyncToken);

                [self invalidateDeviceListsSince:oldDeviceSyncToken to:nextSyncToken success:^() {

                    self.deviceList.lastKnownSyncToken = nextSyncToken;
                    [self.deviceList refreshOutdatedDeviceLists];

                } failure:^(NSError *error) {

                    // If that failed, we fall back to invalidating everyone.
                    MXLogErrorDetails(@"[MXCrypto] onSyncCompleted: Error fetching changed device list", @{
                        @"error": error ?: @"unknown"
                    });
                    [self.deviceList invalidateAllDeviceLists];
                }];
            }
            else
            {
                // Otherwise, we have to invalidate all devices for all users we
                // are tracking.
                MXLogDebug(@"[MXCrypto] onSyncCompleted: Completed first initialsync; invalidating all device list caches");
                [self.deviceList invalidateAllDeviceLists];
            }
        }

        // we can now store our sync token so that we can get an update on
        // restart rather than having to invalidate everyone.
        //
        // (we don't really need to do this on every sync - we could just
        // do it periodically)
        [self.store storeDeviceSyncToken:nextSyncToken];

        // catch up on any new devices we got told about during the sync.
        self.deviceList.lastKnownSyncToken = nextSyncToken;
        [self.deviceList refreshOutdatedDeviceLists];

        // We don't start uploading one-time keys until we've caught up with
        // to-device messages, to help us avoid throwing away one-time-keys that we
        // are about to receive messages for
        // (https://github.com/vector-im/riot-web/issues/2782).
        if (!catchingUp)
        {
            [self maybeUploadOneTimeKeys:nil failure:nil];
            [self->incomingRoomKeyRequestManager processReceivedRoomKeyRequests];
            [self->unrequestedForwardedRoomKeyManager processUnrequestedKeys];
        }
    });

#endif
}

- (MXDeviceInfo *)eventDeviceInfo:(MXEvent *)event
{
    __block MXDeviceInfo *device;

#ifdef MX_CRYPTO

    if (event.isEncrypted)
    {
        // This is a simple read in the db which is thread safe.
        // Return synchronously
        NSString *algorithm = event.wireContent[@"algorithm"];
        device = [self.deviceList deviceWithIdentityKey:event.senderKey andAlgorithm:algorithm];
    }

#endif

    return device;
}


#pragma mark - Local trust

- (void)setDeviceVerification:(MXDeviceVerification)verificationStatus forDevice:(NSString*)deviceId ofUser:(NSString*)userId
                      success:(void (^)(void))success
                      failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO
    dispatch_async(_cryptoQueue, ^{
        [self setDeviceVerification2:verificationStatus forDevice:deviceId ofUser:userId downloadIfNeeded:YES success:success failure:failure];
    });
#else
    if (success)
    {
        success();
    }
#endif
}

- (void)setDeviceVerification2:(MXDeviceVerification)verificationStatus forDevice:(NSString*)deviceId ofUser:(NSString*)userId
              downloadIfNeeded:(BOOL)downloadIfNeeded
                       success:(void (^)(void))success
                       failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO
    MXDeviceInfo *device = [self.store deviceWithDeviceId:deviceId forUser:userId];
    
    // Sanity check
    if (!device)
    {
        if (downloadIfNeeded)
        {
            MXLogDebug(@"[MXCrypto] setDeviceVerificationForDevice: Unknown device. Try to download user's keys for %@:%@", userId, deviceId);
            [self.deviceList downloadKeys:@[userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                [self setDeviceVerification2:verificationStatus forDevice:deviceId ofUser:userId downloadIfNeeded:NO success:success failure:failure];
            } failure:^(NSError *error) {
                if (failure)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure(error);
                    });
                }
            }];
        }
        else
        {
            MXLogDebug(@"[MXCrypto] setDeviceVerificationForDevice: Unknown device %@:%@", userId, deviceId);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(nil);
                });
            }
        }
        return;
    }
    
    MXDeviceTrustLevel *trustLevel = [MXDeviceTrustLevel trustLevelWithLocalVerificationStatus:verificationStatus
                                                                          crossSigningVerified:device.trustLevel.isCrossSigningVerified];
    [device updateTrustLevel:trustLevel];
    [self.store storeDeviceForUser:userId device:device];
    
    if ([userId isEqualToString:self.mxSession.myUserId])
    {
        // If one of the user's own devices is being marked as verified / unverified,
        // check the key backup status, since whether or not we use this depends on
        // whether it has a signature from a verified device
        [self.backup checkAndStartKeyBackup];
        
        // Manage self-verification
        if (verificationStatus == MXDeviceVerified)
        {
            // This is a good time to request all private keys
            MXLogDebug(@"[MXCrypto] setDeviceVerificationForDevice: Request all private keys");
            [self scheduleRequestsForAllPrivateKeys];
            
            // Check cross-signing
            if (self.crossSigning.canCrossSign)
            {
                // Cross-sign our own device
                MXLogDebug(@"[MXCrypto] setDeviceVerificationForDevice: Mark device %@ as self verified", deviceId);
                [self.crossSigning crossSignDeviceWithDeviceId:deviceId userId:userId success:success failure:failure];
                
                // Wait the end of cross-sign before returning
                return;
            }
        }
    }
    
    if (success)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            success();
        });
    }
#endif
}

- (void)setDevicesKnown:(MXUsersDevicesMap<MXDeviceInfo *> *)devices complete:(void (^)(void))complete
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        for (NSString *userId in devices.userIds)
        {
            for (NSString *deviceID in [devices deviceIdsForUser:userId])
            {
                MXDeviceInfo *device = [devices objectForDevice:deviceID forUser:userId];

                if (device.trustLevel.localVerificationStatus == MXDeviceUnknown)
                {
                    MXDeviceTrustLevel *trustLevel =
                    [MXDeviceTrustLevel trustLevelWithLocalVerificationStatus:MXDeviceUnverified
                                                         crossSigningVerified:device.trustLevel.isCrossSigningVerified];
                    [device updateTrustLevel:trustLevel];
                    [self.store storeDeviceForUser:device.userId device:device];
                }
            }
        }

        if (complete)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                complete();
            });
        }
    });
#else
    if (complete)
    {
        complete();
    }
#endif
}

- (void)setUserVerification:(BOOL)verificationStatus forUser:(NSString*)userId
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure
{
    // We cannot remove cross-signing trust for a user in the matrix spec
    NSParameterAssert(verificationStatus);
    
#ifdef MX_CRYPTO
    dispatch_async(_cryptoQueue, ^{
        [self setUserVerification2:verificationStatus forUser:userId downloadIfNeeded:YES success:success failure:failure];
    });
#else
    if (success)
    {
        success();
    }
#endif
}

- (void)setUserVerification2:(BOOL)verificationStatus forUser:(NSString*)userId
            downloadIfNeeded:(BOOL)downloadIfNeeded
                    success:(void (^)(void))success
                    failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO
    MXCrossSigningInfo *crossSigningInfo = [self.store crossSigningKeysForUser:userId];
    
    // Sanity check
    if (!crossSigningInfo)
    {
        if (downloadIfNeeded)
        {
            MXLogDebug(@"[MXCrypto] setUserVerification: Unknown user. Try to download user's keys for %@", userId);
            [self.deviceList downloadKeys:@[userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
                [self setUserVerification2:verificationStatus forUser:userId downloadIfNeeded:NO success:success failure:failure];
            } failure:^(NSError *error) {
                if (failure)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        failure(error);
                    });
                }
            }];
        }
        else
        {
            MXLogDebug(@"[MXCrypto] setUserVerification: Unknown user %@", userId);
            if (failure)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    failure(nil);
                });
            }
        }
        return;
    }
    
    // Store information locally
    if (verificationStatus != crossSigningInfo.trustLevel.isLocallyVerified)
    {
        MXUserTrustLevel *newTrustLevel = [MXUserTrustLevel trustLevelWithCrossSigningVerified:crossSigningInfo.trustLevel.isCrossSigningVerified
                                                                               locallyVerified:verificationStatus];;
        [crossSigningInfo updateTrustLevel:newTrustLevel];
        [_store storeCrossSigningKeys:crossSigningInfo];
    }
    
    // Cross-sign if possible
    if (verificationStatus != crossSigningInfo.trustLevel.isCrossSigningVerified)
    {
        if (self.crossSigning.canCrossSign)
        {
            MXLogDebug(@"[MXCrypto] setUserVerification: Sign user %@ as verified", userId);
            [self.crossSigning signUserWithUserId:userId success:success failure:failure];
            
            // Wait the end of cross-sign before returning
            return;
        }
        else
        {
            // Cross-signing ability should have been checked before going into this hole
            MXLogDebug(@"[MXCrypto] setUserVerification: Cross-signing not enabled. Current state: %@", @(self.crossSigning.state));
            
        }
    }
    
    if (success)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            success();
        });
    }
#endif
}


#pragma mark - Cross-signing trust

- (MXUserTrustLevel*)trustLevelForUser:(NSString*)userId
{
    return [self.store crossSigningKeysForUser:userId].trustLevel ?: [MXUserTrustLevel new];
}

- (MXDeviceTrustLevel*)deviceTrustLevelForDevice:(NSString*)deviceId ofUser:(NSString*)userId;
{
    return [self.store deviceWithDeviceId:deviceId forUser:userId].trustLevel;
}

- (void)trustLevelSummaryForUserIds:(NSArray<NSString*>*)userIds
                      forceDownload:(BOOL)forceDownload
                            success:(void (^)(MXUsersTrustLevelSummary *usersTrustLevelSummary))success
                            failure:(void (^)(NSError *error))failure
{
    [self downloadKeys:userIds forceDownload:forceDownload success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        
        // Read data from the store
        // It has been updated in the process of the downloadKeys response
        [self trustLevelSummaryForUserIds:userIds onComplete:^(MXUsersTrustLevelSummary *trustLevelSummary) {
            success(trustLevelSummary);
        }];
        
    } failure:failure];
}

- (void)trustLevelSummaryForUserIds:(NSArray<NSString*>*)userIds onComplete:(void (^)(MXUsersTrustLevelSummary *trustLevelSummary))onComplete;
{
    // Use cargoQueue for potential huge read requests from the store
    MXWeakify(self);
    dispatch_async(cargoQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        NSUInteger usersCount = 0;
        NSUInteger trustedUsersCount = 0;
        NSUInteger devicesCount = 0;
        NSUInteger trustedDevicesCount = 0;
        
        for (NSString *userId in userIds)
        {
            usersCount++;
            
            MXUserTrustLevel *userTrustLevel = [self trustLevelForUser:userId];
            if (userTrustLevel.isVerified)
            {
                trustedUsersCount++;
                
                for (MXDeviceInfo *device in [self.store devicesForUser:userId].allValues)
                {
                    devicesCount++;
                    if (device.trustLevel.isVerified)
                    {
                        trustedDevicesCount++;
                    }
                }
            }
        }
        
        NSProgress *trustedUsersProgress = [NSProgress progressWithTotalUnitCount:usersCount];
        trustedUsersProgress.completedUnitCount = trustedUsersCount;
        
        NSProgress *trustedDevicesProgress = [NSProgress progressWithTotalUnitCount:devicesCount];
        trustedDevicesProgress.completedUnitCount = trustedDevicesCount;
        
        MXUsersTrustLevelSummary *trustLevelSummary = [[MXUsersTrustLevelSummary alloc] initWithTrustedUsersProgress:trustedUsersProgress
                                                                                           andTrustedDevicesProgress:trustedDevicesProgress];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(trustLevelSummary);
        });
    });
}

#pragma mark - Users keys

- (MXHTTPOperation*)downloadKeys:(NSArray<NSString*>*)userIds
                   forceDownload:(BOOL)forceDownload
                         success:(void (^)(MXUsersDevicesMap<MXDeviceInfo*> *usersDevicesInfoMap,
                                           NSDictionary<NSString*, MXCrossSigningInfo*> *crossSigningKeysMap))success
                         failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO

    // Create an empty operation that will be mutated later
    MXHTTPOperation *operation = [[MXHTTPOperation alloc] init];

    dispatch_async(_cryptoQueue, ^{

        MXHTTPOperation *operation2 = [self.deviceList downloadKeys:userIds forceDownload:forceDownload success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
            if (success)
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    success(usersDevicesInfoMap, crossSigningKeysMap);
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
        
        [operation mutateTo:operation2];
    });

    return operation;
#else
    if (success)
    {
        success(nil);
    }
    return nil;
#endif
}

- (NSDictionary<NSString*, MXDeviceInfo*>*)devicesForUser:(NSString*)userId
{
    NSDictionary<NSString*, MXDeviceInfo*> *devices;

#ifdef MX_CRYPTO
    devices = [self.store devicesForUser:userId];
#endif

    return devices;
}

- (MXDeviceInfo *)deviceWithDeviceId:(NSString*)deviceId ofUser:(NSString*)userId
{
    MXDeviceInfo *device;

#ifdef MX_CRYPTO
    device = [self.store devicesForUser:userId][deviceId];
#endif

    return device;
}

- (void)resetReplayAttackCheckInTimeline:(NSString*)timeline
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(decryptionQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        [self.olmDevice resetReplayAttackCheckInTimeline:timeline];
    });
#endif
}

- (void)resetDeviceKeys
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_sync(decryptionQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        // Reset tracking status
        [self.store storeDeviceTrackingStatus:nil];

        // Reset the sync token
        // [self handleDeviceListsChanges] will download all keys at the coming initial /sync
        [self.store storeDeviceSyncToken:nil];
    });
#endif
}

- (NSString *)version
{
    return [NSString stringWithFormat:@"OLM %@", self.olmVersion];
}

- (NSString *)deviceCurve25519Key
{
#ifdef MX_CRYPTO
    return _olmDevice.deviceCurve25519Key;
#else
    return nil;
#endif
}

- (NSString *)deviceEd25519Key
{
#ifdef MX_CRYPTO
    return _olmDevice.deviceEd25519Key;
#else
    return nil;
#endif
}

- (NSString *)olmVersion
{
#ifdef MX_CRYPTO
    return _olmDevice.olmVersion;
#else
    return nil;
#endif
}


#pragma mark - Gossipping

- (void)requestAllPrivateKeys
{
    MXLogDebug(@"[MXCrypto] requestAllPrivateKeys");
    
    // Request backup private keys
    if (!self.backup.hasPrivateKeyInCryptoStore || !self.backup.enabled)
    {
        MXLogDebug(@"[MXCrypto] requestAllPrivateKeys: Request key backup private keys");
        
        MXWeakify(self);
        [self.backup requestPrivateKeys:^{
            MXStrongifyAndReturnIfNil(self);
            
            if (self.enableOutgoingKeyRequestsOnceSelfVerificationDone)
            {
                [self->outgoingRoomKeyRequestManager setEnabled:YES];
            }
        }];
    }
    
    // Check cross-signing private keys
    if (!self.crossSigning.canCrossSign)
    {
        MXLogDebug(@"[MXCrypto] requestAllPrivateKeys: Request cross-signing private keys");
        [(MXLegacyCrossSigning *)self.crossSigning requestPrivateKeys];
    }
}

- (void)scheduleRequestsForAllPrivateKeys
{
    // For the moment, we have no better solution than waiting a bit before making such request.
    // This 1.5s delay lets time to the other peer to set our device as trusted
    // so that it will accept to gossip the keys to our device.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), _cryptoQueue, ^{
        [self requestAllPrivateKeys];
    });
}


#pragma mark - import/export

- (void)exportRoomKeysWithPassword:(NSString *)password success:(void (^)(NSData *))success failure:(void (^)(NSError *))failure
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(cargoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSData *keyFile;
        NSError *error;

        NSDate *startDate = [NSDate date];

        // Export the keys
        NSMutableArray *keys = [NSMutableArray array];
        for (MXOlmInboundGroupSession *session in [self.store inboundGroupSessions])
        {
            MXMegolmSessionData *sessionData = [session exportSessionData];
            if (sessionData)
            {
                [keys addObject:sessionData.JSONDictionary];
            }
        }

        MXLogDebug(@"[MXCrypto] exportRoomKeysWithPassword: Exportion of %tu keys took %.0fms", keys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

        // Convert them to JSON
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:keys
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&error];
        if (jsonData)
        {
            // Encrypt them
            keyFile = [MXMegolmExportEncryption encryptMegolmKeyFile:jsonData withPassword:password kdfRounds:0 error:&error];
        }

        MXLogDebug(@"[MXCrypto] exportRoomKeysWithPassword: Exported and encrypted %tu keys in %.0fms", keys.count, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

        dispatch_async(dispatch_get_main_queue(), ^{

            if (keyFile)
            {
                if (success)
                {
                    success(keyFile);
                }
            }
            else
            {
                MXLogDebug(@"[MXCrypto] exportRoomKeysWithPassword: Error: %@", error);
                if (failure)
                {
                    failure(error);
                }
            }
        });
    });
#endif
}

- (void)importRoomKeys:(NSArray<NSDictionary *> *)keys success:(void (^)(NSUInteger total, NSUInteger imported))success failure:(void (^)(NSError *))failure
{
#ifdef MX_CRYPTO
    dispatch_async(cargoQueue, ^{

        MXLogDebug(@"[MXCrypto] importRoomKeys:");

        // Convert JSON to MXMegolmSessionData
        NSArray<MXMegolmSessionData *> *sessionDatas = [MXMegolmSessionData modelsFromJSON:keys];

        [self importMegolmSessionDatas:sessionDatas backUp:YES success:success failure:failure];
    });
#endif
}

- (void)importMegolmSessionDatas:(NSArray<MXMegolmSessionData*>*)sessionDatas backUp:(BOOL)backUp success:(void (^)(NSUInteger total, NSUInteger imported))success failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(cargoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXCrypto] importMegolmSessionDatas: backUp: %@", @(backUp));

        NSDate *startDate = [NSDate date];

        // Import keys
        NSArray<MXOlmInboundGroupSession *>* sessions = [self.olmDevice importInboundGroupSessions:sessionDatas];

        MXLogDebug(@"[MXCrypto] importMegolmSessionDatas: Imported %@ keys in store", @(sessions.count));
        
        dispatch_async(self.cryptoQueue, ^{
            // Do not back up the key if it comes from a backup recovery
            if (backUp)
            {
                [self.backup maybeSendKeyBackup];
            }
            else
            {
                [self.store markBackupDoneForInboundGroupSessions:sessions];
            }
            
            // Notify there are new keys
            MXLogDebug(@"[MXCrypto] importMegolmSessionDatas: Notifying about new keys...");
            for (MXOlmInboundGroupSession *session in sessions)
            {
                id<MXDecrypting> alg = [self getRoomDecryptor:session.roomId algorithm:kMXCryptoMegolmAlgorithm];
                [alg didImportRoomKey:session];
            }
            
            NSUInteger imported = sessions.count;
            NSUInteger totalKeyCount = sessionDatas.count;
            
            MXLogDebug(@"[MXCrypto] importMegolmSessionDatas: Complete. Imported %tu keys from %tu provided keys in %.0fms", imported, totalKeyCount, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                if (success)
                {
                    success(totalKeyCount, imported);
                }
            });
        });

    });
#endif
}

- (void)importRoomKeys:(NSData *)keyFile withPassword:(NSString *)password success:(void (^)(NSUInteger total, NSUInteger imported))success failure:(void (^)(NSError *))failure
{
#ifdef MX_CRYPTO
    dispatch_async(cargoQueue, ^{

        MXLogDebug(@"[MXCrypto] importRoomKeys:withPassword:");

        NSError *error;
        NSDate *startDate = [NSDate date];

        NSData *jsonData = [MXMegolmExportEncryption decryptMegolmKeyFile:keyFile withPassword:password error:&error];
        if(jsonData)
        {
            NSArray *keys = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
            if (keys)
            {
                [self importRoomKeys:keys success:^(NSUInteger total, NSUInteger imported) {

                    MXLogDebug(@"[MXCrypto] importRoomKeys:withPassword: Imported %tu keys from %tu provided keys in %.0fms", imported, total, [[NSDate date] timeIntervalSinceDate:startDate] * 1000);

                    if (success)
                    {
                        success(total, imported);
                    }

                } failure:failure];
                return;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{

            MXLogErrorDetails(@"[MXCrypto] importRoomKeys:withPassword: Error", @{
                @"error": error ?: @"unknown"
            });

            if (failure)
            {
                failure(error);
            }
        });
    });
#endif
}

#pragma mark - Key sharing

- (void)pendingKeyRequests:(void (^)(MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests))onComplete
{
    NSParameterAssert(onComplete);

#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        MXUsersDevicesMap<NSArray<MXIncomingRoomKeyRequest *> *> *pendingKeyRequests = self->incomingRoomKeyRequestManager.pendingKeyRequests;

        dispatch_async(dispatch_get_main_queue(), ^{
            onComplete(pendingKeyRequests);
        });
    });
#endif
}

- (void)acceptKeyRequest:(MXIncomingRoomKeyRequest *)keyRequest
                 success:(void (^)(void))success
                 failure:(void (^)(NSError *error))failure
{
#ifdef MX_CRYPTO
    dispatch_async(_cryptoQueue, ^{

        MXLogDebug(@"[MXCrypto] acceptKeyRequest: %@", keyRequest);
        [self acceptKeyRequestFromCryptoThread:keyRequest success:success failure:failure];
    });
#endif
}

- (void)acceptAllPendingKeyRequestsFromUser:(NSString *)userId andDevice:(NSString *)deviceId onComplete:(void (^)(void))onComplete
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSArray<MXIncomingRoomKeyRequest *> *requests = [self->incomingRoomKeyRequestManager.pendingKeyRequests objectForDevice:deviceId forUser:userId];

        MXLogDebug(@"[MXCrypto] acceptAllPendingKeyRequestsFromUser from %@:%@. %@ pending requests", userId, deviceId, @(requests.count));

        for (MXIncomingRoomKeyRequest *request in requests)
        {
            // TODO: Add success and failure blocks to acceptAllPendingKeyRequestsFromUser
            [self acceptKeyRequestFromCryptoThread:request success:nil failure:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (onComplete)
            {
                onComplete();
            }
        });
    });
#endif
}

#ifdef MX_CRYPTO
- (void)acceptKeyRequestFromCryptoThread:(MXIncomingRoomKeyRequest *)keyRequest
                                 success:(void (^)(void))success
                                 failure:(void (^)(NSError *error))failure
{
    NSString *userId = keyRequest.userId;
    NSString *deviceId = keyRequest.deviceId;
    NSString *requestId = keyRequest.requestId;

    NSDictionary *body = keyRequest.requestBody;
    NSString *roomId, *alg;

    MXJSONModelSetString(roomId, body[@"room_id"]);
    MXJSONModelSetString(alg, body[@"algorithm"]);

    // The request is no more pending
    [incomingRoomKeyRequestManager removePendingKeyRequest:requestId fromUser:userId andDevice:deviceId];

    id<MXDecrypting> decryptor = [self getRoomDecryptor:roomId algorithm:alg];
    if (decryptor)
    {
        [decryptor shareKeysWithDevice:keyRequest success:success failure:failure];
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{

            NSDictionary *details = @{
                @"algorithm": alg ?: @"unknown",
                @"room_id": roomId ?: @"unknown",
            };
            MXLogErrorDetails(@"[MXCrypto] acceptPendingKeyRequests: ERROR: unknown alg in room", details);
            if (failure)
            {
                failure(nil);
            }
        });
    }
}
#endif

- (void)ignoreKeyRequest:(MXIncomingRoomKeyRequest *)keyRequest onComplete:(void (^)(void))onComplete
{
#ifdef MX_CRYPTO
    dispatch_async(_cryptoQueue, ^{

        MXLogDebug(@"[MXCrypto] ignoreKeyRequest: %@", keyRequest);
        [self ignoreKeyRequestFromCryptoThread:keyRequest];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (onComplete)
            {
                onComplete();
            }
        });
    });
#endif
}

- (void)ignoreAllPendingKeyRequestsFromUser:(NSString *)userId andDevice:(NSString *)deviceId onComplete:(void (^)(void))onComplete
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        NSArray<MXIncomingRoomKeyRequest *> *requests = [self->incomingRoomKeyRequestManager.pendingKeyRequests objectForDevice:deviceId forUser:userId];

        MXLogDebug(@"[MXCrypto] ignoreAllPendingKeyRequestsFromUser from %@:%@. %@ pending requests", userId, deviceId, @(requests.count));

        for (MXIncomingRoomKeyRequest *request in requests)
        {
            [self ignoreKeyRequestFromCryptoThread:request];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (onComplete)
            {
                onComplete();
            }
        });
    });
#endif
}

#ifdef MX_CRYPTO
- (void)ignoreKeyRequestFromCryptoThread:(MXIncomingRoomKeyRequest *)keyRequest
{
    NSString *userId = keyRequest.userId;
    NSString *deviceId = keyRequest.deviceId;
    NSString *requestId = keyRequest.requestId;

    // Make request no more pending
    [incomingRoomKeyRequestManager removePendingKeyRequest:requestId fromUser:userId andDevice:deviceId];
}
#endif


- (void)setOutgoingKeyRequestsEnabled:(BOOL)enabled onComplete:(void (^)(void))onComplete
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);
        
        [self->outgoingRoomKeyRequestManager setEnabled:enabled];
        
        if (onComplete)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                onComplete();
            });
        }
    });
#endif
}

- (BOOL)isOutgoingKeyRequestsEnabled
{
    return outgoingRoomKeyRequestManager.isEnabled;
}

- (void)reRequestRoomKeyForEvent:(MXEvent *)event
{
#ifdef MX_CRYPTO
    MXWeakify(self);
    dispatch_async(_cryptoQueue, ^{
        MXStrongifyAndReturnIfNil(self);

        MXLogDebug(@"[MXCrypto] reRequestRoomKeyForEvent: %@", event.eventId);

        NSDictionary *wireContent = event.wireContent;
        NSString *algorithm, *senderKey, *sessionId;
        MXJSONModelSetString(algorithm, wireContent[@"algorithm"]);
        MXJSONModelSetString(senderKey, wireContent[@"sender_key"]);
        MXJSONModelSetString(sessionId, wireContent[@"session_id"]);

        if (algorithm && senderKey && sessionId)
        {
            [self->outgoingRoomKeyRequestManager resendRoomKeyRequest:@{
                                                                        @"room_id": event.roomId,
                                                                        @"algorithm": algorithm,
                                                                        @"sender_key": senderKey,
                                                                        @"session_id": sessionId
                                                                        }];
        }
    });
#endif
}


#pragma mark - Crypto settings
- (BOOL)globalBlacklistUnverifiedDevices
{
#ifdef MX_CRYPTO
    return _store.globalBlacklistUnverifiedDevices;
#else
    return NO;
#endif
}

- (void)setGlobalBlacklistUnverifiedDevices:(BOOL)globalBlacklistUnverifiedDevices
{
#ifdef MX_CRYPTO
    _store.globalBlacklistUnverifiedDevices = globalBlacklistUnverifiedDevices;
#endif
}

- (BOOL)isBlacklistUnverifiedDevicesInRoom:(NSString *)roomId
{
#ifdef MX_CRYPTO
    return [_store blacklistUnverifiedDevicesInRoom:roomId];
#else
    return NO;
#endif
}

- (BOOL)isRoomEncrypted:(NSString *)roomId
{
#ifdef MX_CRYPTO
    return [_store algorithmForRoom:roomId] != nil;
#else
    return NO;
#endif
}

- (BOOL)isRoomSharingHistory:(NSString *)roomId
{
    if (!MXSDKOptions.sharedInstance.enableRoomSharedHistoryOnInvite)
    {
        return NO;
    }
    
    MXRoom *room = [self.mxSession roomWithRoomId:roomId];
    MXRoomHistoryVisibility visibility = room.summary.historyVisibility;
    return [visibility isEqualToString:kMXRoomHistoryVisibilityWorldReadable] || [visibility isEqualToString:kMXRoomHistoryVisibilityShared];
}

- (void)setBlacklistUnverifiedDevicesInRoom:(NSString *)roomId blacklist:(BOOL)blacklist
{
#ifdef MX_CRYPTO
    [_store storeBlacklistUnverifiedDevicesInRoom:roomId blacklist:blacklist];
#endif
}


#pragma mark - Private API

#ifdef MX_CRYPTO

- (instancetype)initWithMatrixSession:(MXSession*)matrixSession cryptoQueue:(dispatch_queue_t)theCryptoQueue andStore:(id<MXCryptoStore>)store
{
    // This method must be called on the crypto thread
    self = [super init];
    if (self)
    {
        _mxSession = matrixSession;
        _cryptoQueue = theCryptoQueue;
        _store = store;

        // Default configuration
        _warnOnUnknowDevices = YES;
        _enableOutgoingKeyRequestsOnceSelfVerificationDone = YES;

        decryptionQueue = [MXLegacyCrypto dispatchQueueForUser:_mxSession.matrixRestClient.credentials.userId];
        
        cargoQueue = dispatch_queue_create([NSString stringWithFormat:@"MXCrypto-Cargo-%@", _mxSession.myDeviceId].UTF8String, DISPATCH_QUEUE_SERIAL);
        
        ensureOlmSessionsInProgress = [NSMutableArray array];

        _olmDevice = [[MXOlmDevice alloc] initWithStore:_store];

        _deviceList = [[MXDeviceList alloc] initWithCrypto:self];

        // Use our own REST client that answers on the crypto thread
        _matrixRestClient = [[MXRestClient alloc] initWithCredentials:_mxSession.matrixRestClient.credentials andOnUnrecognizedCertificateBlock:nil andPersistentTokenDataHandler:_mxSession.matrixRestClient.persistTokenDataHandler andUnauthenticatedHandler:_mxSession.matrixRestClient.unauthenticatedHandler];
        _matrixRestClient.completionQueue = _cryptoQueue;

        roomEncryptors = [NSMutableDictionary dictionary];
        roomDecryptors = [NSMutableDictionary dictionary];

        // Build our device keys: they will later be uploaded
        NSString *deviceId = _store.deviceId;
        if (!deviceId)
        {
            // Generate a device id if the homeserver did not provide it or it was lost
            deviceId = [self generateDeviceId];

            MXLogDebug(@"[MXCrypto] Warning: No device id in MXCredentials. The id %@ was created", deviceId);

            [_store storeDeviceId:deviceId];
        }

        NSString *userId = _matrixRestClient.credentials.userId;
        
        _myDevice = [_store deviceWithDeviceId:deviceId forUser:userId];
        if (!_myDevice)
        {
            _myDevice = [[MXDeviceInfo alloc] initWithDeviceId:deviceId];
            _myDevice.userId = userId;
            _myDevice.keys = @{
                               [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, deviceId]: _olmDevice.deviceEd25519Key,
                               [NSString stringWithFormat:@"%@:%@", kMXKeyCurve25519Type, deviceId]: _olmDevice.deviceCurve25519Key,
                               };
            _myDevice.algorithms = [[MXCryptoAlgorithms sharedAlgorithms] supportedAlgorithms];
            [_myDevice updateTrustLevel:[MXDeviceTrustLevel trustLevelWithLocalVerificationStatus:MXDeviceVerified
                                                                             crossSigningVerified:NO]];
            
            // Add our own deviceinfo to the store
            [_store storeDeviceForUser:userId device:_myDevice];
        }

        oneTimeKeyCount = -1;

        outgoingRoomKeyRequestManager = [[MXOutgoingRoomKeyRequestManager alloc]
                                         initWithMatrixRestClient:_matrixRestClient
                                         deviceId:_myDevice.deviceId
                                         cryptoQueue:[MXLegacyCrypto dispatchQueueForUser:_myDevice.userId]
                                         cryptoStore:_store];

        incomingRoomKeyRequestManager = [[MXIncomingRoomKeyRequestManager alloc] initWithCrypto:self];
        
        unrequestedForwardedRoomKeyManager = [[MXUnrequestedForwardedRoomKeyManager alloc] init];
        unrequestedForwardedRoomKeyManager.delegate = self;

        _keyVerificationManager = [[MXLegacyKeyVerificationManager alloc] initWithCrypto:self];
        
        _secretStorage = [[MXSecretStorage alloc] initWithMatrixSession:_mxSession processingQueue:_cryptoQueue];
        _secretShareManager = [[MXSecretShareManager alloc] initWithCrypto:self];

        _crossSigning = [[MXLegacyCrossSigning alloc] initWithCrypto:self];
        
        if ([MXSDKOptions sharedInstance].enableKeyBackupWhenStartingMXCrypto)
        {
            id<MXKeyBackupEngine> engine = [[MXNativeKeyBackupEngine alloc] initWithCrypto:self];
            _backup = [[MXKeyBackup alloc] initWithEngine:engine
                                               restClient:_matrixRestClient
                                       secretShareManager:_secretShareManager
                                                    queue:_cryptoQueue];
        }
        
        MXRecoveryServiceDependencies *dependencies = [[MXRecoveryServiceDependencies alloc] initWithCredentials:_mxSession.matrixRestClient.credentials
                                                                                                          backup:_backup
                                                                                                   secretStorage:_secretStorage
                                                                                                     secretStore:_store
                                                                                                    crossSigning:_crossSigning
                                                                                                     cryptoQueue:_cryptoQueue];
        _recoveryService = [[MXRecoveryService alloc] initWithDependencies:dependencies delegate:self];
        
        cryptoMigration = [[MXCryptoMigration alloc] initWithCrypto:self];
        
        lastNewSessionForcedDates = [MXUsersDevicesMap new];
        
        [self registerEventHandlers];
        
    }
    return self;
}

- (MXDeviceInfo *)eventSenderDeviceOfEvent:(MXEvent *)event
{
    NSString *senderKey = event.senderKey;
    NSString *algorithm = event.wireContent[@"algorithm"];

    if (!senderKey || !algorithm)
    {
        return nil;
    }

    NSArray *forwardingChain = event.forwardingCurve25519KeyChain;
    if (forwardingChain.count > 0)
    {
        // we got this event from somewhere else
        // TODO: check if we can trust the forwarders.
        return nil;
    }

    // senderKey is the Curve25519 identity key of the device which the event
    // was sent from. In the case of Megolm, it's actually the Curve25519
    // identity key of the device which set up the Megolm session.
    MXDeviceInfo *device = [_deviceList deviceWithIdentityKey:senderKey andAlgorithm:algorithm];
    if (!device)
    {
        // we haven't downloaded the details of this device yet.
        return nil;
    }

    // So far so good, but now we need to check that the sender of this event
    // hadn't advertised someone else's Curve25519 key as their own. We do that
    // by checking the Ed25519 claimed by the event (or, in the case of megolm,
    // the event which set up the megolm session), to check that it matches the
    // fingerprint of the purported sending device.
    //
    // (see https://github.com/vector-im/vector-web/issues/2215)
    NSString *claimedKey = event.keysClaimed[kMXKeyEd25519Type];
    if (!claimedKey)
    {
        MXLogDebug(@"[MXCrypto] eventSenderDeviceOfEvent: Event %@ claims no ed25519 key. Cannot verify sending device", event.eventId);
        return nil;
    }

    if (![claimedKey isEqualToString:device.fingerprint])
    {
        MXLogDebug(@"[MXCrypto] eventSenderDeviceOfEvent: Event %@ claims ed25519 key %@. Cannot verify sending device but sender device has key %@", event.eventId, claimedKey, device.fingerprint);
        return nil;
    }
    
    return device;
}

- (BOOL)setEncryptionInRoom:(NSString*)roomId withMembers:(NSArray<NSString*>*)members algorithm:(NSString*)algorithm inhibitDeviceQuery:(BOOL)inhibitDeviceQuery
{
    NSString *existingAlgorithm = [_store algorithmForRoom:roomId];
    if (existingAlgorithm && ![existingAlgorithm isEqualToString:algorithm])
    {
        MXLogWarning(@"[MXCrypto] setEncryptionInRoom: New m.room.encryption event in %@ with an algorithm change from %@ to %@", roomId, existingAlgorithm, algorithm);
        
        // Reset the current encryption in this room.
        // If the new algo is supported, it will be used
        // Else, encryption and sending will be no more possible in this room
        [roomEncryptors removeObjectForKey:roomId];
    }

    Class encryptionClass = [[MXCryptoAlgorithms sharedAlgorithms] encryptorClassForAlgorithm:algorithm];
    if (!encryptionClass)
    {
        NSString *message = [NSString stringWithFormat:@"[MXCrypto] setEncryptionInRoom: Unable to encrypt with %@", algorithm];
        MXLogError(message);
        return NO;
    }

    if (!existingAlgorithm)
    {
        [_store storeAlgorithmForRoom:roomId algorithm:algorithm];
    }

    id<MXEncrypting> alg = [[encryptionClass alloc] initWithCrypto:self andRoom:roomId];

    roomEncryptors[roomId] = alg;

    // make sure we are tracking the device lists for all users in this room.
    MXLogDebug(@"[MXCrypto] setEncryptionInRoom: Enabling encryption in %@; starting to track device lists for all users therein", roomId);

    for (NSString *userId in members)
    {
        [_deviceList startTrackingDeviceList:userId];
    }

    if (!inhibitDeviceQuery)
    {
        [_deviceList refreshOutdatedDeviceLists];
    }

    return YES;
}

- (MXHTTPOperation*)ensureOlmSessionsForUsers:(NSArray*)users
                                      success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                      failure:(void (^)(NSError *error))failure
{
    MXLogDebug(@"[MXCrypto] ensureOlmSessionsForUsers: %@", users);

    NSMutableDictionary<NSString* /* userId */, NSMutableArray<MXDeviceInfo*>*> *devicesByUser = [NSMutableDictionary dictionary];

    for (NSString *userId in users)
    {
        devicesByUser[userId] = [NSMutableArray array];

        NSArray<MXDeviceInfo *> *devices = [self.deviceList storedDevicesForUser:userId];
        for (MXDeviceInfo *device in devices)
        {
            NSString *key = device.identityKey;

            if ([key isEqualToString:_olmDevice.deviceCurve25519Key])
            {
                // Don't bother setting up session to ourself
                continue;
            }

            if (device.trustLevel.localVerificationStatus == MXDeviceBlocked) {
                // Don't bother setting up sessions with blocked users
                continue;
            }

            [devicesByUser[userId] addObject:device];
        }
    }

    return [self ensureOlmSessionsForDevices:devicesByUser force:NO success:success failure:failure];
}

- (MXHTTPOperation*)ensureOlmSessionsForDevices:(NSDictionary<NSString* /* userId */, NSArray<MXDeviceInfo*>*>*)devicesByUser
                                          force:(BOOL)force
                                        success:(void (^)(MXUsersDevicesMap<MXOlmSessionResult*> *results))success
                                        failure:(void (^)(NSError *error))failure

{
    NSMutableArray<MXDeviceInfo*> *devicesWithoutSession = [NSMutableArray array];

    MXUsersDevicesMap<MXOlmSessionResult*> *results = [[MXUsersDevicesMap alloc] init];

    NSUInteger count = 0;
    for (NSString *userId in devicesByUser)
    {
        count += devicesByUser[userId].count;

        for (MXDeviceInfo *deviceInfo in devicesByUser[userId])
        {
            NSString *deviceId = deviceInfo.deviceId;
            NSString *key = deviceInfo.identityKey;

            NSString *sessionId = [_olmDevice sessionIdForDevice:key];
            if (!sessionId || force)
            {
                [devicesWithoutSession addObject:deviceInfo];
            }

            MXOlmSessionResult *olmSessionResult = [[MXOlmSessionResult alloc] initWithDevice:deviceInfo andOlmSession:sessionId];
            [results setObject:olmSessionResult forUser:userId andDevice:deviceId];
        }
    }

    MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices (users: %tu - devices: %tu - force: %@): %@", devicesByUser.count, count, @(force), devicesByUser);

    if (devicesWithoutSession.count == 0)
    {
        MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: Have already sessions for all");
        if (success)
        {
            success(results);
        }
        return nil;
    }

    
    NSString *oneTimeKeyAlgorithm = kMXKeySignedCurve25519Type;
    
    // Devices for which we will make a /claim request
    MXUsersDevicesMap<NSString*> *usersDevicesToClaim = [[MXUsersDevicesMap<NSString*> alloc] init];
    // The same but devices are listed by their identity key
    NSMutableArray<NSString*> *devicesToClaim = [NSMutableArray array];
    
    // Devices (by their identity key) that are waiting for a response to /claim request
    // That can be devices for which we are going to make a /claim request OR devices that
    // already have a pending requests.
    // Once we have emptied this array, we can call the success or the failure block. The
    // operation is complete.
    NSMutableArray<NSString*> *devicesInProgress = [NSMutableArray array];
    
    // Prepare the request for claiming one-time keys
    for (MXDeviceInfo *device in devicesWithoutSession)
    {
        NSString *deviceIdentityKey = device.identityKey;
        
        // Claim only if a request is not yet pending
        if (![ensureOlmSessionsInProgress containsObject:deviceIdentityKey])
        {
            [usersDevicesToClaim setObject:oneTimeKeyAlgorithm forUser:device.userId andDevice:device.deviceId];
            [devicesToClaim addObject:deviceIdentityKey];
            
            [ensureOlmSessionsInProgress addObject:deviceIdentityKey];
        }
        
        // In both case, we need to wait for the creation of the olm session for this device
        [devicesInProgress addObject:deviceIdentityKey];
    }
    
    MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: %@ out of %@ sessions to claim one time keys", @(usersDevicesToClaim.count), @(devicesWithoutSession.count));
    
    
    // Wait for the result of claim request(s)
    // Listen to the dedicated notification
    MXWeakify(self);
    __block id observer;
    observer = [[NSNotificationCenter defaultCenter] addObserverForName:kMXCryptoOneTimeKeyClaimCompleteNotification object:self queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        MXStrongifyAndReturnIfNil(self);
        
        NSArray<NSString*> *devices = note.userInfo[kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey];
        NSError *error = note.userInfo[kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey];
        
        // Was it a /claim request for us?
        if ([devicesInProgress mx_intersectArray:devices])
        {
            if (error)
            {
                MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: Got a notification failure for %@ devices. Fail our current pool of %@ devices", @(devices.count), @(devicesInProgress.count));
                
                // Consider the failure for all requests of the current pool
                [self->ensureOlmSessionsInProgress removeObjectsInArray:devices];
                [devicesInProgress removeAllObjects];
                
                // The game is over for this pool
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                if (failure)
                {
                    failure(error);
                }
            }
            else
            {
                for (NSString *deviceIdentityKey in devices)
                {
                    if ([devicesInProgress containsObject:deviceIdentityKey])
                    {
                        MXDeviceInfo *device = [self.store deviceWithIdentityKey:deviceIdentityKey];
                        NSString *olmSessionId = [self.olmDevice sessionIdForDevice:deviceIdentityKey];
                        
                        // Update the result
                        MXOlmSessionResult *olmSessionResult = [results objectForDevice:device.deviceId forUser:device.userId];
                        olmSessionResult.sessionId = olmSessionId;
                        
                        // This device is no more in progress
                        [devicesInProgress removeObject:deviceIdentityKey];
                        [self->ensureOlmSessionsInProgress removeObject:deviceIdentityKey];
                    }
                }
                
                MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: Got olm sessions for %@ devices. Still missing %@ sessions", @(devices.count), @(devicesInProgress.count));
                
                // If the pool is empty, we are done
                if (!devicesInProgress.count)
                {
                    [[NSNotificationCenter defaultCenter] removeObserver:observer];
                    if (success)
                    {
                        success(results);
                    }
                }
            }
        }
    }];
    
    
    if (usersDevicesToClaim.count == 0)
    {
        MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: All missing sessions are already pending");
        return nil;
    }
    

    MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: claimOneTimeKeysForUsersDevices (users: %tu - devices: %tu)",
          usersDevicesToClaim.map.count, usersDevicesToClaim.count);

    return [_matrixRestClient claimOneTimeKeysForUsersDevices:usersDevicesToClaim success:^(MXKeysClaimResponse *keysClaimResponse) {

        MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: claimOneTimeKeysForUsersDevices response (users: %tu - devices: %tu): %@",
              keysClaimResponse.oneTimeKeys.map.count, keysClaimResponse.oneTimeKeys.count, keysClaimResponse.oneTimeKeys);

        for (NSString *userId in devicesByUser)
        {
            for (MXDeviceInfo *deviceInfo in devicesByUser[userId])
            {
                MXKey *oneTimeKey;
                for (NSString *deviceId in [keysClaimResponse.oneTimeKeys deviceIdsForUser:userId])
                {
                    MXOlmSessionResult *olmSessionResult = [results objectForDevice:deviceId forUser:userId];
                    if (olmSessionResult.sessionId && !force)
                    {
                        // We already have a result for this device
                        continue;
                    }

                    MXKey *key = [keysClaimResponse.oneTimeKeys objectForDevice:deviceId forUser:userId];
                    if ([key.type isEqualToString:oneTimeKeyAlgorithm])
                    {
                        oneTimeKey = key;
                    }

                    if (!oneTimeKey)
                    {
                        MXLogDebug(@"[MXCrypto] ensureOlmSessionsForDevices: No one-time keys (alg=%@) for device %@:%@", oneTimeKeyAlgorithm, userId, deviceId);
                        continue;
                    }

                    [self verifyKeyAndStartSession:oneTimeKey userId:userId deviceInfo:deviceInfo];
                }
            }
        }
        
        // Broadcast the /claim request is done
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCryptoOneTimeKeyClaimCompleteNotification
                                                            object:self
                                                          userInfo: @{
                                                                      kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey: devicesToClaim
                                                                      }];

    } failure:^(NSError *error) {

        MXLogError(@"[MXCrypto] ensureOlmSessionsForDevices: claimOneTimeKeysForUsersDevices request failed.");

        // Broadcast the /claim request is done
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXCryptoOneTimeKeyClaimCompleteNotification
                                                            object:self
                                                          userInfo: @{
                                                                      kMXCryptoOneTimeKeyClaimCompleteNotificationDevicesKey: devicesToClaim,
                                                                      kMXCryptoOneTimeKeyClaimCompleteNotificationErrorKey: error
                                                                      }];
    }];
}

- (NSString*)verifyKeyAndStartSession:(MXKey*)oneTimeKey userId:(NSString*)userId deviceInfo:(MXDeviceInfo*)deviceInfo
{
    NSString *sessionId;

    NSString *deviceId = deviceInfo.deviceId;
    NSString *signKeyId = [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, deviceId];
    NSString *signature = [oneTimeKey.signatures objectForDevice:signKeyId forUser:userId];

    // Check one-time key signature
    NSError *error;
    if ([_olmDevice verifySignature:deviceInfo.fingerprint JSON:oneTimeKey.signalableJSONDictionary signature:signature error:&error])
    {
        // Update the result for this device in results
        sessionId = [_olmDevice createOutboundSession:deviceInfo.identityKey theirOneTimeKey:oneTimeKey.value];

        if (sessionId)
        {
            MXLogDebug(@"[MXCrypto] verifyKeyAndStartSession: Started new olm session id %@ for device %@ (theirOneTimeKey: %@)", sessionId, deviceInfo, oneTimeKey.value);
        }
        else
        {
            // Possibly a bad key
            MXLogErrorDetails(@"[MXCrypto] verifyKeyAndStartSession: Error starting olm session with device", @{
                @"device_id": deviceId ?: @"unknown"
            });
        }
    }
    else
    {
        NSDictionary *details = @{
            @"device_id": deviceId ?: @"unknown",
            @"error": error ?: @"unknown"
        };
        MXLogErrorDetails(@"[MXCrypto] verifyKeyAndStartSession: Unable to verify signature on one-time key for device", details);
    }

    return sessionId;
}

- (NSDictionary*)encryptMessage:(NSDictionary*)payloadFields forDevices:(NSArray<MXDeviceInfo*>*)devices
{
    NSMutableDictionary *ciphertext = [NSMutableDictionary dictionary];
    for (MXDeviceInfo *recipientDevice in devices)
    {
        NSString *sessionId = [_olmDevice sessionIdForDevice:recipientDevice.identityKey];
        if (sessionId)
        {
            NSMutableDictionary *payloadJson = [NSMutableDictionary dictionaryWithDictionary:payloadFields];
            payloadJson[@"sender"] = _matrixRestClient.credentials.userId;
            payloadJson[@"sender_device"] = _store.deviceId;

            // Include the Ed25519 key so that the recipient knows what
            // device this message came from.
            // We don't need to include the curve25519 key since the
            // recipient will already know this from the olm headers.
            // When combined with the device keys retrieved from the
            // homeserver signed by the ed25519 key this proves that
            // the curve25519 key and the ed25519 key are owned by
            // the same device.
            payloadJson[@"keys"] = @{
                                     kMXKeyEd25519Type: _olmDevice.deviceEd25519Key
                                     };

            // Include the recipient device details in the payload,
            // to avoid unknown key attacks, per
            // https://github.com/vector-im/vector-web/issues/2483
            payloadJson[@"recipient"] = recipientDevice.userId;
            payloadJson[@"recipient_keys"] = @{
                                               kMXKeyEd25519Type: recipientDevice.fingerprint
                                               };

            NSData *payloadData = [NSJSONSerialization  dataWithJSONObject:payloadJson options:0 error:nil];
            NSString *payloadString = [[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding];

            //MXLogDebug(@"[MXCrypto] encryptMessage: %@\nUsing sessionid %@ for device %@", payloadJson, sessionId, recipientDevice.identityKey);
            ciphertext[recipientDevice.identityKey] = [_olmDevice encryptMessage:recipientDevice.identityKey sessionId:sessionId payloadString:payloadString];
        }
    }

    return @{
             @"algorithm": kMXCryptoOlmAlgorithm,
             @"sender_key": _olmDevice.deviceCurve25519Key,
             @"ciphertext": ciphertext
             };
}

- (id<MXDecrypting>)getRoomDecryptor:(NSString*)roomId algorithm:(NSString*)algorithm
{
    id<MXDecrypting> alg;

    if (roomId)
    {
        if (!roomDecryptors[roomId])
        {
            roomDecryptors[roomId] = [NSMutableDictionary dictionary];
        }

        alg = roomDecryptors[roomId][algorithm];
        if (alg)
        {
            return alg;
        }
    }

    Class algClass = [[MXCryptoAlgorithms sharedAlgorithms] decryptorClassForAlgorithm:algorithm];
    if (algClass)
    {
        alg = [[algClass alloc] initWithCrypto:self];

        if (roomId)
        {
            roomDecryptors[roomId][algorithm] = alg;
        }
    }

    return alg;
}

- (id<MXEncrypting>)getRoomEncryptor:(NSString*)roomId algorithm:(NSString*)algorithm
{
    if (![algorithm isEqualToString:kMXCryptoMegolmAlgorithm])
    {
        MXLogErrorDetails(@"[MXCrypto] getRoomEncryptor: algorithm is not supported", @{
            @"algorithm": algorithm ?: @"unknown"
        });
        return nil;
    }

    id<MXEncrypting> alg = roomEncryptors[roomId];
    if (alg)
    {
        return alg;
    }
    
    NSString *existingAlgorithm = [self.store algorithmForRoom:roomId];
    if ([algorithm isEqualToString:existingAlgorithm])
    {
        MXLogErrorDetails(@"[MXCrypto] getRoomEncryptor: algorithm does not match the room", @{
            @"algorithm": algorithm ?: @"unknown"
        });
        return nil;
    }
    
    Class algClass = [[MXCryptoAlgorithms sharedAlgorithms] encryptorClassForAlgorithm:algorithm];
    if (!algClass)
    {
        MXLogErrorDetails(@"[MXCrypto] getRoomEncryptor: cannot get encryptor for algorithm", @{
            @"algorithm": algorithm ?: @"unknown"
        });
        return nil;
    }
    
    alg = [[algClass alloc] initWithCrypto:self andRoom:roomId];
    roomEncryptors[roomId] = alg;
    return alg;
}

- (NSDictionary*)signObject:(NSDictionary*)object
{
    return @{
             _myDevice.userId: @{
                     [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, _myDevice.deviceId]: [_olmDevice signJSON:object]
                     }
             };
}


#pragma mark - Key sharing
- (void)requestRoomKey:(NSDictionary*)requestBody recipients:(NSArray<NSDictionary<NSString*, NSString*>*>*)recipients
{
    [outgoingRoomKeyRequestManager sendRoomKeyRequest:requestBody recipients:recipients];
}

- (void)cancelRoomKeyRequest:(NSDictionary*)requestBody
{
    [outgoingRoomKeyRequestManager cancelRoomKeyRequest:requestBody];
}

- (void)handleUnrequestedRoomKeyInfo:(MXRoomKeyInfo *)keyInfo senderId:(NSString *)senderId senderKey:(NSString *)senderKey
{
    [unrequestedForwardedRoomKeyManager addPendingKeyWithKeyInfo:keyInfo senderId:senderId senderKey:senderKey];
}

- (NSDictionary*)buildMegolmKeyForwardingMessage:(NSString*)roomId senderKey:(NSString*)senderKey sessionId:(NSString*)sessionId  chainIndex:(NSNumber*)chainIndex
{
    NSDictionary *key = [self.olmDevice getInboundGroupSessionKey:roomId senderKey:senderKey sessionId:sessionId chainIndex:chainIndex];
    if (key)
    {
        return @{
                 @"type": kMXEventTypeStringRoomForwardedKey,
                 @"content": @{
                         @"algorithm": kMXCryptoMegolmAlgorithm,
                         @"room_id": roomId,
                         @"sender_key": senderKey,
                         @"sender_claimed_ed25519_key": key[@"sender_claimed_ed25519_key"],
                         @"session_id": sessionId,
                         @"session_key": key[@"key"],
                         @"chain_index": key[@"chain_index"],
                         @"forwarding_curve25519_key_chain": key[@"forwarding_curve25519_key_chain"],
                         kMXSharedHistoryKeyName: key[@"shared_history"]
                         }
                 };
    }
    
    return nil;
}

#pragma mark - Private methods
/**
 Get or create the GCD queue for a given user.

 @param userId the user id.
 @return the dispatch queue to use to handle the crypto for this user.
 */
+ (dispatch_queue_t)dispatchQueueForUser:(NSString*)userId
{
    static NSMutableDictionary <NSString*, dispatch_queue_t> *dispatchQueues;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatchQueues = [NSMutableDictionary dictionary];
    });

    dispatch_queue_t queue = dispatchQueues[userId];
    if (!queue)
    {
        @synchronized (dispatchQueues)
        {
            MXLogDebug(@"[MXCrypto] Create dispatch queue for %@'s crypto", userId);
            queue = dispatch_queue_create([NSString stringWithFormat:@"MXCrypto-%@", userId].UTF8String, DISPATCH_QUEUE_SERIAL);
            dispatchQueues[userId] = queue;
        }
    }

    return queue;
}

- (NSString*)generateDeviceId
{
    return [[[MXTools generateSecret] stringByReplacingOccurrencesOfString:@"-" withString:@""] substringToIndex:10];
}

/**
 Ask the server which users have new devices since a given token,
 and invalidate them.

 @param oldSyncToken the old token.
 @param lastKnownSyncToken the new token.
 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)invalidateDeviceListsSince:(NSString*)oldSyncToken to:(NSString*)lastKnownSyncToken
                           success:(void (^)(void))success
                           failure:(void (^)(NSError *error))failure
{
    [_matrixRestClient keyChangesFrom:oldSyncToken to:lastKnownSyncToken success:^(MXDeviceListResponse *deviceLists) {

        MXLogDebug(@"[MXCrypto] invalidateDeviceListsSince: got key changes since %@: changed: %@\nleft: %@", oldSyncToken, deviceLists.changed, deviceLists.left);

        [self handleDeviceListsChanges:deviceLists];

        success();

    } failure:failure];
}

/**
 Listen to events that change the signatures chain.
 */
- (void)registerEventHandlers
{
    dispatch_async(dispatch_get_main_queue(), ^{

        // Observe incoming to-device events
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onToDeviceEvent:) name:kMXSessionOnToDeviceEventNotification object:self.mxSession];

        // Observe membership changes
        MXWeakify(self);
        self->roomMembershipEventsListener = [self.mxSession listenToEventsOfTypes:@[kMXEventTypeStringRoomEncryption, kMXEventTypeStringRoomMember] onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {

            MXStrongifyAndReturnIfNil(self);
            
            if (direction == MXTimelineDirectionForwards)
            {
                if (event.eventType == MXEventTypeRoomEncryption)
                {
                    [self onCryptoEvent:event];
                }
                else if (event.eventType == MXEventTypeRoomMember)
                {
                    [self onRoomMembership:event roomState:customObject];
                }
            }
        }];

    });
}

/**
 Handle a to-device event.

 @param notification the notification containing the to-device event.
 */
- (void)onToDeviceEvent:(NSNotification *)notification
{
    MXEvent *event = notification.userInfo[kMXSessionNotificationEventKey];

    MXLogDebug(@"[MXCrypto] onToDeviceEvent: event.type: %@", event.type);

    if (_cryptoQueue)
    {
        MXWeakify(self);
        switch (event.eventType)
        {
            case MXEventTypeRoomForwardedKey:
            {
                dispatch_async(_cryptoQueue, ^{
                    MXStrongifyAndReturnIfNil(self);

                    [self onRoomKeyEvent:event];
                });
                break;
            }

            case MXEventTypeRoomKeyRequest:
            {
                dispatch_async(_cryptoQueue, ^{
                    MXStrongifyAndReturnIfNil(self);

                    [self->incomingRoomKeyRequestManager onRoomKeyRequestEvent:event];
                });
                break;
            }

            default:
                break;
        }
    }
}

/**
 Handle a key event.

 @param event the key event.
 */
- (void)onRoomKeyEvent:(MXEvent*)event
{
    if (!event.content[@"room_id"] || !event.content[@"algorithm"])
    {
        MXLogError(@"[MXCrypto] onRoomKeyEvent: ERROR: Key event is missing fields");
        return;
    }

    id<MXDecrypting> alg = [self getRoomDecryptor:event.content[@"room_id"] algorithm:event.content[@"algorithm"]];
    if (!alg)
    {
        NSString *message = [NSString stringWithFormat:@"[MXCrypto] onRoomKeyEvent: ERROR: Unable to handle keys for %@", event.content[@"algorithm"]];
        MXLogError(message);
        return;
    }

    [alg onRoomKeyEvent:event];
}

/**
 Handle an m.room.encryption event.

 @param event the encryption event.
 */
- (void)onCryptoEvent:(MXEvent*)event
{
    MXRoom *room = [_mxSession roomWithRoomId:event.roomId];

    MXWeakify(self);    
    [room state:^(MXRoomState *roomState) {
        MXStrongifyAndReturnIfNil(self);
        
        // We can start tracking only lazy loaded room members
        // All room members will be loaded when necessary, ie when encrypting in the room
        MXRoomMembers *roomMembers = roomState.members;
        
        NSMutableArray *members = [NSMutableArray array];
        NSArray<MXRoomMember *> *encryptionTargetMembers = [roomMembers encryptionTargetMembers:roomState.historyVisibility];
        for (MXRoomMember *roomMember in encryptionTargetMembers)
        {
            [members addObject:roomMember.userId];
        }
        
        if (self.cryptoQueue)
        {
            dispatch_async(self.cryptoQueue, ^{
                [self setEncryptionInRoom:event.roomId withMembers:members algorithm:event.content[@"algorithm"] inhibitDeviceQuery:YES];
            });
        }
    }];
}

/**
 Handle a change in the membership state of a member of a room.

 @param event the membership event causing the change.
 @param roomState the know state of the room when the event occurs.
 */
- (void)onRoomMembership:(MXEvent*)event roomState:(MXRoomState*)roomState
{
    // Check whether we have to track the devices for this user.
    BOOL shouldTrack = NO;
    NSString *userId = event.stateKey;
    
    MXRoomMemberEventContent *content = [MXRoomMemberEventContent modelFromJSON:event.content];
    if ([userId isEqualToString:self.mxSession.credentials.userId] && [content.membership isEqualToString:kMXMembershipStringInvite])
    {
        [unrequestedForwardedRoomKeyManager onRoomInviteWithRoomId:event.roomId senderId:event.sender];
    }
    
    MXRoomMember *member = [roomState.members memberWithUserId:userId];
    if (member)
    {
        if (member.membership == MXMembershipJoin)
        {
            MXLogDebug(@"[MXCrypto] onRoomMembership: Join event for %@ in %@", member.userId, event.roomId);
            shouldTrack = YES;
        }
        // Check whether we should encrypt for the invited members too
        else if (member.membership == MXMembershipInvite && ![roomState.historyVisibility isEqualToString:kMXRoomHistoryVisibilityJoined])
        {
            // track the deviceList for this invited user.
            // Caution: there's a big edge case here in that federated servers do not
            // know what other servers are in the room at the time they've been invited.
            // They therefore will not send device updates if a user logs in whilst
            // their state is invite.
            MXLogDebug(@"[MXCrypto] onRoomMembership: Invite event for %@ in %@", member.userId, event.roomId);
            shouldTrack = YES;
        }
    }
    
    if (shouldTrack && self.cryptoQueue)
    {
        MXWeakify(self);
        dispatch_async(self.cryptoQueue, ^{
            MXStrongifyAndReturnIfNil(self);
            
            // make sure we are tracking the deviceList for this user
            [self.deviceList startTrackingDeviceList:member.userId];
        });
    }
}

/**
 Upload my user's device keys.
 */
- (MXHTTPOperation *)uploadDeviceKeys:(void (^)(MXKeysUploadResponse *keysUploadResponse))success failure:(void (^)(NSError *))failure
{
    // Sanity check
    if (!_matrixRestClient.credentials.userId)
    {
        MXLogError(@"[MXCrypto] uploadDeviceKeys. ERROR: _matrixRestClient.credentials.userId cannot be nil");
        failure(nil);
        return nil;
    }

    // Prepare the device keys data to send
    // Sign it
    NSString *signature = [_olmDevice signJSON:_myDevice.signalableJSONDictionary];
    _myDevice.signatures = @{
                            _matrixRestClient.credentials.userId: @{
                                    [NSString stringWithFormat:@"%@:%@", kMXKeyEd25519Type, _myDevice.deviceId]: signature
                                    }
                            };

    // For now, we set the device id explicitly, as we may not be using the
    // same one as used in login.
    return [_matrixRestClient uploadKeys:_myDevice.JSONDictionary oneTimeKeys:nil fallbackKeys:nil success:success failure:failure];
}

/**
 Check if it's time to upload one-time keys, and do so if so.
 */
- (void)maybeUploadOneTimeKeys:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    if (uploadOneTimeKeysOperation)
    {
        MXLogDebug(@"[MXCrypto] maybeUploadOneTimeKeys: already in progress");
        if (success)
        {
            success();
        }
        return;
    }

    NSDate *now = [NSDate date];
    if (lastOneTimeKeyCheck && [now timeIntervalSinceDate:lastOneTimeKeyCheck] < kMXCryptoUploadOneTimeKeysPeriod)
    {
        // We've done a key upload recently.
        if (success)
        {
            success();
        }
        return;
    }

    lastOneTimeKeyCheck = now;

    if (oneTimeKeyCount != -1)
    {
        // We already have the current one_time_key count from a /sync response.
        // Use this value instead of asking the server for the current key count.
        MXLogDebug(@"[MXCrypto] maybeUploadOneTimeKeys: there are %tu one-time keys on the homeserver", oneTimeKeyCount);
        
        MXWeakify(self);
        uploadOneTimeKeysOperation = [self generateAndUploadOneTimeKeys:oneTimeKeyCount retry:YES success:^{
            MXStrongifyAndReturnIfNil(self);
            
            self->uploadOneTimeKeysOperation = nil;
            if (success)
            {
                success();
            }
            
        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);
            
            MXLogErrorDetails(@"[MXCrypto] maybeUploadOneTimeKeys: Failed to publish one-time keys", @{
                @"error": error ?: @"unknown"
            });
            self->uploadOneTimeKeysOperation = nil;
            
            if (failure)
            {
                failure(error);
            }
        }];
        
        if (!uploadOneTimeKeysOperation && success)
        {
            success();
        }

        // Reset oneTimeKeyCount to prevent start uploading based on old data.
        // It will be set again on the next /sync-response
        oneTimeKeyCount = -1;
    }
    else
    {
        // Ask the server how many keys we have
        MXWeakify(self);
        uploadOneTimeKeysOperation = [self publishedOneTimeKeysCount:^(NSUInteger keyCount) {

            if (!self->uploadOneTimeKeysOperation)
            {
                if (success)
                {
                    success();
                }
                return;
            };

            MXWeakify(self);
            MXHTTPOperation *operation2 = [self generateAndUploadOneTimeKeys:keyCount retry:YES success:^{
                MXStrongifyAndReturnIfNil(self);
                
                self->uploadOneTimeKeysOperation = nil;
                if (success)
                {
                    success();
                }
                
            } failure:^(NSError *error) {
                MXStrongifyAndReturnIfNil(self);
                
                MXLogErrorDetails(@"[MXCrypto] maybeUploadOneTimeKeys: Failed to publish one-time keys", @{
                    @"error": error ?: @"unknown"
                });
                self->uploadOneTimeKeysOperation = nil;
                
                if (failure)
                {
                    failure(error);
                }
            }];
            
            if (operation2)
            {
                [self->uploadOneTimeKeysOperation mutateTo:operation2];
            }
            else
            {
                self->uploadOneTimeKeysOperation = nil;
                if (success)
                {
                    success();
                }
            }

        } failure:^(NSError *error) {
            MXStrongifyAndReturnIfNil(self);

            MXLogErrorDetails(@"[MXCrypto] maybeUploadOneTimeKeys: Get published one-time keys count failed", @{
                @"error": error ?: @"unknown"
            });
            self->uploadOneTimeKeysOperation = nil;

            if (failure)
            {
                failure(error);
            }
        }];
    }
}

- (MXHTTPOperation *)generateAndUploadOneTimeKeys:(NSUInteger)keyCount retry:(BOOL)retry success:(void (^)(void))success failure:(void (^)(NSError *))failure
{
    MXLogDebug(@"[MXCrypto] generateAndUploadOneTimeKeys: %@ one time keys are available on the homeserver", @(keyCount));
          
    MXHTTPOperation *operation;
    
    if ([self generateOneTimeKeys:keyCount])
    {
        operation = [self uploadOneTimeKeys:^(MXKeysUploadResponse *keysUploadResponse) {
            success();
        } failure:^(NSError *error) {
            MXLogErrorDetails(@"[MXCrypto] generateAndUploadOneTimeKeys: Failed to publish one-time keys", @{
                @"error": error ?: @"unknown"
            });
            
            if ([MXError isMXError:error] && retry)
            {
                // The homeserver explicitly rejected the request.
                // Reset local OTKs we tried to push and retry
                // There is no matrix specific error but we really want to detect the error described at
                // https://github.com/vector-im/element-ios/issues/3721
                MXLogError(@"[MXCrypto] uploadOneTimeKeys: Reset local OTKs because the server does not like them");
                [self.olmDevice markOneTimeKeysAsPublished];
                
                [self generateAndUploadOneTimeKeys:keyCount retry:NO success:success failure:failure];
            }
            else
            {
                failure(error);
            }
        }];
    }
    
    return operation;
}

- (MXHTTPOperation *)generateAndUploadFallbackKey
{
    [_olmDevice generateFallbackKey];
    
    NSDictionary *fallbackKey = _olmDevice.fallbackKey;
    NSMutableDictionary *fallbackKeyJson = [NSMutableDictionary dictionary];
    
    for (NSString *keyId in fallbackKey[kMXKeyCurve25519Type])
    {
        // Sign the fallback key
        NSMutableDictionary *signedKey = [NSMutableDictionary dictionary];
        signedKey[@"key"] = fallbackKey[kMXKeyCurve25519Type][keyId];
        signedKey[@"fallback"] = @(YES);
        signedKey[@"signatures"] = [self signObject:signedKey];
        
        fallbackKeyJson[[NSString stringWithFormat:@"%@:%@", kMXKeySignedCurve25519Type, keyId]] = signedKey;
    }
    
    MXLogDebug(@"[MXCrypto] generateAndUploadFallbackKey: Started uploading fallback key.");
    
    MXWeakify(self);
    return [_matrixRestClient uploadKeys:nil oneTimeKeys:nil fallbackKeys:fallbackKeyJson success:^(MXKeysUploadResponse *keysUploadResponse) {
        MXStrongifyAndReturnIfNil(self);
        
        self.uploadFallbackKeyOperation = nil;
        MXLogDebug(@"[MXCrypto] generateAndUploadFallbackKey: Finished uploading fallback key.");
    } failure:^(NSError *error) {
        MXStrongifyAndReturnIfNil(self);
        
        self.uploadFallbackKeyOperation = nil;
        MXLogError(@"[MXCrypto] generateAndUploadFallbackKey: Failed uploading fallback key.");
    }];
}

/**
 Generate required one-time keys.

 @param keyCount the number of key currently available on the homeserver.
 @return NO if no keys need to be generated.
 */
- (BOOL)generateOneTimeKeys:(NSUInteger)keyCount
{
    // We need to keep a pool of one time public keys on the server so that
    // other devices can start conversations with us. But we can only store
    // a finite number of private keys in the olm Account object.
    // To complicate things further then can be a delay between a device
    // claiming a public one time key from the server and it sending us a
    // message. We need to keep the corresponding private key locally until
    // we receive the message.
    // But that message might never arrive leaving us stuck with duff
    // private keys clogging up our local storage.
    // So we need some kind of enginering compromise to balance all of
    // these factors.

    MXLogDebug(@"[MXCrypto] generateOneTimeKeys: %tu one-time keys on the homeserver", keyCount);

    // First check how many keys we can store in the Account object.
    NSUInteger maxOneTimeKeys = _olmDevice.maxNumberOfOneTimeKeys;

    // Try to keep at most half that number on the server. This leaves the
    // rest of the slots free to hold keys that have been claimed from the
    // server but we haven't recevied a message for.
    // If we run out of slots when generating new keys then olm will
    // discard the oldest private keys first. This will eventually clean
    // out stale private keys that won't receive a message.
    NSUInteger keyLimit = maxOneTimeKeys / 2;

    // We work out how many new keys we need to create to top up the server
    // If there are too many keys on the server then we don't need to
    // create any more keys.
    NSUInteger numberToGenerate = 0;
    if (keyLimit > keyCount)
    {
        numberToGenerate = keyLimit - keyCount;
    }


    MXLogDebug(@"[MXCrypto] generateOneTimeKeys: Generate %tu keys", numberToGenerate);

    if (numberToGenerate)
    {
        // Ask olm to generate new one time keys, then upload them to synapse.
        NSDate *startDate = [NSDate date];
        [_olmDevice generateOneTimeKeys:numberToGenerate];
        MXLogDebug(@"[MXCrypto] generateOneTimeKeys: Keys generated in %.0fms", [[NSDate date] timeIntervalSinceDate:startDate] * 1000);
    }

    return (numberToGenerate > 0);
}

/**
 Upload my user's one time keys.
 */
- (MXHTTPOperation *)uploadOneTimeKeys:(void (^)(MXKeysUploadResponse *keysUploadResponse))success failure:(void (^)(NSError *))failure
{
    NSDictionary *oneTimeKeys = _olmDevice.oneTimeKeys;
    NSMutableDictionary *oneTimeJson = [NSMutableDictionary dictionary];

    for (NSString *keyId in oneTimeKeys[kMXKeyCurve25519Type])
    {
        // Sign each one-time key
        NSMutableDictionary *k = [NSMutableDictionary dictionary];
        k[@"key"] = oneTimeKeys[kMXKeyCurve25519Type][keyId];
        k[@"signatures"] = [self signObject:k];

        oneTimeJson[[NSString stringWithFormat:@"%@:%@", kMXKeySignedCurve25519Type, keyId]] = k;
    }

    MXLogDebug(@"[MXCrypto] uploadOneTimeKeys: Upload %tu keys", ((NSDictionary*)oneTimeKeys[kMXKeyCurve25519Type]).count);

    // For now, we set the device id explicitly, as we may not be using the
    // same one as used in login.
    MXWeakify(self);
    return [_matrixRestClient uploadKeys:nil oneTimeKeys:oneTimeJson fallbackKeys:nil success:^(MXKeysUploadResponse *keysUploadResponse) {
        MXStrongifyAndReturnIfNil(self);

        [self.olmDevice markOneTimeKeysAsPublished];
        success(keysUploadResponse);

    } failure:^(NSError *error) {
        MXLogError(@"[MXCrypto] uploadOneTimeKeys fails.");
        failure(error);
    }];
}

// Ask the server how many keys we have
- (MXHTTPOperation *)publishedOneTimeKeysCount:(void (^)(NSUInteger publishedKeyCount))success failure:(void (^)(NSError *))failure
{
    return [_matrixRestClient uploadKeys:_myDevice.JSONDictionary oneTimeKeys:nil fallbackKeys:nil success:^(MXKeysUploadResponse *keysUploadResponse) {
        
        NSUInteger publishedkeyCount = [keysUploadResponse oneTimeKeyCountsForAlgorithm:kMXKeySignedCurve25519Type];
        
        MXLogDebug(@"[MXCrypto] publishedOneTimeKeysCount: %@ OTKs on the homeserver", @(publishedkeyCount));
        
        success(publishedkeyCount);
        
    } failure:^(NSError *error) {
        MXLogErrorDetails(@"[MXCrypto] publishedOneTimeKeysCount failed", @{
            @"error": error ?: @"unknown"
        });
        failure(error);
    }];
}


#pragma mark Wedged olm sessions

- (void)markOlmSessionForUnwedgingInEvent:(MXEvent*)event
{
    NSString *sender = event.sender;
    NSString *deviceKey, *algorithm;
    MXJSONModelSetString(deviceKey, event.content[@"sender_key"]);
    MXJSONModelSetString(algorithm, event.content[@"algorithm"]);
    
    MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedging from %@:%@", sender, deviceKey);

    if (!sender || !deviceKey || !algorithm)
    {
        return;
    }
    
    if ([sender isEqualToString:_mxSession.myUserId]
        && [deviceKey isEqualToString:self.olmDevice.deviceCurve25519Key])
    {
        MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedging: Do not unwedge ourselves");
        return;
    }
    
    // Check when we last forced a new session with this device: if we've already done so
    // recently, don't do it again.
    NSDate *lastNewSessionForcedDate = [lastNewSessionForcedDates objectForDevice:deviceKey forUser:sender];
    if (lastNewSessionForcedDate
        && -[lastNewSessionForcedDate timeIntervalSinceNow] < kMXCryptoMinForceSessionPeriod)
    {
        MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedging: New session already forced with device at %@. Not forcing another", lastNewSessionForcedDate);
        return;
    }

    // Establish a new olm session with this device since we're failing to decrypt messages
    // on a current session.
    MXDeviceInfo *device = [_store deviceWithIdentityKey:deviceKey];
    if (!device)
    {
        MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedgingInEvent: Couldn't find device for identity key %@: not re-establishing session", deviceKey);
        return;
    }
    
    MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedging from %@:%@", sender, device.deviceId);
    
    [lastNewSessionForcedDates setObject:[NSDate date] forUser:sender andDevice:deviceKey];
    
    NSDictionary *userDevice = @{
                                 sender: @[device]
                                 };
    [self ensureOlmSessionsForDevices:userDevice force:YES success:^(MXUsersDevicesMap<MXOlmSessionResult *> *results) {
        
        // Now send a blank message on that session so the other side knows about it.
        // (The keyshare request is sent in the clear so that won't do)
        // We send this first such that, as long as the toDevice messages arrive in the
        // same order we sent them, the other end will get this first, set up the new session,
        // then get the keyshare request and send the key over this new session (because it
        // is the session it has most recently received a message on).
        NSDictionary *encryptedContent = [self encryptMessage:@{
                                                                @"type": @"m.dummy"
                                                                }
                                                   forDevices:@[device]];
        
        MXUsersDevicesMap<NSDictionary*> *contentMap = [MXUsersDevicesMap new];
        [contentMap setObject:encryptedContent forUser:sender andDevice:device.deviceId];
        
        MXToDevicePayload *payload = [[MXToDevicePayload alloc] initWithEventType:kMXEventTypeStringRoomEncrypted
                                                                       contentMap:contentMap];
        [self.matrixRestClient sendToDevice:payload success:nil failure:^(NSError *error) {
            MXLogDebug(@"[MXCrypto] markOlmSessionForUnwedgingInEvent: ERROR for sendToDevice: %@", error);
        }];
        
    } failure:^(NSError *error) {
        MXLogErrorDetails(@"[MXCrypto] markOlmSessionForUnwedgingInEvent: ERROR for ensureOlmSessionsForDevices", @{
            @"error": error ?: @"unknown"
        });
    }];
}

#pragma mark - MXUnrequestedForwardedRoomKeyManagerDelegate

- (void)downloadDeviceKeysWithUserId:(NSString *)userId completion:(void (^)(MXUsersDevicesMap<MXDeviceInfo *> *))completion
{
    [self downloadKeys:@[userId] forceDownload:YES success:^(MXUsersDevicesMap<MXDeviceInfo *> *usersDevicesInfoMap, NSDictionary<NSString *,MXCrossSigningInfo *> *crossSigningKeysMap) {
        completion(usersDevicesInfoMap);
    } failure:^(NSError *error) {
        MXLogError(@"[MXCrypto]: Failed downloading keys for key forward manager");
        completion([[MXUsersDevicesMap alloc] init]);
    }];
}

- (void)acceptRoomKeyWithKeyInfo:(MXRoomKeyInfo *)keyInfo
{
    id<MXDecrypting> decryptor = [self getRoomDecryptor:keyInfo.roomId algorithm:keyInfo.algorithm];
    MXRoomKeyResult *key = [[MXRoomKeyResult alloc] initWithType:MXRoomKeyTypeUnsafe info:keyInfo];
    [decryptor onRoomKey:key];
}

#endif

@end
