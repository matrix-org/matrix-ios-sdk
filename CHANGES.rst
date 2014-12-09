Changes in Matrix iOS SDK in 0.0.x (2014-12-09)
===============================================

SDK:
 * Added MXStore, an abstract interface to store events received from the Home Server. It comes with two implementations: MXNoStore and MXMemoryStore:
  * MXNoStore does not store events. The SDK will always make requests to the HS. 
  * MXMemoryStore stores them in memory. The SDK will make requests to the HS only if required.
 * Added MXRoomPowerLevels, an helper class to get power levels values of a room.
 * Improved [MXStore resume]. It takes now a callback to inform the app when the SDK data is synchronised with the HS.

Matrix Console:
 * Use MXMemoryStore to reuse events already downloaded.
 * Use new [MXStore resume] method to show an activity indicator while resuming the SDK.
 * In the recents tab, highlight rooms with unread messages.
 * Added search inputs in public rooms and in recents.
 * Prevent user from doing actions (kick, ban, change topic, etc) when he does not have enough power level.
