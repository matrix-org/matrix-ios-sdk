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
