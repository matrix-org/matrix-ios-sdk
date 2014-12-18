Changes in Matrix iOS SDK in 0.2.0 (2014-12-17)
===============================================

SDK:
 * BugFix SYIOS-10 - mxSession: myUser lost his displayName after joining a public room.
 * BugFix SYIOS-9 - SDK should ignore duplicated events sent by the home server.
 * BugFix SYIOS-8 - Reliable SDK version
 * Feature SYIOS-3 - Add API to set the power level of an user.
 * Feature SYIOS-2 - MXRoom: add shortcut methods like inviteUser, postMessage…
 * Feature SYIOS-7 - Add the ability to cancel [MXRoom paginateBackMessages].
 * Updated [MXRestClient joinRoom] to support both room id and room alias.
 * SDK tests: add/update tests, improve tests suite duration.

Matrix Console:
 * BugFix SYIOS-18 - displaying keyboard has nasty animation artefacts.
 * BugFix SYIOS-17 - Fudge around flickering during echos.
 * BugFix SYIOS-15 - Entering a room should show all cached history from global initialsync.
 * BugFix - “Recents getting stuck after settings changes”.
 * Post user’s presence (online, unavailable or offline).
 * Fix scrolling issues in Room screen.
 * Use MXMyUser object (defined by SDK) to manage user’s information.
 * Enlarge text width in Room screen.
 * Room view: display and edit room topic.
 * Room view: support /join command (join room by its alias).
 * Room view: support /op and /deop commands (power level handling).
 * Recents: improve last event description.

Changes in Matrix iOS SDK in 0.1.0 (2014-12-09)
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
