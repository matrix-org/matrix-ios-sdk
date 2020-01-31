Changes in Matrix iOS SDK in 0.16.0 (2019-xx-xx)
===============================================

Improvements:
 * Make enums conform to `Equatable`/`Hashable` where applicable.
 * Aggregations: Implement m.reference aggregations, aka thread ([MSC1849](https://github.com/matrix-org/matrix-doc/blob/matthew/msc1849/proposals/1849-aggregations.md)).
 * Cross-Signing: Add a new module, MXCrossSigning, to handle device cross-signing (vector-im/riot-ios/issues/2890).
 * MXRoom: Add a method to retrieve trusted members count in an encrypted room.
 * MXSession: Add createRoomWithParameters with a MXRoomCreationParameters model class.
 * MXRoomCreationParameters: Support the initial_state parameter and allow e2e on room creation (vector-im/riot-ios/issues/2943).
 * MXCrypto: Expose devicesForUser.
 * MXRoomSummary: Add the trust property to indicate trust in other users and devices in the room (vector-im/riot-ios/issues/2906).

Bug fix:
 * MXEventType: Fix Swift refinement.
 * MXCryptoStore does not store device.algorithm (https://github.com/vector-im/riot-ios/issues/2896).

API break:
 * MXCrypto: the `downloadKeys` method now returns users cross-signing keys.
 * MXDeviceInfo: the `verified` property has been replaced by `trustLevel`.
 * MXSession & MXRestClient: the `createRoom` method with a long list of parameters
   has been replaced by `createRoomWithParameters`.

Changes in Matrix iOS SDK in 0.15.2 (2019-12-05)
===============================================

Improvements:
 * Add macOS target with unit tests.

Bug fix:
 * MXCallAudioSessionConfigurator: Fix compilation issue with macOS.
 * MXRoomSummary: Fix potential crash when `_lastMessageOthers` is null.
 
API break:
 * MXCallAudioSessionConfigurator: Now unavailable for macOS.

Changes in Matrix iOS SDK in 0.15.1 (2019-12-04)
===============================================

Improvements:
 * Well-known: Expose "m.integrations" according to [MSC1957](https://github.com/matrix-org/matrix-doc/pull/1957) (vector-im/riot-ios#2815).
 * MXSession: Expose and store homeserverWellknown.
 * SwiftMatrixSDK: Add missing start(withSyncFilter:) refinement to MXSession.swift.
 
Bug fix:
 * MXIdentityServerRestClient: Match registration endpoint to the IS r0.3.0 spec (vector-im/riot-ios#2824).

Changes in Matrix iOS SDK in 0.15.0 (2019-11-06)
===============================================

Improvements:
 * MX3PidAddManager: Add User-Interactive Auth to /account/3pid/add (vector-im/riot-ios#2744).
 * MXSession: On resume, make the first /sync request trigger earlier (vector-im/riot-ios#2793).
 * MXCrypto: Do not fail to decrypt when there is nothing to decrypt (redacted events).

Bug fix:
 * Room members who left are listed with the actual members (vector-im/riot-ios#2737).
 * MX3PidAddManager: Add User-Interactive Auth to /account/3pid/add (vector-im/riot-ios#2744).
 * MXHTTPOperation: Make urlResponseFromError return the url response in case of MXError.
 * MXHTTPOperation: Fix a crash in `-mutateTo:` method when operation parameter is nil.
 * VoIP: Fix regression when using a TURN server (vector-im/riot-ios#2796).

API break:
 * MXBackgroundModeHandler: Update interface and now use a single method that return a MXBackgroundTask.

Changes in Matrix iOS SDK in 0.14.0 (2019-10-11)
===============================================

Improvements:
 * MXServiceTerms: A class to support MSC2140 (Terms of Service API) (vector-im/riot-ios#2600).
 * MXRestClient: Remove identity server URL fallback to homeserver one's when there is no identity server configured.
 * MXRestClient: Add new APIs from MSC2290 (matrix-org/matrix-doc/pull/2290).
 * MXHTTPClient: Improve M_LIMIT_EXCEEDED error handling: Do not wait to try again if the mentioned delay is too long.
 * MXEventTimeline: The roomEventFilter property is now writable (vector-im/riot-ios#2615).
 * VoIP: Make call start if there is no STUN server.
 * MXMatrixVersions: Add doesServerRequireIdentityServerParam and doesServerAcceptIdentityAccessToken properties.
 * MXMatrixVersions: Support r0.6.0. Add doesServerSupportSeparateAddAndBind (vector-im/riot-ios#2718).
 * Create MXIdentityServerRestClient and MXIdentityService to manage identity server requests (vector-im/riot-ios#2647).
 * MXIdentityService: Support identity server v2 API. Handle identity server v2 API authentification and use the hashed v2 lookup API for 3PIDs (vector-im/riot-ios#2603 and /vector-im/riot-ios#2652).
 * MXHTTPClient: Add access token renewal plus request retry mechanism.
 * MXHTTPClient: Do not retry requests if the host is not valid.
 * MXAutoDiscovery: Add initWithUrl contructor.
 * MX3PidAddManager: New class to handle add 3pids to HS and to bind to IS.
 * Privacy: Store Identity Server in Account Data ([MSC2230](https://github.com/matrix-org/matrix-doc/pull/2230))(vector-im/riot-ios#2665).
 * Privacy: Lowercase emails during IS lookup calls (vector-im/riot-ios#2696).
 * Privacy: MXRestClient: Use `id_access_token` in CS API when required (vector-im/riot-ios#2704).
 * Privacy: Sending Third-Party Request Tokens via the Homeserver ([MSC2078](https://github.com/matrix-org/matrix-doc/pull/2078)).

API break:
 * MXRestClient: Remove identity server requests. Now MXIdentityService is used to perform identity server requests.
 * MXRestClient: requestTokenForPhoneNumber returns an additional optional parameter (`submitUrl`).
 
Bug Fix:
 * Send kMXSessionCryptoDidCorruptDataNotification from the main thread.

Changes in Matrix iOS SDK in 0.13.1 (2019-08-08)
===============================================

Improvements:
 * MXError: Expose httpResponse.
 * Soft logout: Handle new CS API error code (vector-im/riot-ios/issues/2584).
 * MXRoomCreateContent: Add missing fields `room_version` and `m.federate` (Note: `creator` field becomes optional (because of MSC2175)).
 * Logs: Remove MXJSONModelSet warnings for MXRoomMemberEventContent and MXGroupProfile.
 * Aggregations: Expose reaction history API.

Bug Fix:
 * Crypto: Fix a race condition that prevented message from being sent (vector-im/riot-ios/issues/2541).
 * MXRoom: storeLocalReceipt: Add a sanity check to avoid crash.

Changes in Matrix iOS SDK in 0.13.0 (2019-07-16)
===============================================

Improvements:
 * MXHTTPClient: support multiple SSL pinning modes (none/public key/certificate)
 * MXHTTPClient: Enable the certificate pinning mode by default as soon as some certificates are present in the application bundle.
 * MXHTTPClient: Add a new notification name `kMXHTTPClientMatrixErrorNotification` posted on each Matrix error.
 * Join Room: Support via parameters to better handle federation (vector-im/riot-ios/issues/2547).
 * MXEvent: Create a MXEventUnsignedData model for `MXEvent.unsignedData`.
 * MXEvent: Add relatesTo property.
 * Aggregations: Create MXSession.MXAggregations to manage Matrix aggregations API.
 * Add the Matrix errors related to the password policy.
 * SwiftMatrixSDK: Migrate to Swift 5.0.
 * VoIP: Stop falling back to Google for STUN (vector-im/riot-ios/issues/2532).
 * Storage: Isolate our realm DBs to avoid migration due to change in another realm.
 * MXRoom: sendFile: Use the original file name by default.
 * Push: MXRestClient: Add a method to get all pushers.
 * MXRoomSummary: Send an update when the event id of a local echo changes.
 * MXRoomSummary: Manage edits (vector-im/riot-ios/issues/2583).

Bug Fix:
 * MXMediaLoader: Disable trusting the built-in anchors certificates when the certificate pinning is enabled.
 * Crypto: Device Verification: Name for 🔒 is "Lock" (vector-im/riot-ios/issues/2526).

API break:
 * MXEvent: unsignedData is now of type MXEventUnsignedData.
 * MXRestClient: Remove the joinRoom method with least parameters.
 * MXSession, MXRestClient: Add viaServers parameters to all joinRoom methods.

Changes in Matrix iOS SDK in 0.12.5 (2019-05-03)
===============================================

Improvements:
 * Crypto: Handle partially-shared sessions better (vector-im/riot-ios/issues/2320).
 * Crypto: Support Interaction Device Verification (vector-im/riot-ios/issues/2322).
 * MXSession: add a global notification posted when the account data are updated from the homeserver.
 * VoIP: Use WebRTC framework included in Jitsi Meet SDK (vector-im/riot-ios/issues/1483).

Bug Fix:
 * MXRoomSummaryUpdater: Fix `MXRoomSummary.hiddenFromUser` property not being saved when associated room become tombstoned (vector-im/riot-ios/issues/2148).
 * MXFileStore not loaded with 0 rooms, thanks to @asydorov (PR #647).

Changes in Matrix iOS SDK in 0.12.4 (2019-03-21)
===============================================

Bug Fix:
 * MXRestClient: Fix file upload with filename containing whitespace (PR #645).

Changes in Matrix iOS SDK in 0.12.3 (2019-03-08)
===============================================

Improvements:
 * Maintenance: Update cocopoads and pods. Automatic update to Swift4.2.
 * MXCredentials: Create a new data model for it, separated from the CS API response data model (new MXLoginResponse class).
 * MXAutoDiscovery: New class to manage .well-known data (vector-im/riot-ios/issues/2117).
 * Login: Handle well-known data in the login response - MSC1730 (vector-im/riot-ios/issues/2298).
 * Login: Add kMXLoginFlowTypeCAS & kMXLoginFlowTypeSSO.
 * MXRestClient: Expose acceptableContentTypes.
 * MXHTTPOperation: Add urlResponseFromError:, a tool to retrieve the original NSHTTPURLResponse object.

Bug Fix:
 * Crypto: Fix crash in MXKeyBackup (vector-im/riot-ios/issues/#2281).
 * Escape room v3 event ids in permalinks (vector-im/riot-ios/issues/2277).

Changes in Matrix iOS SDK in 0.12.2 (2019-02-15)
===============================================

Improvements:
 * MXRestClient: Update CS API call to support event ids hashes in room version 3 (vector-im/riot-ios#2194).
 * MXRoom: Add a sendAudioFile API to send file using msgType "m.audio", thanks to N-Pex (PR #616).
 * MXCrypto: Add key backup passphrase support (vector-im/riot-ios#2127).
 * MXCrypto: Key backup: Ignore all whitespaces in recovery key (vector-im/riot-ios#2194).
 * MXJSONModel: Use instancetype as return type of `modelFromJSON` initializer.
 * MXKeyBackup: Add MXKeyBackupStateNotTrusted state.
 * MXKeyBackup: Do not reset MXKeyBackup.keyBackupVersion in error states.
 * MXKeyBackup: Implement the true deleteKeyBackupVersion Client-Server API.
 * MXKeyBackup: Declare backup trust using new `PUT /room_keys/version/{version}` API (vector-im/riot-ios/issues/2223).
 * Crypto: Cancel share request on restore/import (vector-im/riot-ios/issues/#2232).
 * Crypto: Improve key import performance (vector-im/riot-ios/issues/#2248).

Bug Fix:
 * Crypto: Device deduplication method sometimes crashes (vector-im/riot-ios/issues/#2167).
 * MXSession: A new invite to a direct chat that I left is not displayed as direct.
 * MXSession/Swift: fix expected return type from createRoom.
 * MXRealmCryptoStore: fix outgoingRoomKeyRequestWithRequestBody that was sometimes not able to find existing request.

API break:
* MXKeyBackup: Rename isKeyBackupTrusted to trustForKeyBackupVersion.

Changes in Matrix iOS SDK in 0.12.1 (2019-01-04)
===============================================

Improvements:
 * MXCrypto: Use the last olm session that got a message (vector-im/riot-ios/issues/2128).
 * MXScanManager: Support the encrypted body (the request body is now encrypted by default using the server public key).
 * MXMediaManager: Support the encrypted body.

Bug Fix:
 * MXCryptoStore: Stop duplicating devices in the store (vector-im/riot-ios/issues/2132).
 * MXPeekingRoom: the room preview is broken (vector-im/riot-ios/issues/2126).

Changes in Matrix iOS SDK in 0.12.0 (2018-12-06)
===============================================

Improvements:
 * MXCrypto: Add the MXKeyBackup module to manage e2e keys backup (vector-im/riot-ios#2070).
 * MXMediaManager/MXMediaLoader: Do not allow non-mxc content URLs.
 * MXMediaManager: Add a constructor based on a homeserver URL, to handle directly the Matrix Content URI (mxc://...).
 * MXSession: Add a MediaManager instance to handle the media stored on the Matrix Content repository.
 * MXMediaManager: Support the media download from a Matrix Content Scanner (Antivirus Server).
 * MXJSONModels: Add data models for Terms of service / privacy policy API (https://github.com/matrix-org/matrix-doc/blob/travis/msc/terms-api/proposals/1692-terms-api.md).
 * Swift: Add explicit public initializer to MX3PID struct, thanks to @tladesignz (PR #594).
 * Tests: Make MXRealmCryptoStore work the first time tests are launched on simulators for iOS 11 and higher.
 * Add MXScanManager a media antivirus scanner (PR#600).
 
Bug Fix:
 * MXRestClient: [avatarUrlForUser:success:failure]: the returned url is always nil, thanks to @asydorov (PR #580) and @giomfo.
 * MXRoomSummary: fix null Direct Chat displayname / avatar issue caused by limited syncs.
 * MXRoom: members methods don't respond after a failure.
 * MXRealmCryptoStore: Make queries inside transactionWithBlock.

API break:
 * MXMediaManager: [downloadMediaFromURL:andSaveAtFilePath:success:failure:] is removed, use [downloadMediaFromMatrixContentURI:withType:inFolder:success:failure] or [downloadThumbnailFromMatrixContentURI:withType:inFolder:toFitViewSize:withMethod:success:failure] instead.
 * MXMediaManager: [downloadMediaFromURL:andSaveAtFilePath:] is removed, use [downloadMediaFromMatrixContentURI:withType:inFolder:] instead.
 * MXMediaManager: [existingDownloaderWithOutputFilePath:] is removed, use [existingDownloaderWithIdentifier:] instead.
 * MXMediaManager: [cachePathForMediaWithURL:andType:inFolder:] is removed, use [cachePathForMatrixContentURI:andType:inFolder:] instead.
 * MXMediaLoader: the notification names "kMXMediaDownloadxxx" and "kMXMediaUploadxxx" are removed, use kMXMediaLoaderStateDidChangeNotification instead.
 * MXMediaLoader: [downloadMediaFromURL:andSaveAtFilePath:success:failure] is removed, use [downloadMediaFromURL:withIdentifier:andSaveAtFilePath:success:failure] instead.
 * MXRestClient: [urlOfContent:] and [urlOfContentThumbnail:toFitViewSize:withMethod:] are removed.
 * The Matrix Content repository contants are moved to MXEnumConstants.h
 * [urlOfIdenticon:] is moved from MXRestClient to MXMediaManager.

Changes in Matrix iOS SDK in 0.11.6 (2018-10-31)
===============================================

Improvements:
 * Upgrade OLMKit version (3.0.0).
 * MXHTTPClient: Send Access-Token as header instead of query param (vector-im/riot-ios/issues/2071).
 * MXCrypto: Encrypt the messages for invited members according to the history visibility (#559)
 * MXSession: When create a room as direct wait for room being tagged as direct chat before calling success block.
 * CallKit is now disabled in China (PR #578).
 * Add MXEncryptedContentFile and MXEncryptedContentKey classes.
 * MXRestClient: Handle GET /_matrix/client/r0/profile/{userId} request.

Bug fix:
 * MXEvent: Move `invite_room_state` to the correct place in the client-server API (vector-im/riot-ios/issues/2010).
 * MXRoomSummaryUpdater: Fix minor issue in updateSummaryAvatar method.
 * Left room is still displayed as "Empty room" in rooms list (vector-im/riot-ios/issues/2082).
 * Reply of reply with unexpected newlines renders badly (vector-im/riot-ios/issues/2086).

API break:
* MXCrypto: importRoomKeys methods now return number of imported keys.

Changes in Matrix iOS SDK in 0.11.5 (2018-10-05)
===============================================

Improvements:
 * MXSession: Add eventWithEventId:inRoom: method.
 * MXRoomState: Add pinnedEvents to list pinned events ids.
 * MXServerNotices: Add this class to get notices from the user homeserver.

Changes in Matrix iOS SDK in 0.11.4 (2018-09-26)
===============================================

Improvements:
 * MXRoom: Expose room members access in Swift (PR #562).
 * MXPeekingRoom: Create a MXPeekingRoomSummary class to represent their summary data.
 * MXRoomSummary: If no avatar, try to compute it from heroes.
 * MXRoomSummary: If no avatar for an invited room, try to compute it from available state events.
 * MXRoomSummary: Internationalise the room name computation for rooms with no name.
 * MXRoomMember: Add Swift refinement for membership properties.

Bug fix:
 * Lazy-Loading: Fix regression on peeking (vector-im/riot-ios/issues/2035).
 * MXRestClient: Fix get public rooms list Swift refinement.
 * MXTools: Allow '@' in room alias (vector-im/riot-ios/issues/1977).

Changes in Matrix iOS SDK in 0.11.3 (2018-08-27)
===============================================

Bug fix:
 * MXJSONModel: Manage `m.server_notice` empty tag sent due to a bug server side (PR #556).

Changes in Matrix iOS SDK in 0.11.2 (2018-08-24)
===============================================

Improvements:
 * MXSession: Add the supportedMatrixVersions method getting versions of the specification supported by the homeserver.
 * MXRestClient: Add testUserRegistration to check earlier if a username can be registered.
 * MXSession: Add MXSessionStateSyncError state and MXSession.syncError to manage homeserver resource quota on /sync requests (vector-im/riot-ios/issues/1937).
 * MXError: Add kMXErrCodeStringResourceLimitExceeded to manage homeserver resource quota (vector-im/riot-ios/issues/1937).
 * MXError: Define constant strings for keys and values that can be found in a Matrix JSON dictionary error.
 * Tests: MXHTTPClient_Private.h: Add method to set fake delay in HTTP requests.
 
Bug fix:
 * People tab is empty in the share extension (vector-im/riot-ios/issues/1988).
 * MXError: MXError lost NSError.userInfo information.

Changes in Matrix iOS SDK in 0.11.1 (2018-08-17)
===============================================

Improvements:
 * Tests: Add DirectRoomTests to test direct rooms management.

Bug fix:
 * Direct rooms can be lost on an initial /sync (vector-im/riot-ios/issues/1983).
 * Fix possible race conditions in direct rooms management.
 * Avoid to create an empty filter on each [MXSession start:]

Changes in Matrix iOS SDK in 0.11.0 (2018-08-10)
===============================================

Improvements:
 * MXSession: Add the option to use a Matrix filter in /sync requests ([MXSession startWithSyncFilter:]).
 * MXSession: Add API to manage Matrix filters.
 * MXRestClient: Add Matrix filter API.
 * MXRoom: Add send reply with text message (vector-im/riot-ios#1911).
 * MXRoom: Add an asynchronous methods for liveTimeline, state and members.
 * MXRoom: Add methods to manage the room liveTimeline listeners synchronously.
 * MXRoomState: Add a membersCount property to store members stats independently from MXRoomMember objects.
 * MXRoomSummary: Add a membersCount property to cache MXRoomState one.
 * MXRoomSummary: Add a membership property to cache MXRoomState one.
 * MXRoomSummary: add isConferenceUserRoom.
 * MXStore: Add Obj-C annotations.
 * MXFileStore: Add a setting to set which data to preload ([MXFileStore setPreloadOptions:]).
 * Manage the new summary API from the homeserver( MSC: https://docs.google.com/document/d/11i14UI1cUz-OJ0knD5BFu7fmT6Fo327zvMYqfSAR7xs/edit#).
 * MXRoom: Add send reply with text message (vector-im/riot-ios#1911).
 * Support room versioning (vector-im/riot-ios#1938).

Bug fix:
 * MXRestClient: Fix filter parameter in messagesForRoom. It must be sent as an inline JSON string.
 * Sends read receipts on login (vector-im/riot-ios/issues/1918).

API break:
 * MXSession: [MXSession startWithMessagesLimit] has been removed. Use the more generic [MXSession startWithSyncFilter:].
 * MXRoom: liveTimeline and state accesses are now asynchronous.
 * MXCall: callee access is now asynchronous.
 * MXRoomState: Remove displayName property. Use MXRoomSummary.displayName instead.
 * MXRoomState: Create a MXRoomMembers property. All members getter methods has been to the new class.
 * MXStore: Make the stateOfRoom method asynchronous.
 * MXRestClient: contextOfEvent: Add a filter parameter.

Changes in Matrix iOS SDK in 0.10.12 (2018-05-31)
=============================================== 

Improvements:
 * MXCrypto: Add reRequestRoomKeyForEvent to re-request encryption keys to decrypt an event (vector-im/riot-ios/issues/1879).
 * Matrix filters: Create or update models for them: MXFilter, MXRoomFilter & MXRoomEventFilter.
 * MXRestClient: Factorise processing and completion blocks handling.
 * Read Receipts: Notify the app for implicit read receipts.
 * Replace all current `__weak typeof(self) weakSelf = self;...` dances by MXWeakify / MXStrongifyAndReturnIfNil.
 * Doc: Update instructions to install Synapse used in SDK integration tests
 
Bug fix:
 * MXRoomSummary: Fix a memory leak
 * MXRoom: A message (or a media) can be sent whereas the user cancelled it. This can make the app crash.
 * MXCrypto: Fix code that went into a dead-end.
 * MXMegolmDecryption: Fix unused overridden var.
 * Analytics: Do not report rooms count on every sync.

API break:
 * Analytics: Rename all kMXGoogleAnalyticsXxx constant values to kMXAnalyticsXxx.

Changes in Matrix iOS SDK in 0.10.11 (2018-05-31)
=============================================== 

Improvements:
 * MXSession: Add setAccountData.
 * MXSession: Add account deactivation
 * MKTools: Create MXWeakify & MXStrongifyAndReturnIfNil

Changes in Matrix iOS SDK in 0.10.10 (2018-05-23)
=============================================== 

Improvements:
 * MXTools: Regex optimisation: Cache regex of [MXTools stripNewlineCharacters:].
 * MXSession: Make MXAccountData member public.
 * Send Stickers: Manage local echo for sticker (vector-im/riot-ios#1860).
 * GDPR: Handle M_CONSENT_NOT_GIVEN error (vector-im/riot-ios#1871).

Bug fixes:
 * Groups: Avoid flair to make requests in loop in case the HS returns an empty response for `/publicised_groups` (vector-im/riot-ios#1869).

Changes in Matrix iOS SDK in 0.10.9 (2018-04-23)
=============================================== 

Bug fixes:
 * Regression: Sending a photo from the photo library causes a crash.

Changes in Matrix iOS SDK in 0.10.8 (2018-04-20)
=============================================== 

Improvements:
 * Pod: Update realm version (#483)
 * Render stickers in the timeline (vector-im/riot-ios#1819).

Bug fixes:
 * MatrixSDK/JingleCallStack: Upgrade the minimal iOS version to 9.0 because the WebRTC framework requires it (vector-im/riot-ios#1821).
 * App fails to logout on unknown token (vector-im/riot-ios#1839).
 * All rooms showing the same avatar (vector-im/riot-ios#1673).

Changes in Matrix iOS SDK in 0.10.7 (2018-03-30)
=============================================== 

Improvements:
 * Make state event redaction handling gentler with homeserver (vector-im/riot-ios#1823).

Bug fixes:
 * Room summary is not updated after redaction of the room display name (vector-im/riot-ios#1822).

Changes in Matrix iOS SDK in 0.10.6 (2018-03-12)
=============================================== 

Improvements:
 * SwiftMatrixSDK is now compatible with Swift 4, thanks to @johnflanagan-spok (PR #463).
 * Crypto: Make sure we request keys for only valid matrix user ids.
 * MXRoom: We should retry messages with same txn id when hitting 'resend' (vector-im/riot-ios#1731).
 * MXTools: Make isMatrixUserIdentifier support historical user ids (vector-im/riot-ios#1743).
 * MXRestClient: Add [MXRestClient eventWithEventId:] and [MXRestClient eventWithEventId:inRoom:].
 * Improve server load on event redaction (vector-im/riot-ios#1730).
 * Make tests pass again.
 
Bug fixes:
 * Push: Missing push notifications after answering a call (vector-im/riot-ios#1757).
 * Direct Chat: a room was marked as direct by mistake when I joined it.
 * MXRoom: Canceled message can be sent if there is only one in the message sending queue.
 * MXTools: Fix the regex part for the HS domain part in all isMatrixXxxxIdentifier methods.
 * MXFileStore: commits can stay pending after [MXFileStore close].
 * MXFileStore: Make sure data is flushed to files on [MXFileStore close].
 * MXFileStore: The  metadata (containing eventStremToken) can be not stored in files.
 * MXOutgoingRoomKeyRequestManager: Fix crash reported by app store.
 * MXCallKitAdapter: Clean better when releasing an instance.

API breaks:
 * MXCrypto: Remove deviceWithDeviceId and devicesForUser methods because they return local values that may be out of sync. Use downloadKeys instead (vector-im/riot-ios#1782).
 * MXRestClient: Add a txnId parameter to the sendEventToRoom method to better follow the matrix spec.
 
Changes in Matrix iOS SDK in 0.10.5 (2018-02-09)
=============================================== 

Improvements:
 * Groups: Handle the user's groups and their data (vector-im/riot-meta#114).
 * Groups: Add methods to accept group invite and leave it (vector-im/riot-meta#114).
 * MXSession - Groups Flair: Handle the publicised groups for the matrix users (vector-im/riot-meta#118).
 * MXRoomState - Groups Flair: Support the new state event type `m.room.related_groups`(vector-im/riot-meta#118).
 * Create SDK extensions: JingleCallStack and Google Analytics are now separated from the core sdk code (PR #432).
 * MXFileStore: Run only one background task for [MXFileStore commit] (PR #436).
 * MXTools - Groups: add `isMatrixGroupIdentifier` method.
 * Bumped SwiftMatrixSDK.podspec dependency to GZIP 1.2.1, thanks to @nrakochy.
 * MXSDKOptions: Remove enableGoogleAnalytics. It is no more used (PR #448).
 * Crypto: The crypto is now built by default in matrix-ios-sdk (PR #449).

Bug fixes:
 * Room Summary Notification Count is not computed correctly until entering a room with at least one message (#409).
 * Crypto: Fix crash when we try to generate a negative number of one time keys (PR #445).
 * Medias not loading with an optional client certificate (#446), thanks to @r2d2leboss.
 * Crypto: Fix crash when sharing keys on broken network (PR #451).

Changes in Matrix iOS SDK in 0.10.4 (2017-11-30)
=============================================== 

Improvements:
 * Crypto: Support the room key sharing (vector-im/riot-meta#113).
 * Crypto: Store permanently incoming room key requests (vector-im/riot-meta#121).
 * Crypto: use device_one_time_keys_count transmitted by /sync.
 * MXCrypto: Add a proper onSyncCompleted method (PR #410).
 * MXCrypto: Start it before syncing with the HS.
 * MXCrypto: Add deviceWithDeviceId.
 * MXCrypto: add ignoreKeyRequest & ignoreAllPendingKeyRequestsFromUser methods.
 * Remove the support of the new_device event (PR #421).
 * Remove AssetsLibrary framework use (deprecated since iOS 9).
 * MXSession: kMXSessionDidSyncNotification now comes with MXSyncResponse object result returned by the homeserver.

Bug fixes:
 * Fix many warnings regarding strict prototypes, thanks to @beatrupp.

API breaks:
 * Remove CoreData implementation of MXStore (It was not used).
 * MXCrypto: Make `decryptEvent` return decryption results (PR #426).

Changes in Matrix iOS SDK in 0.10.3 (2017-11-13)
=============================================== 

Bug fixes:
 * A 1:1 invite is not displayed as a direct chat after clearing the cache.

Changes in Matrix iOS SDK in 0.10.1 (2017-10-27)
===============================================

Improvements:
 * Notifications: implement @room notifications (vector-im/riot-meta#119).
 * MXTools: Add a reusable generateTransactionId method.
 * MXRoom: Prevent multiple occurrences of the room id in the direct chats dictionary of the account data. 
 
Bug fixes:
 * CallKit - When I reject or answer a call on one device, it should stop ringing on all other iOS devices (vector-im/riot-ios#1618).

API breaks:
 * Crypto: Remove MXFileCryptoStore (We stopped to maintain it one year ago).

Changes in Matrix iOS SDK in 0.10.0 (2017-10-23)
===============================================

Improvements:
 * Call: Add CallKit support, thanks to @morozkin.
 * MXRoom: Preserve message sending order.
 * MXRealmCryptoStore: Move the existing db file from the default folder to the shared container.
 * MXSession: Add `isEventStreamInitialised` flag.
 * MXRestClient: Store certificates allowed by the end user in the initWithHomeServer method too.
 * MXRestClient: Improve registration parameters handling (vector-im/riot-ios#910).
 * MXCall: Go into MXCallStateCreateAnswer state on [MXCall answer] even if there are unknown devices in e2e rooms.
 * MXLogger: Make it compatible with MXSDKOptions.applicationGroupIdentifier to write app extensions logs to file.
 * MXLogger: Add setSubLogName method to log extensions into different files
 * MXLogger: Log up to 10 life cycles.
 
Bug fixes:
 * Call: Fix freeze when making a 2nd call.
 * MXEventTimeline: Fix crash when the user changes the language in the app.
 * Store is reset by mistake on app launch when the user has left a room (vector-im/riot-ios#1574).
 * MXRoom: sendEventOfType: Copy the event content to send to keep it consistent in multi-thread conditions (like in e2e) (vector-im/riot-ios#1581).
 * Mark all messages as read does not work well (vector-im/riot-ios#1425).

Changes in Matrix iOS SDK in 0.9.3 (2017-10-03)
===============================================

Improvements:
 * MXSession: Fix parallel /sync requests streams (PR #360).
 * Add new async method for loading users with particular userIds, thanks to @morozkin (PR #357).
 * MXFileStore: Add necessary async API for room state events and accountdata, (PR #361, PR #363).
 * MXMemoryStore: improve getEventReceipts implementation (PR #364).
 * MXRestClient: Add the openIdToken method (PR #365).
 * MXEvent: Add MXEventTypeRoomBotOptions & MXEventTypeRoomPlumbing. (PR #370).
 * Crypto: handleDeviceListsChanges: Do not switch to the processing thread if there is nothing to do.
 * MXRoomSummary: Add the server timestamp (PR #376).
 
Bug fixes:
 * [e2e issue] Decrypt error related to new device creation (#340).
 * Fix inbound video calls don't have speakerphone turned on by default (vector-im/riot-ios#933), thanks to @morozkin (PR #359).
 * Override audio output handling by WebRTC, thanks to @morozkin (PR #358).
 * Room settings: the displayed room access settings is wrong (vector-im/riot-ios#1494)
 * Fix retain cycle between room and eventTimeLine, thanks to @samuel-gallet (PR #352).
 * Fix API for unbanning and kicking, thanks to @ThibaultFarnier (PR #367).
 * When receiving an invite tagged as DM it's filed in rooms (vector-im/riot-ios#1308).
 * Altering DMness of rooms is broken (vector-im/riot-ios#1370).
 * Video attachment: App crashes when video compression fails (PR #369).
 * Background task release race condition (PR #374).
 * MXHTTPClient: Fix a regression that prevented the app from reconnecting when the network comes back (PR #375).

Changes in Matrix iOS SDK in 0.9.2 (2017-08-25)
===============================================

Improvements:
 * MXRoom: Added an option to send a file and keep it's filename, thanks to @aramsargsyan (#354).
 
Bug fixes:
 * MXHTTPClient: retain cycles, thanks to @morozkin (#350).
 * MXPushRuleEventMatchConditionChecker: inaccurate regex, thanks to @morozkin (#353).
 * MXRoomState: returning old data for some properties, thanks to @morozkin (#355).

API breaks:
 * Add a "stateKey" optional param to [MXRoom sendStateEventOfType:] and to [MXRestClient sendStateEventToRoom:].

Changes in Matrix iOS SDK in 0.9.1 (2017-08-08)
===============================================

Improvements:
 * MXRoomState: Improve algorithm to manage room members displaynames disambiguation.
 * MXRoomSummary: Add isDirect and directUserId properties, thanks to @morozkin (#342).
 * MXFileStore: New section with asynchronous API. asyncUsers and asyncRoomsSummaries methods are available, thanks to @morozkin (#342).
 
Bug fixes:
 * Mentions do not work for names that start or end with a non-word character like '[', ']', '@'...).
 * App crashed I don't know why, suspect memory issues / Crash in [MXRoomState copyWithZone:] (https://github.com/matrix-org/riot-ios-rageshakes#132).

API breaks:
 * Replace [MXRoomState stateEventWithType:] by [MXRoomState stateEventsWithType:].

Changes in Matrix iOS SDK in 0.9.0 (2017-08-01)
===============================================

Improvements:
 * Be more robust against JSON data sent by the homeserver.
 * MXRestClient: Add searchUsers method to search user from the homeserver user directory.
 * MXRestClient: Change API used to add email in order to check if the email (or msisdn) is already used (https://github.com/vector-im/riot-meta#85).
 * App Extension support: wrap access to UIApplication shared instance
 * MXSession: Pause could not be delayed if no background mode handler has been set in the MXSDKOptions.
 * MXRoomState: do copy of membersNamesCache content in memberName rather than in copyWithZone.
 
 * SwiftMatrixSDK
 * Add swift refinements to MXSession event listeners, thanks to @aapierce0 (PR #327).
 * Update the access control for the identifier property on some swift enums, thanks to @aapierce0 (PR #330).
 * Add Swift refinements to MXRoom class, thanks to @aapierce0 (PR #335).
 * Add Swift refinements to MXRoomPowerLevels, thanks to @aapierce0 (PR #336).
 * Add swift refinements to MXRoomState, thanks to @aapierce0 (PR #338).
 
Bug fixes:
 * Getting notifications for unrelated messages (https://github.com/vector-im/riot-android/issues/1407).
 * Crypto: Fix crash when encountering a badly formatted olm message (https://github.commatrix-org/riot-ios-rageshakes#107).
 * MXSession: Missing a call to failure callback on unknown token, thanks to @aapierce0 (PR #331). 
 * Fixed an issue that would prevent attachments from being downloaded via SSL connections when using a custom CA ceritficate that was included in the bundle, thanks to @javierquevedo (PR #332).
 * Avatars do not display with account on a self-signed server (https://github.com/vector-im/riot-ios/issues/816).
 * MXRestClient: Escape userId in CS API requests.

Changes in Matrix iOS SDK in 0.8.2 (2017-06-30)
===============================================

Improvements:
 * MXFileStore: Improve performance by ~5% (PR #318).

Changes in Matrix iOS SDK in 0.8.1 (2017-06-23)
===============================================

Improvements:
 * MXFileStore: Improve performance by ~10% (PR #316).
 
Bug fixes:
 * VoIP: Fix outgoing call stays in "Call connecting..." whereas it is established (https://github.com/vector-im/riot-ios#1326).

Changes in Matrix iOS SDK in 0.8.0 (2017-06-16)
===============================================

Improvements:
 * The minimal iOS version is now 8.0, 10.10 for macOS.
 * Add read markers synchronisation across matrix clients.
 * Add MXRoomSummary, an object where room data (display name, last message, etc) is cached. It avoids to recompute it from the room state.
 * Bug report: add MXBugReportRestClient to talk to the bug report API.
 * VoIP: several improvements, thanks to @morozkin (PR #301, PR #304, PR #307).
 * Remove direct dependency to Google Analytics, thanks to @aapierce0 (PR #256).
 * Extract background mode handling outside of Matrix SDK, thanks to Samuel Gallet (PR #296).
 * MXHTTPOperation: add isCancelled property, thanks to @SteadyCoder (PR #274).
 * MXMediaManager: Consider a cache version based on the version defined by the application and the one defined at the SDK level.
 * MXRestClient: add forgetPasswordForEmail for password reseting, thanks to @morozkin (PR #277).
 * MXRestClient: add setPinnedCertificates to allow app to use custom certificate, thanks to Samuel Gallet (PR #302).
 * MXRestClient: Fix publicRoomsOnServer for the search parameter.
 * MXRestClient: Make publicRooms still use the old "GET" API if there is no params.
 * MXRestClient: Add thirdpartyProtocols to get the third party protocols that can be reached using this HS.
 * MXRoom: Expose the user identifier for whom this room is tagged as direct (if any).
 * MXSession: Handle the missed notifications count at session level.
 * MXCredentials: add homeServerName property.
 * Crypto: Rework device list tracking logic in to order to fix UISI (https://github.com/matrix-org/matrix-js-sdk/pull/425 & https://github.com/matrix-org/matrix-js-sdk/pull/431).
 
Bug fixes:
 * App crashes if there are more than one invited room.
 * MXSession: Take into account encrypted messages in unread counter.
 * [MXSession resetRoomsSummariesLastMessage] freezes the app (#292).
 * README: update dead links in "Push Notifications" section.
 
API breaks:
 * MXRestClient: Update publicRooms to support pagination and 3rd party networks

Changes in Matrix iOS SDK in 0.7.11 (2017-03-23)
===============================================

Improvements:
 * MXSDKOptions: Let the application define its own media cache version (see `mediaCacheAppVersion`).
 * MXMediaManager: Consider a cache version based on the version defined by the application and the one defined at the SDK level.

Changes in Matrix iOS SDK in 0.7.10 (2017-03-21)
===============================================

Bug fix:
 * Registration with email failed when the email address is validated on the mobile phone.

Changes in Matrix iOS SDK in 0.7.9 (2017-03-16)
===============================================

Improvements:
 * MXRestClient: Tell the server we support the msisdn flow login (with x_show_msisdn parameter).
 * MXRoomState: Make isEncrypted implementation more robust.
 * MXCrypto: add ensureEncryptionInRoom method.

Bug fixes:
 * MXCrypto: Fix a crash due to a signedness issue in the count of one-time keys to upload.
 * MXCall: In case of encrypted room, make sure that encryption is fully set up before answering (https://github.com/vector-im/riot-ios#1058)

Changes in Matrix iOS SDK in 0.7.8 (2017-03-07)
===============================================

Improvements:
 * Add a Swift API to most of SDK classes, thanks to @aapierce0 (PR #241).
 * MXEvent: Add sentError property
 * MXSession: add catchingUp flag in to order to indicate we are restarting the events stream ASAP, ie /sync with serverTimeout = 0
 * MXRestClient: Support phone number validation.
 * MXRestClient: Add API to remove 3rd party identifiers from user's information
 * Crypto: Upgrade OLMKit(2.2.2).
 * Crypto: Support of the devices list CS API. It should fix a lot of Unknown Inbound Session Ids.
 * Crypto: Warn on unknown devices: Generate an error when the user sends a message to a room where there is unknown devices.
 * Crypto: Support for blacklisting unverified devices, both per-room and globally.
 * Crypto: Upload one-time keys on /sync rather than a timer.
 * Crypto: Add [MXCrypto resetDeviceKeys] to clear devices keys. This should fix unexpected UISIs from our user.
 * MXMyUser: do not force store update in case of user profile change. Let the store be updated once at the end of the sync.

Bug fixes:
 * Corrupted room state: some joined rooms appear in Invites section (https://github.com/vector-im/riot-ios#1029).
 * MXRestClient: submit3PIDValidationToken: The invalid token was not correctly handled.
 * MXRestClient: Update HTTP retry policy (#245).
 * MXRestClient: Self-signed homeserver: Fix regression on media hosted by server with CA certificate.
 * Crypto: app may crash on clear cache because of the periodic uploadKeys (#234).
 * Crypto: Invalidate device lists when encryption is enabled in a room (https://github.com/vector-im/riot-web#2672).
 * Crypto: Sometimes some events are not decrypted when importing keys (#261).
 * Crypto: After importing keys, the newly decrypted msg have a forbidden icon (https://github.com/vector-im/riot-ios#1028).
 * Crypto: Tight loop of /keys/query requests (#264).

API breaks:
 * MXPublicRoom: numJoinedMembers is now a signed integer.
 * Rename [MXHTTPClient jitterTimeForRetry] into [MXHTTPClient timeForRetry:]

Changes in Matrix iOS SDK in 0.7.7 (2017-02-08)
===============================================

Improvements:
 * MXFileStore: Do not store the access token. There is no reason for that.
 * Improve disk usage: Do not use NSURLCache. The SDK does not need this cache. This may save hundreds of MB.
 * Add E2E keys export & import. This is managed by the new MXMegolmExportEncryption class.

Bug fixes:
 * Fix a few examples in the README file, thanks to @aapierce0 (PR #230).
 * Duplicated msg when going into room details (https://github.com/vector-im/riot-ios#970).
 * App crashes a few seconds after a successful login (https://github.com/vector-im/riot-ios#965).
 * Got stuck syncing forever (https://github.com/vector-im/riot-ios#1008).
 * Local echoes for typed messages stay (far) longer in grey (https://github.com/vector-im/riot-ios#1007).
 * MXRealmCryptoStore: Prevent storeSession & storeInboundGroupSession from storing duplicates (#227).
 * MXRealmCryptoStore: Force migration of the db to remove duplicate olm and megolm sessions (#227).
 
Changes in Matrix iOS SDK in 0.7.6 (2017-01-24)
===============================================

Improvements:
 * MXRestClient: Made apiPathPrefix fully relative (#213).
 * MXRestClient: Add contentPathPrefix property to customise path to content repository (#213).
 * MXRestClient: Support the bulk lookup API (/bulk_lookup) of the identity server.
 * MXEvent: Add isLocalEvent property.
 * Crypto store migration: The migration from MXFileCryptoStore to MXRealmCryptoStore have been improved to avoid user from relogging.

Bug fixes:
 * MXCrypto: App crash on "setObjectForKey: key cannot be nil"

API breaks:
 * MXDecryptingErrorUnkwnownInboundSessionIdCode has been renamed to MXDecryptingErrorUnknownInboundSessionIdCode.
 * MXDecryptingErrorUnkwnownInboundSessionIdReason has been renamed to MXDecryptingErrorUnknownInboundSessionIdReason.
 * kMXRoomLocalEventIdPrefix has been renamed to kMXEventLocalEventIdPrefix.

Changes in Matrix iOS SDK in 0.7.5 (2017-01-19)
===============================================

Improvements:
 * Matrix iOS SDK in now compatible with macOS, thanks to @aapierce0 (PR #218).
 * MXEvent.sentState: add MXEventSentStatePreparing state.
 * Google Analytics: Add an option to send some speed stats to GA (It is currently focused on app startup).
 
Bug fixes:
 * Resend now function doesn't work on canceled upload file (https://github.com/vector-im/riot-ios#890).
 * Riot is picking up my name within words and highlighting them (https://github.com/vector-im/riot-ios#893).
 * MXHTTPClient: Handle correctly the case where the homeserver url is a subdirectory (#213).
 * Failure to decrypt megolm event despite receiving the keys (https://github.com/vector-im/riot-ios#913).
 * Riot looks to me like I'm sending the same message twice (https://github.com/vector-im/riot-ios#894).

Changes in Matrix iOS SDK in 0.7.4 (2016-12-23)
===============================================

Improvements:
 * Crypto: all crypto processing is now done outside the main thread.
 * Crypto: keys are now stored in a realm db.
 * Crypto: variuos bug fixes and improvements including:
     * Retry decryption after receiving keys
     * Avoid a packetstorm of device queries on startup
     * Detect store corruption and send kMXSessionCryptoDidCorruptDataNotification
 * Move MXKMediaManager and MXKMediaLoader at SDK level.
 * MXEvent: Add sentState property (was previously in the kit).
 * MXEvent: There is now an encrypting state.
 * MXRoom now manages outgoing messages (was done at the kit level).
 
API breaks:
 * MXRoom:`sendMessageOfType` is deprecated. Replaced by sendMessageWithContent.

Changes in Matrix iOS SDK in 0.7.3 (2016-11-23)
===============================================

Improvements:
 * Crypto: Ignore reshares of known megolm sessions.
 
Bug fixes:
 * MXRestClient: Fix Delete Device API.
 
Changes in Matrix iOS SDK in 0.7.2 (2016-11-22)
===============================================

Improvements:
 * MXRestClient: Add API to get information about user's devices.
 
Bug fixes:
 * Cannot invite user with dash in their user id (vector-im/vector-ios#812).
 * Crypto: Mitigate replay attack #162.

Changes in Matrix iOS SDK in 0.7.1 (2016-11-18)
===============================================

Bug fixes:
* fix Signal detected: 11 at [MXRoomState memberName:] level.
* [Register flow] Register with a mail address fails (https://github.com/vector-im/vector-ios#799).

Changes in Matrix iOS SDK in 0.7.0 (2016-11-16)
===============================================

Improvements:
 * Support end-to-end encryption. It is experimental and may not be reliable. You should not yet trust it to secure data. File transfers are not yet encrypted. Devices will not yet be able to decrypt history from before they joined the room. Once encryption is enabled for a room it cannot be turned off again (for now). Encrypted messages will not be visible on clients that do not yet implement encryption.
 * MXSession: support `m.direct` type in `account_data` (#149). Required to convert existing rooms to/from DMs (https://github.com/vector-im/vector-ios#715).
 * MXRoom: Handle inbound invites to decide if they are DMs or not (https://github.com/vector-im/vector-ios#713).
 * MXSDKOptions: Create a "Build time options" section.
 
API improvements:
 * MXRestClient: Add registerWithLoginType and loginWithLoginType which do the job with new CS auth api for dummy and password flows.
 * MXRestClient: Support /logout API to invalidate an existing access token.
 * MXRestClient: Register/login: Fill the initial_device_display_name field with the device name by default.
 * MXRestClient: Support the `filter` parameter during a messages request (see `MXRoomEventFilter` object). The `contains_url` filter is now used for events search.
 * MXHTTPOperation: Add the `mutateTo` method to be able to cancel any current HTTP request in a requests chain.
 * MXSession/MXRestClient: Support `invite` array, `isDirect` flag and `preset` during the room creation. Required to tag explicitly the invite as DM or not DM (https://github.com/vector-im/vector-ios#714).
 * MXRoomState: Add the stateEventWithType getter method.
 * MXSession: Add `directJoinedRoomWithUserId` to get the first joined direct chat listed in account data for this user.
 * MXRoom: Add `setIsDirect` method to convert existing rooms to/from DMs (https://github.com/vector-im/vector-ios#715).
 * MXRoom: Add `eventDeviceInfo` to get the device information related to an encrypted event.
 * MXRoom: Add API to create a temporary message event. This temporary event is automatically defined as `encrypted` when the room is encrypted and the encryption is enabled.

API break:
 * MXRestClient: Remove `registerWithUser` and `loginWithUser` methods which worked only with old CS auth API.
 * MXSession: Remove `privateOneToOneRoomWithUserId:` and `privateOneToOneUsers` (the developer must use the `directRooms` property instead).

Changes in Matrix iOS SDK in 0.6.17 (2016-09-27)
================================================

Improvements:
 * Move MXRoom.acknowledgableEventTypes into MXSession (#141).
 * MXTools: Update the regex used to detect room alias (Support '#' character in alias name).

Bug fixes:
 * Invite a left user doesn't display his displayname (https://github.com/vector-im/vector-ios#646).
 * The room preview does not always display the right member info (https://github.com/vector-im/vector-ios#643).
 * App got stuck and permenantly spinning (https://github.com/vector-im/vector-ios#655).

Changes in Matrix iOS SDK in 0.6.16 (2016-09-15)
================================================

Bug fixes:
 * MXSession: In case of initialSync, mxsession.myUser.userId must be available before changing the state to MXSessionStateStoreDataReady (https://github.com/vector-im/vector-ios#623).

Changes in Matrix iOS SDK in 0.6.15 (2016-09-14)
================================================

Bug fixes:
 * MXFileStore: The stored receipts may not be totally loaded on cold start.
 * MXNotificationCenter: The conditions of override and underride rules are defined in an array.

Changes in Matrix iOS SDK in 0.6.14 (2016-09-08)
================================================

Improvements:
 * Allow MXSession to run the events stream in background for special cases
 * MXEvent: Add the m.room.encrypted type
 * MXSession: Expose the list of user ids for whom a 1:1 room exists (https://github.com/vector-im/vector-ios/issues/529).
 * MXStore: Save MXUsers in the store (https://github.com/vector-im/vector-ios/issues/406).
 * MXTools: Expose regex used to identify email address, user ids, room ids & and room aliases. Cache their regex objects to improve performance.
 * MXTools: Add [MXTools isMatrixEventIdentifier:].
 * MXTools: Add methods to create permalinks to room or event (https://github.com/vector-im/vector-ios/issues/547).
 
Bug fixes:
 * MXKRoomState.aliases: some addresses are missing  (https://github.com/vector-im/vector-ios/issues/528).
 * MXFileStore: Stop leaking background tasks, which kill the app after 180s of bg.
 * MXCall: Add a timeout for outgoing calls (https://github.com/vector-im/vector-ios/issues/577).
 * MXJingleCallStackCall: When screen is locked, rotating the screen landscape makes local video preview go upside down (https://github.com/vector-im/vector-ios/issues/519).

Changes in Matrix iOS SDK in 0.6.13 (2016-08-25)
================================================

Improvements:
 * Add conference call support.
 * Call: Update the libjingle lib to its latest version. That implied a major refactoring of MXJingleCallStack.
 * Repair MXFileStore in case of interrupted commit (https://github.com/vector-im/vector-ios/issues/376).
 * Speed up MXFileStore loading.
 * Allow MXFileStore to run when the app is backgrounded.
 * Change the MXStore API to be able to run several paginations in parallel.
 
API improvements:
 * Add MXEventsEnumerator to enumerate sets of events like those returned by the MXStore API.
 * MXRoomState: Added - (NSArray*)membersWithMembership:(MXMembership)membership.
 * MXSession & MXRestClient: Add createRoom with a parameters dictionary to manage all fields available in Matrix spec.
 * MXCall: Add cameraPosition property to switch the camera.
 * MXMyUser: Allow nil callback blocks in setter methods.
 * SDK Tests: Add a test on [MXRestClient close].
 * SDK Tests: Add a test on [MXFileStore diskUsage].
 
Bug fixes:
 * Redacting membership events should immediately reset the displayname & avatar of room members (https://github.com/vector-im/vector-ios/issues/443).
 * Profile changes shouldn't reorder the room list (https://github.com/vector-im/vector-ios/issues/494).
 * When the last message is redacted, [MXKRecentCellData update] makes paginations loops (https://github.com/vector-im/vector-ios/issues/520).
 * MXSession: Do not send kMXSessionIgnoredUsersDidChangeNotification when the session loads the data from the store (https://github.com/vector-im/vector-ios/issues/491).
 * MXHTTPClient: Fix crash: "Task created in a session that has been invalidated" (https://github.com/vector-im/vector-ios/issues/490).
 * Call: the remote and local video are not scaled to fill the video container (https://github.com/vector-im/vector-ios/issues/537).

API Breaks:
 * Rename "kMXRoomSyncWithLimitedTimelineNotification" with "kMXRoomDidFlushMessagesNotification"
 * MXRoom: Make placeCall: asynchronous.
 * MXFileStore: Replace 'diskUsage' property by an async non blocking method: [self diskUsageWithBlock:].
 * MXStore: Replace [MXStore resetPaginationOfRoom:], [MXStore paginateRoom:numMessages:] and [MXStore remainingMessagesForPaginationInRoom:] methods by [MXStore messagesEnumeratorForRoom:]

Changes in Matrix iOS SDK in 0.6.12 (2016-08-01)
================================================

Improvements:
 * MXCallManager: Better handle call invites when the app resumes.
 * MXCall: Improve the sending of local ICE candidates to avoid HTTP 429(Too Many Requests) response
 * MXCall: Added the audioToSpeaker property to choose between the main and the ear speaker.
 * MXRoomState: Added the joinedMembers property.
 * MXLogger: Added the isMainThread information in crash logs.
 
Bug fixes:
 * MXJingleCallStackCall: Added sanity check on creation of RTCICEServer objects as crashes have been reported.

Changes in Matrix iOS SDK in 0.6.11 (2016-07-26)
================================================

Improvements:
 * MXCall: Added audioMuted and videoMuted properties.
 * Call: the SDK is now able to send local ICE candidates.
 * Integration of libjingle/PeerConnection call stack (see MXJingleCall).
 
Bug fixes:
 * MXCallManager: Do not show the call screen when the call is initiated by the same user but from another device.
 * MXCallManager: Hide the call screen when the user answers an incoming call from another device.

Breaks:
 * MXCallStackCall: two new properties (audioMuted and videoMuted) and one new delegate method (onICECandidateWithSdpMid).

Changes in Matrix iOS SDK in 0.6.10 (2016-07-15)
================================================

Improvements:
 * MXRestClient: Add API to add/remove a room alias.
 * MXRestClient: Add API to set the room canonical alias.
 * Update AFNetworking: Move to 3.1.0 version.
 * SDK Tests: Update and improve tests. 

Bug fixes:
 * MXRoom: Read receipts can now be posted on room history visibility or guest access change.
 
Breaks:
 * MXRestClient: uploadContent signature has been changed.

Changes in Matrix iOS SDK in 0.6.9 (2016-07-01)
===============================================

Improvements:
 * MXPeekingRoom (New): This class allows to get data from a room the user has not joined yet.
 * MXRoom: Add API to change room settings: history visibility, join rule, guest access, directory visibility.
 * MXTools: Add isMatrixRoomAlias, isMatrixRoomIdentifier and isMatrixUserIdentifier methods.

Bug fixes:
 * MXRestClient: can't join rooms with utf-8 alias (https://github.com/vector-im/vector-ios/issues/374)
 * Push rules: strings comparisons are now case insensitive (https://github.com/vector-im/vector-ios/issues/410)
 
Breaks:
 * kMXRoomVisibility* consts have been renamed to kMXRoomDirectoryVisibility*
 * MXRoom: isPublic has been replaced by isJoinRulePublic
 
 
Changes in Matrix iOS SDK in 0.6.8 (2016-06-01)
===============================================

Improvements:
 * Push rules update: Listen to account_data to get push rules updates.
 * SDK Tests improvements: Prevent the test suite from breaking because one test fails.
 * MXRoomState: disambiguate the display name for the invited room member too.

Bug fixes:
 * Ignored users: kMXSessionIgnoredUsersDidChangeNotification was sometimes not sent.
 * Recents: All blank after upgrade.
 * Fixed implementation of userAccountData in MXMemoryStore and MXNoStore.
 * MXSession: Detect when the access token is no more valid.

Changes in Matrix iOS SDK in 0.6.7 (2016-05-04)
===============================================

Improvements:
 * Presence: Manage the currently_active parameter.
 * MXRestClient: Add API to reset the account password.
 * Ability to report abuse
 * Ability to ignore users

Changes in Matrix iOS SDK in 0.6.6 (2016-04-26)
===============================================

Improvements:
 * MXSession/MXRestClient: Add [self join:withSignUrl:] to join a room where the user has been invited by a 3PID invitation.
 * MXHTTPClient: Add an option to serialise input parameters as form data instead of JSON, which is still the default behavior.
 * MXRestClient: Update requestEmailValidation (set params in body, replace camelCase params keys by their underscore name, add the nextLink param).
 * MXRestClient: Add submitEmailValidationToken to validate an email.
 * MXFileStore: Improve storage and loading of read receipts.
 * MXTools: Add method to remove new line characters from NSString.

Bug fixes:
 * Cannot paginate to the origin of the room.
 * Store - Detect and remove corrupted room data.
 * The application icon badge number is wrong.

Changes in Matrix iOS SDK in 0.6.5 (2016-04-08)
===============================================

Improvements:
 * MXJSONModels: Registration Support - Define MXAunthenticationSession class. This class is used to store the server response on supported flows during the login or the registration.
 * MXRestClient: New email binding - validateEmail and bind3PID has been removed. add3PID and treePIDs has been added.
 * MXRestClient: Registration Support - Add API to check user id availability.
 * MXSession: Added roomWithAlias method.
 * MXTools: Add method to validate email address.

Bug fixes:
 * User profile: user settings may be modified during pagination in past timeline.
 * Fixed crash in [MXFileStore saveReceipts]. There was a race condition.
 * Cancel correctly pending operations.

Changes in Matrix iOS SDK in 0.6.4 (2016-03-17)
===============================================

Improvements:
 * MXRoom: Update unread events handling (ignore m.room.member events and redacted events).
 * MXRoomPowerLevels: power level values are signed.
 * MXStore: Retrieve the receipt for a user in a room.

Bug fixes:
 * App crashes on redacted event handling.
 * The account data changes are ignored (Favorites section is not refreshed correctly).

Changes in Matrix iOS SDK in 0.6.3 (2016-03-07)
===============================================

Improvements:
 * Moving to r0 API: Replace calls to v1 and v2_alpha apis by r0, which is configurable via MXRestClient.apiPathPrefix.
 * MXEventContext: Add C-S API to handle event context.
 * MXEventTimeline: Created MXEventTimeline to manage a list of continuous events. MXRoom has now a liveTimeline property that manages live events and state of the room. MXEventTimeline is able to manage live events and events that will come from the event context API.
 * MXEventDirection* has been renamed to MXTimelineDirection*.
 * MXEventTimeline: Support backward/forward pagination around a past event.
 * MXRestClient: the messagesForRoom method has been updated to conform r0 C-S API. The "to" parameter has been replaced by the "direction" parameter.
 * MXRoom: Replace the inaccurate 'unreadEvents' array with a boolean flag 'hasUnreadEvents'.
 * MXRoom: Add 'notificationCount' and 'highlightCount' based on the notificationCount field in /sync response.
 * SDK Tests: Update and fix tests.

Bug fixes:
 * Support email login.
 * Room ordering: a tagged room with no order value must have higher priority than the tagged rooms with order value.
 * SYIOS-208: [MXSession startWithMessagesLimit]: if defined, the limit argument is now passed to /sync request.
 * SYIOS-207: Removed MXEventDirectionSync which became useless.

Changes in Matrix iOS SDK in 0.6.2 (2016-02-09)
===============================================

Improvements:
 * MXRoom: Add an argument to limit the pagination to the messages from the store.
 * MXRoom: Support email invitation.

Bug fixes:
 * App crashes on resume if a pause is pending.
 * Account creation: reCaptcha is missing in registration fallback.

Changes in Matrix iOS SDK in 0.6.1 (2016-01-29)
===============================================

Improvements:
 * Remove Mantle dependency (to improve performances).
 * JSON validation: Log errors (break only in DEBUG build).

Bug fixes:
 * SYIOS-203: iOS crashes on non numeric power levels.
 * MXRestClient: set APNS pusher failed on invalid params.

Changes in Matrix iOS SDK in 0.6.0 (2016-01-22)
===============================================

Improvements:
 * MXSession: Switch on server sync v2 (Left room are handled but not stored for the moment).
 * MXSession: Support room tags.
 * MXSession: Improve the invitations management.
 * MXRestClient: Support server change password API.
 * MXRestClient: Support server search API.
 * MXSDKOption: Add new option: enable/disable identicon use at SDK level.
 * MXRoom: Add room comparator based on originServerTs value.
 * MXRoom: Exclude the current user from the receipts list retrieved for an event.
 * MXEvent: Add properties for receipt events to retrieve event ids or sender ids.
 * MXEvent: Report server API changes (handle ‘unsigned’ dictionary).
 * MXPublicRoom: Support worldReadable, guestCanJoin and avatarURL fields.
 * MXHTTPClient: Accept path that already contains url parameters.
 * MXJSONModels: Improve performance (Limit Mantle use).
 * MXStore: Store the partial text message typed by the user.
 * MXStore: Store messages which are being sent (unsent messages are then stored).

Bug fixes:
 * MXRoom: Fix detection of the end of the back pagination. End of pagination is now detected when returned chunk is empty and both tokens (start/end) are equal.
 * MXRoom: Generate a read receipt for the sender of an incoming message.
 * MXRoom: Improve offline experience - Disable retry option on pagination requests when data are available from store. The caller is then able to handle messages from store without delay.
 * MXSession: Load push rules from server before loading store data in order to highlight the bing events.

Changes in Matrix iOS SDK in 0.5.7 (2015-11-30)
===============================================

Improvements:
 * MXStore: Added a new optimised eventExistsWithEventId: method.
 * MXRoomState: Room state optimisation.
 * MXEvent: Events handling optimisation.
 * MXSession: Add Room tag support.
 * MXRoom: Add Room avatar support.

Bug fixes:
 * SYIOS-176: Single word highlighting failed.
 * SYIOS-140: Add support for canonical alias.
 * SYIOS-184: We don't seem to have any way to invite users into a room.
 * MXNotificationCenter: NSMutableArray was mutated while being enumerated.
 * App crashes at launch after an event redaction.

Changes in Matrix iOS SDK in 0.5.6 (2015-11-13)
===============================================

Bug fixes:
 * MXRoomState: All room members have the same power level when a new state event is received.
 * MXRoom: The backward room state is corrupted (former display name and avatar are missing).

Changes in Matrix iOS SDK in 0.5.5 (2015-11-12)
===============================================

Improvements:
 * MXMemoryStore: Improved [MXStore unreadEvents] implementation. It is 7-8 times quicker now.
 * MXRoomState: Added cache to [MXRoomState memberName:] to optimise it.
 * MXUser/MXRoomMember: Ignore non mxc avatar url.

Changes in Matrix iOS SDK in 0.5.4 (2015-11-06)
===============================================

Improvements:
 * Use autoreleasepool to reduce memory usage.
 * MXHTTPClient: Handle unrecognized certificate during authentication challenge from a server.
 * MXHTTPClient: Fixed memory leaks of MXHTTPOperation objects.
 * MXJSONModel: Optimise memory usage during model creation.
 * MXRestClient: Add read receipts management (sent with API v2, received with API v1).
 * MXRestClient: Define login fallback (server auth v1).
 * MXRoom: Clone room state only in case of change.
 * MXNotificationCenter: Reduce computation time during events handling.

Bug fixes:
 * MXRoom: Room invitation failed.
 * MXSession: No history is displayed in new joined room.
 * SYIOS-164: Duplicated events on bad networks
 * SYIOS-165: Join an empty room on one device is not properly dispatched to the other devices.
 * SYIOS-169: Improve MXEvent conversion.
 * SYIOS-170: Public Room: room history is wrong when user joins for the second time.

Changes in Matrix iOS SDK in 0.5.3 (2015-09-14)
===============================================

Improvements:
 * Clean the store before the initial room syncing.
 * MXHTTPClient: improve http client logs.

Bug fixes:
 * MXRoom: App crashes on invite room during initial sync.

Changes in Matrix iOS SDK in 0.5.2 (2015-08-13)
===============================================

Improvements:
 * Fixed code that made Cocoapods 0.38.2 unhappy.

Changes in Matrix iOS SDK in 0.5.1 (2015-08-10)
===============================================

Improvements:
 * MXRestClient: Add API to create push rules.
 * MXRestClient: Add API to update global notification settings.

Changes in Matrix iOS SDK in 0.5.0 (2015-07-10)
===============================================

Improvements:
 * MXSession: Optimise one-to-one rooms handling (keep update a list of these
   rooms).
 * MXRoomState: Optimise power level computation during room members handling.
 * MXEvent: Define "m.file" as new message type.
 * MXRestClient: Notification Pushers - Support remote notifications for
   multiple account on the same device.
 * MXRestClient: Add filename in url parameters in case of file upload
   (image/video).
 
Bug fixes:
 * MXFileStore: SYIOS-121 - Support multi-account.
 * MXFileStore: Fixed store that does not work on some devices. The reason was
   the store was not able to create the file hierarchy.
 * MXSession: Post MXSessionStateInitialised state change at the end of
   initialisation.
 * MXSession: Post state change event only in case of actual change.
 * Bug Fix: App crashes on attachment notifications.
 * Bug Fix: App crash - The session may be closed before the end of store
   opening.
 * Bug Fix: Blank room - Handle correctly end of pagination error during back
   pagination (see SYN-162 - Bogus pagination token when the beginning of the
   room history is reached).


Changes in Matrix iOS SDK in 0.4.0 (2015-04-23)
===============================================

-----
 SDK
-----
Improvements:
 * MXSession: Define a life cycle. The current value is stored in the `state`
   property. Its changes are notified via NSNotificationCenter
   (kMXSessionStateDidChangeNotification).
 * MXSession/MXRoom: return a MXHTTPOperation for all methods taht make HTTP
   requests to the Matrix Client-Server API so that the SDK client can cancel
   them.
 * MXSession: Added createRoom method
 * MXSession: Added notifications to indicate changes on room:
     - kMXSessionNewRoomNotification
     - kMXSessionInitialSyncedRoomNotification
     - kMXSessionWillLeaveRoomNotification
     - kMXSessionDidLeaveRoomNotification
 * MXNotificationCenter: Take into account the `highlight` tweek parameters in
   push rules.
 
Bug fixes:
 * Fixed pagination hole that happened when receiving live events between
   [MXRoom resetBackState] and [MXRoom paginateBackMessages].
 * MXStore: When reopened, the MXSession did reset all pagination token of all
   cached room.
 * MXFileStore: if pagination token was changed with no new messages, the new
   pagination token was not saved into the file cache.
 
-----------------
 Matrix Console
-----------------
Console source code has been moved into its own git repository:
https://github.com/matrix-org/matrix-ios-console.


Changes in Matrix iOS SDK in 0.3.2 (2015-03-27)
===============================================

-----
 SDK
-----
Improvements:
 * All requests (except typing notifications) are retried (SYIOS-32).
 * Added definitions for VOIP event types.
 * Updated AFNetworking version: 2.4.1 -> 2.5.2.
 
Bug fixes:
 * SYIOS-105 - Public rooms sometimes appear as 2-member rooms for some reason.
 
-----------------
 Matrix Console
-----------------
Improvements:
 * Settings - Invite user to use a webclient and hit Settings to configure
   global notification rules.
 * InApp notifications - Support tweak action for InApp notification.
 * Improved image rotation support over different Matrix clients.
 
Bug fixes:
 * SYIOS-107 - In-App notifications does not work since changes in push rules
   spec.
 * SYIOS-108 - I can't re-enter existing chats when tapping through contact
   details.
 * On iOS 8, the app does not prompt user to upload logs after app crash. Rage
   shake is not working too.
 * Typing notification - Do not loop anymore to send typing notif in case of
   failure.
 

Changes in Matrix iOS SDK in 0.3.1 (2015-03-03)
===============================================

-----
 SDK
-----
Improvements:
 * Improved push notifications documentation.
 * MXSession: Slightly randomise reconnection times by up to 3s to prevent all
   Matrix clients from retrying requests to the homeserver at the same time.
 * Improved logs
 
Bug fixes:
 * SYIOS-90 - iOS can receive & display messages multiple times when on bad
   connections
 
-----------------
 Matrix Console
-----------------
Improvements:
 * Fixed warnings with 64bits builds.
 * Room history: Improve scrolling handling when keyboard appears.
 * Contacts: Prompt user when local contacts tab is selected if constact sync
   is disabled.
 
Bug fixes:
 * Fix crash when switching rooms while the event stream is resuming.
 * SYIOS-69 - On Screen Keyboard can end up hiding the most recent messages in
   a room.
 * SYIOS-98 - Crash when attempting to attach image on iPad
 

Changes in Matrix iOS SDK in 0.3.0 (2015-02-23)
===============================================

-----
 SDK
-----
Breaks:
 * [MXSession initWithMatrixRestClient: andStore: ] and the onStoreDataReady
   argument in [MXSession start:] has been removed. The SDK client can now use
   the asynchronous [MXSession setStore:] method to define a store and getting
   notified when the SDK can read cached data from it. (SYIOS-62)
 * MXStore implementations must now implement [MXStore openWithCredentials].
 * All MXRestClient methods now return MXHTTPOperation objects.
 
Improvements:
 * Created the MXSession.notificationCenter component: it indicates when an
   event must be notified to the user according to user's push rules settings.
 * MXFileStore: Improved loading performance by 8x.
 * Added an option (MXSession.loadPresenceBeforeCompletingSessionStart) to
   refresh presence data in background when starting a session.
 * Created MXLogger to redirect NSLog to file and to log crashes or uncaught
   exception.
 * MXRestClient: Added [MXRestClient registerFallback].
 * Logs: Make all NSLog calls follows the same format.
 
Features:
 * SYIOS-40 - Any HTTP request can fail due to rate-limiting on the server, and
   need to be retried.
 * SYIOS-81 - Ability to send messages in the background.
 
Bug fixes:
 * SYIOS-67 - We should synthesise identicons for users with no avatar.
 * MXSession: Fixed crash when closing the MXSession before the end of initial
   Sync.
 
-----------------
 Matrix Console
-----------------
Improvements:
 * Improve offline mode: remove loading wheel when network is unreachable and
   color in red the navigation bar when the app is offline.
 * Settings: Add identity server url in Configuration section.
 * Application starts quicker on cold start.
 * Home: Improve text inputs completion.
 * Settings: Rename “Hide redacted information” option to “Hide redactions”,
   and enable this option by default.
 * Settings: Rename the tab as “Settings” rather than “More”.
 * Recents: Adjust fonts size for Room name and last messages.

Features:
 * Added registration. It is implemented by a webview that opens the
   registration fallback page.
 * SYIOS-75 - Tapping on APNS needs to take you to the right room.
 * Manage local notifications with MXSession.notificationCenter.
 * Recents: Set blue the background cell for room with unread bing message(s).
 * SYIOS-68 - Rageshake needs to include device info.
 * SYIOS-87 - Rageshake needs to report logs as well as screenshot 
 * When the app crashes, the user is invited to send the crash log at the next
   app startup.
 * Logs: Make all NSLog calls follows the same format.

Bug fixes:
 * On iPhone 6+ (landscape mode), keep open the selected room when user changes
   application tabs.
 * Settings: Restore correctly user's display name after cache clearing.
 * SYIOS-76 - The 'Send' button hit area is too small and easy to miss.
 * SYIOS-73 - Text area input font should match that used in bubbles.
 * SYIOS-71 - Current room should be highlighted in landscape mode
 * SYIOS-79 - Partial text input should be remembered per-room.
 * SYIOS-83 - When uploading an image, the bubble order jumps around.
 * SYIOS-80 - Errors when internet connection unavailable are way too intrusive.
 * SYIOS-88 - Rageshake needs to be less sensitive by x2 or so.
 * Room History: App freezes on members display for room with a high number of
   members (> 500).
 * Settings: Store the minimum cache size to prevent application freeze when
   user scrolls settings table.


Changes in Matrix iOS SDK in 0.2.2 (2015-02-05)
===============================================

-----
 SDK
-----
Improvements:
 * MXFileStore stores data on a separated thread to avoid blocking the UI
   thread.
 * MXRestClient: Callback blocks in all MXRestClient methods are now optional.
 * MXEvent: Cleaned up exposed properties and added a description for each of
   them.
 
Features:
 * Added API for registering for push notifications.
 * Added generic API methods to make any kind of registration or login flow.
 * Added Identity server API: lookup3pid, requestEmailValidation, validateEmail
   and bind3PID.
 * Management of event redaction: there is a new method in the SDK to redact an
   event and the SDK updates its data on redaction event.
 
Bug fixes:
 * SYIOS-5 - Expose registration API
 * SYIOS-44 - Credentials persist across logout
 * SYIOS-54 - Matrix Console app slightly freezes when receiving a message
 * SYIOS-59 - Infinite loop in case of back pagination on new created room
 * MXRoom: Fixed [MXRoom sendTextMessage]
 
-----------------
 Matrix Console
-----------------
Improvements:
 * When long pressing on a message, the app shows the JSON string of the Matrix
   event.
 * On this screen, the user can redact the event - if he has enough power level.
 * Use home server media repository facilities to use lower image size for
   thumbnails and avatars
 * Settings screen: show build version with the app version.
 * Settings screen: added an option to hide information related to redacted
   event.
 * Settings screen: added an option to enable reading of local phonebook. The
   country is required to internationalise phone numbers.

Features:
 * Push notifications.
 * Added a contacts screen that displays Matrix users the user had interactions
   with and contacts from the device phonebook.
 * Contacts from the device phonebook who have an email linked to a Matrix user
   id are automatically recognised.

Bug fixes:
 * SYIOS-53 - multilines text input that expands as you type mutiplines would
   be nice
 * SYIOS-45 - Need to check the thumbnail params requested by iOS
 * SYIOS-55 - High resolution avatars create memory pressure
 * SYIOS-57 - Back pagination does not work well for self chat
 * SYIOS-56 - add cache size handling in settings
 * SYIOS-60 - In a self chat, Console takes ages to paginate back even if
   messages are in cache
 * SYIOS-61 - Chat room : cannot scroll to bottom when keyboard is opened
   whereas the growing textview contains multi-lines text.
 * SYIOS-63 - calculate room names for 3+ memebers if no room name/alias
 * SYIOS-44 - Credentials persist across logout
 * SYIOS-64 - Chat room : unexpected blank lines are added into history when
   user types in growing textview
 * SYIOS-65 - IOS8 : in case of search in recents, keyboard is not dismisssed
   when user selects a room.
 * SYIOS-16 Add option in Console to join room thanks to its alias



Changes in Matrix iOS SDK in 0.2.1 (2015-01-14)
===============================================

-----
 SDK
-----
Improvements:
 * [MXSession startWithMessagesLimit] takes a new callback parameter to
   indicate when data has been loaded from the MXStore.
 
Features:
 * Added typing notification API.
 * MXRESTClient provides helpers to resolve Matrix Content URI ("mxc://...")
   and their thumbnail.
 
Bug fixes:
 * Fixed 1:1 room renaming
 * SYIOS-37 - When restarting Matrix Console from the cache, users presences
   are lost
 
-----------------
 Matrix Console
-----------------
Improvements:
 * UX improvements.
 * The app starts quicker thanks to data available in cache.
 * Added a count of unread messages in the recents view.
 * SYIOS-38 - UX improvement for updating avatar & display name in settings
 * SYIOS-41 - File uploads (and downloads) should be able to happen in
   parallel, with basic progress meters
 * SYIOS-25 - Console: display app version in settings
 * Code improvement: Media Manager refactoring

Features:
 * Typing notifications.
 * Show progress information for uploading and downloading media. There is a
   pie chart progress plus network stats.
 * Added pitch to zoom gesture on images
 * Added bing alert. Bing words can be defined in the settings screen.
 * SYIOS-28 - There is no way to view a user's mxid (or other profile info) on
   iOS
 
Bug fixes:
 * SYIOS-33 - Current dev shows lots of rooms with blank recents entries which
   crash on entry
 * SYIOS-42 - Avatar & displayname missing in the "More" tab
 * SYIOS-43 - Recents tab on an iPad mini always shows a room view
 * SYIOS-51 - spinner appears when backgrounding recents page
 * SYIOS-50 - When you post a multiline message, the bubble vertical spacing
   gets confused.
 
 
 
Changes in Matrix iOS SDK in 0.2.0 (2014-12-19)
===============================================

-----
 SDK
-----
Improvements:
 * The SDK is now available on CocoaPods ($ pod search MatrixSDK)
 * Updated [MXRestClient joinRoom] to support both room id and room alias.
 * SDK tests: Improved tests suite duration.
 * The SDK version is available with MatrixSDKVersion
 
Features:
 * Added MXFileStore, a MXStore implementation to store Matrix events
   permanently on the file system.
 * SYIOS-2 - MXRoom: add shortcut methods like inviteUser, postMessage…
 * SYIOS-3 - Add API to set the power level of an user.
 * SYIOS-7 - Add the ability to cancel [MXRoom paginateBackMessages].
 
Bug fixes:
 * SYIOS-10 - mxSession: myUser lost his displayName after joining a public
   room.
 * SYIOS-9 - SDK should ignore duplicated events sent by the home server.
 * SYIOS-8 - Reliable SDK version

-----------------
 Matrix Console
-----------------
Improvements:
 * UX improvements.
 * Cold start is quicker thanks to the permanent cache managed by MXFileStore.
 * Recents: improve last event description.

Features:
 * Use new Matrix content repository to generate thumbnails and store contents.
 * Room view: display and edit room topic.
 * Room view: support /join command (join room by its alias).
 * Room view: support /op and /deop commands (power level handling).
 * Post user’s presence (online, unavailable or offline).
 * Use MXMyUser object (defined by SDK) to manage user’s information.
 
Bug fixes:
 * SYIOS-18 - displaying keyboard has nasty animation artefacts.
 * SYIOS-17 - Fudge around flickering during echos.
 * SYIOS-15 - Entering a room should show all cached history from global
   initialsync.
 * SYIOS-21 - All login failures trigger 'Invalid username / password'
 * SYIOS-22 - Invalid username / password dialog box disappears automatically
   about half a second after appearing
 * SYIOS-23 - With multiple devices, a message sent from one device does not
   appear on another
 * Recents getting stuck after settings changes.



Changes in Matrix iOS SDK in 0.1.0 (2014-12-09)
===============================================

SDK:
 * Added MXStore, an abstract interface to store events received from the Home
   Server. It comes with two implementations: MXNoStore and MXMemoryStore:
     - MXNoStore does not store events. The SDK will always make requests to the
       HS. 
     - MXMemoryStore stores them in memory. The SDK will make requests to the HS
       only if required.
 * Added MXRoomPowerLevels, an helper class to get power levels values of a
   room.
 * Improved [MXStore resume]. It takes now a callback to inform the app when
   the SDK data is synchronised with the HS.

Matrix Console:
 * Use MXMemoryStore to reuse events already downloaded.
 * Use new [MXStore resume] method to show an activity indicator while resuming
   the SDK.
 * In the recents tab, highlight rooms with unread messages.
 * Added search inputs in public rooms and in recents.
 * Prevent user from doing actions (kick, ban, change topic, etc) when he does
   not have enough power level.
