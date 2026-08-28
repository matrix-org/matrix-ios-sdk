// Copyright 2026
// SPDX-License-Identifier: Apache-2.0

#import <Foundation/Foundation.h>
#import "MXJSONModel.h"

NS_ASSUME_NONNULL_BEGIN

@class MXFilterJSONModel;

FOUNDATION_EXPORT NSNotificationName const MXSessionRoomListStateDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const MXSessionSlidingSyncRoomOrderDidChangeNotification;

typedef NS_ENUM(NSUInteger, MXSlidingSyncRoomListPhase) {
    MXSlidingSyncRoomListPhaseLoadingInitialWindow,
    MXSlidingSyncRoomListPhaseReady,
    MXSlidingSyncRoomListPhaseHydrating,
    MXSlidingSyncRoomListPhaseComplete,
};

/** Read-only progress of the server ordered room list. */
@interface MXSlidingSyncRoomListState : NSObject <NSCopying>
@property (nonatomic, readonly) MXSlidingSyncRoomListPhase phase;
@property (nonatomic, readonly, getter=isPartial) BOOL partial;
@property (nonatomic, readonly) NSUInteger loaded;
@property (nonatomic, readonly) NSUInteger total;
+ (instancetype)stateWithPhase:(MXSlidingSyncRoomListPhase)phase loaded:(NSUInteger)loaded total:(NSUInteger)total;
@end

/** Configuration for Tuwunel's Simplified Sliding Sync (MSC4186). */
@interface MXSlidingSyncConfiguration : NSObject <NSCopying>
@property (nonatomic) NSUInteger initialWindowSize;
@property (nonatomic) NSUInteger expandedWindowSize;
@property (nonatomic) NSUInteger backgroundBatchSize;
@property (nonatomic) NSUInteger timelineLimit;
@property (nonatomic) BOOL lazyLoadMembers;
@property (nonatomic) BOOL backgroundHydrationEnabled;
@property (nonatomic, copy) NSString *listName;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *requiredState;
@property (nonatomic, copy) NSDictionary<NSString *, id> *extensions;
/** Existing /sync filter used only if Sliding Sync is unavailable. */
@property (nonatomic, nullable, strong) MXFilterJSONModel *legacyFallbackSyncFilter;
+ (instancetype)defaultConfiguration;
- (NSDictionary<NSString *, id> *)requestDictionaryWithPosition:(nullable NSString *)position
                                                    connectionId:(NSString *)connectionId
                                                          ranges:(NSArray<NSArray<NSNumber *> *> *)ranges
                                               roomSubscriptions:(nullable NSArray<NSString *> *)roomIds
                                                         timeout:(NSUInteger)timeout
                                                     setPresence:(nullable NSString *)setPresence;
@end

@interface MXSlidingSyncListOperation : MXJSONModel
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, nullable, copy) NSArray<NSNumber *> *range;
@property (nonatomic, nullable, copy) NSArray<NSString *> *roomIds;
@property (nonatomic, nullable) NSNumber *index;
@property (nonatomic, nullable) NSNumber *fromIndex;
@property (nonatomic, nullable) NSNumber *toIndex;
@property (nonatomic, nullable, copy) NSString *roomId;
@end

@interface MXSlidingSyncList : MXJSONModel
@property (nonatomic) NSUInteger count;
@property (nonatomic, copy) NSArray<MXSlidingSyncListOperation *> *operations;
@end

/** Parsed response plus an adapter to the SDK's existing /sync pipeline. */
@interface MXSlidingSyncResponse : MXJSONModel
@property (nonatomic, copy) NSString *position;
@property (nonatomic, nullable, copy) NSString *transactionId;
@property (nonatomic, copy) NSDictionary<NSString *, MXSlidingSyncList *> *lists;
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *rooms;
@property (nonatomic, copy) NSDictionary<NSString *, id> *extensions;
- (id)legacySyncResponseForUserId:(NSString *)userId;
@end

NS_ASSUME_NONNULL_END
