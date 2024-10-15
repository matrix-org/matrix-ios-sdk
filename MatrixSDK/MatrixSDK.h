/*
 Copyright 2014 OpenMarket Ltd
 Copyright 2017 Vector Creations Ltd
 Copyright 2019 The Matrix.org Foundation C.I.C

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

#import <Foundation/Foundation.h>

/**
 The Matrix iOS SDK version.
 */
FOUNDATION_EXPORT NSString *MatrixSDKVersion;

#import "MXRestClient.h"
#import "MXSession.h"
#import "MXError.h"
#import "MXWarnings.h"

#import "MXStore.h"
#import "MXNoStore.h"
#import "MXMemoryStore.h"
#import "MXFileStore.h"

#import "MXAllowedCertificates.h"

#import "MXRoomSummaryProtocol.h"
#import "MXRoomSummaryUpdater.h"

#import "MXEventsEnumeratorOnArray.h"
#import "MXEventsByTypesEnumeratorOnArray.h"

#import "MXLogger.h"
#import "MXLog.h"

#import "MXTools.h"
#import "MXThrottler.h"
#import "NSData+MatrixSDK.h"
#import "MXMatrixVersions.h"
#import "MXCapabilities.h"
#import "MXRoomVersionsCapability.h"
#import "MXBooleanCapability.h"

#import "MXSDKOptions.h"

#import "MXMediaManager.h"

#import "MXLRUCache.h"

#import "MXCallStack.h"

#import "MXCrypto.h"
#import "MXMegolmExportEncryption.h"
#import "MXEncryptedContentFile.h"
#import "MXEncryptedContentKey.h"
#import "MXKeyVerificationStart.h"
#import "MXKeyVerificationAccept.h"
#import "MXKeyVerificationCancel.h"
#import "MXKeyVerificationDone.h"
#import "MXKeyVerificationKey.h"
#import "MXKeyVerificationMac.h"
#import "MXKeyVerificationRequestByDMJSONModel.h"
#import "MXSASKeyVerificationStart.h"
#import "MXQRCodeKeyVerificationStart.h"
#import "MXCurve25519BackupAuthData.h"
#import "MXAes256BackupAuthData.h"
#import "MXKeyBackupPassword.h"

#import "MXAes.h"

#import "MXQRCodeDataCodable.h"
#import "MXQRCodeDataBuilder.h"
#import "MXQRCodeDataCoder.h"
#import "MXQRCodeData.h"
#import "MXVerifyingAnotherUserQRCodeData.h"
#import "MXSelfVerifyingMasterKeyTrustedQRCodeData.h"
#import "MXSelfVerifyingMasterKeyNotTrustedQRCodeData.h"

#import "MXBugReportRestClient.h"

#import "MXCallKitAdapter.h"
#import "MXCallKitConfiguration.h"
#import "MXCallAudioSessionConfigurator.h"
#import "MXCallStackCall.h"

#import "MXGroup.h"

#import "MXServerNotices.h"

#import "MXAutoDiscovery.h"
#import "MXServiceTerms.h"

#import "MXEventUnsignedData.h"
#import "MXEventRelations.h"
#import "MXEventAnnotationChunk.h"
#import "MXEventAnnotation.h"
#import "MXEventReferenceChunk.h"
#import "MXEventReplace.h"
#import "MXInReplyTo.h"
#import "MXEventRelationThread.h"
#import "MXEventContentLocation.h"

#import "MXReplyEventParser.h"

#import "MXEventScan.h"
#import "MXMediaScan.h"

#import "MXBase64Tools.h"
#import "MXBaseProfiler.h"

#import "MXCallInviteEventContent.h"
#import "MXCallAnswerEventContent.h"
#import "MXCallSelectAnswerEventContent.h"
#import "MXCallCandidatesEventContent.h"
#import "MXCallRejectEventContent.h"
#import "MXCallNegotiateEventContent.h"
#import "MXCallReplacesEventContent.h"
#import "MXCallAssertedIdentityEventContent.h"
#import "MXUserModel.h"
#import "MXCallCapabilitiesModel.h"
#import "MXAssertedIdentityModel.h"

#import "MXThirdPartyProtocolInstance.h"
#import "MXThirdPartyProtocol.h"
#import "MXThirdpartyProtocolsResponse.h"
#import "MXThirdPartyUserInstance.h"
#import "MXThirdPartyUsersResponse.h"

#import "MXLoginSSOFlow.h"

#import "MXKeyProvider.h"
#import "MXAesKeyData.h"
#import "MXRawDataKey.h"

#import "MXSpaceChildContent.h"
#import "MXRoomLastMessage.h"
#import "MXUIKitBackgroundTask.h"
#import "MXUIKitBackgroundModeHandler.h"
#import "MXRoomAccountDataUpdater.h"
#import "MXPushGatewayRestClient.h"
#import "MXEncryptedAttachments.h"
#import "MXLoginSSOIdentityProviderBrand.h"
#import "MXDecryptionResult.h"

//  Bridging to Swift
#import "MXCryptoConstants.h"
#import "MXEventDecryptionResult.h"
#import "MXPushRuleEventMatchConditionChecker.h"
#import "MXPushRuleDisplayNameCondtionChecker.h"
#import "MXPushRuleRoomMemberCountConditionChecker.h"
#import "MXPushRuleSenderNotificationPermissionConditionChecker.h"
#import "MXCachedSyncResponse.h"
#import "MXSharedHistoryKeyService.h"
#import "MXRoomKeyEventContent.h"
#import "MXForwardedRoomKeyEventContent.h"
#import "MXKeyBackupEngine.h"
#import "MXCryptoTools.h"
#import "MXRecoveryKey.h"
#import "MXSecretShareSend.h"
#import "MXCryptoSecretStore.h"
#import "MXCryptoVersion.h"

//  Sync response models
#import "MXSyncResponse.h"
#import "MXPresenceSyncResponse.h"
#import "MXToDeviceSyncResponse.h"
#import "MXDeviceListResponse.h"
#import "MXRoomsSyncResponse.h"
#import "MXRoomSync.h"
#import "MXRoomSyncState.h"
#import "MXRoomSyncTimeline.h"
#import "MXRoomSyncEphemeral.h"
#import "MXRoomSyncAccountData.h"
#import "MXRoomSyncUnreadNotifications.h"
#import "MXRoomSyncSummary.h"
#import "MXInvitedRoomSync.h"
#import "MXRoomInviteState.h"
#import "MXGroupsSyncResponse.h"
#import "MXInvitedGroupSync.h"
#import "MXGroupSyncProfile.h"
#import "MXBeaconInfo.h"
#import "MXBeacon.h"
#import "MXEventAssetType.h"
#import "MXDevice.h"

