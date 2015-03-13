Changes in Matrix iOS SDK in 0.3.1 (2015-03-03)
===============================================

-----
 SDK
-----
Improvements:
 * Improved push notifications documentation.
 * MXSession: Slightly randomise reconnection times by up to 3s to prevent all Matrix clients from retrying requests to the homeserver at the same time.
 * Improved logs
 
Bug fixes:
 * SYIOS-90 - iOS can receive & display messages multiple times when on bad connections
 
-----------------
 Matrix Console
-----------------
Improvements:
 * Fixed warnings with 64bits builds.
 * Room history: Improve scrolling handling when keyboard appears.
 * Contacts: Prompt user when local contacts tab is selected if constact sync is disabled.
 
Bug fixes:
 * Fix crash when switching rooms while the event stream is resuming.
 * SYIOS-69 - On Screen Keyboard can end up hiding the most recent messages in a room.
 * SYIOS-98 - Crash when attempting to attach image on iPad
 

Changes in Matrix iOS SDK in 0.3.0 (2015-02-23)
===============================================

-----
 SDK
-----
Breaks:
 * [MXSession initWithMatrixRestClient: andStore: ] and the onStoreDataReady argument in [MXSession start:] has been removed. The SDK client can now use the asynchronous [MXSession setStore:] method to define a store and getting notified when the SDK can read cached data from it. (SYIOS-62)
 * MXStore implementations must now implement [MXStore openWithCredentials].
 * All MXRestClient methods now return MXHTTPOperation objects.
 
Improvements:
 * Created the MXSession.notificationCenter component: it indicates when an event must be notified to the user according to user's push rules settings.
 * MXFileStore: Improved loading performance by 8x.
 * Added an option (MXSession.loadPresenceBeforeCompletingSessionStart) to refresh presence data in background when starting a session.
 * Created MXLogger to redirect NSLog to file and to log crashes or uncaught exception.
 * MXRestClient: Added [MXRestClient registerFallback].
 * Logs: Make all NSLog calls follows the same format.
 
Features:
 * SYIOS-40 - Any HTTP request can fail due to rate-limiting on the server, and need to be retried.
 * SYIOS-81 - Ability to send messages in the background.
 
Bug fixes:
 * SYIOS-67 - We should synthesise identicons for users with no avatar.
 * MXSession: Fixed crash when closing the MXSession before the end of initial Sync.
 
-----------------
 Matrix Console
-----------------
Improvements:
 * Improve offline mode: remove loading wheel when network is unreachable and color in red the navigation bar when the app is offline.
 * Settings: Add identity server url in Configuration section.
 * Application starts quicker on cold start.
 * Home: Improve text inputs completion.
 * Settings: Rename “Hide redacted information” option to “Hide redactions”, and enable this option by default.
 * Settings: Rename the tab as “Settings” rather than “More”.
 * Recents: Adjust fonts size for Room name and last messages.

Features:
 * Added registration. It is implemented by a webview that opens the registration fallback page.
 * SYIOS-75 - Tapping on APNS needs to take you to the right room.
 * Manage local notifications with MXSession.notificationCenter.
 * Recents: Set blue the background cell for room with unread bing message(s).
 * SYIOS-68 - Rageshake needs to include device info.
 * SYIOS-87 - Rageshake needs to report logs as well as screenshot 
 * When the app crashes, the user is invited to send the crash log at the next app startup.
 * Logs: Make all NSLog calls follows the same format.

Bug fixes:
 * On iPhone 6+ (landscape mode), keep open the selected room when user changes application tabs.
 * Settings: Restore correctly user's display name after cache clearing.
 * SYIOS-76 - The 'Send' button hit area is too small and easy to miss.
 * SYIOS-73 - Text area input font should match that used in bubbles.
 * SYIOS-71 - Current room should be highlighted in landscape mode
 * SYIOS-79 - Partial text input should be remembered per-room.
 * SYIOS-83 - When uploading an image, the bubble order jumps around.
 * SYIOS-80 - Errors when internet connection unavailable are way too intrusive.
 * SYIOS-88 - Rageshake needs to be less sensitive by x2 or so.
 * Room History: App freezes on members display for room with a high number of members (> 500).
 * Settings: Store the minimum cache size to prevent application freeze when user scrolls settings table.


Changes in Matrix iOS SDK in 0.2.2 (2015-02-05)
===============================================

-----
 SDK
-----
Improvements:
 * MXFileStore stores data on a separated thread to avoid blocking the UI thread.
 * MXRestClient: Callback blocks in all MXRestClient methods are now optional.
 * MXEvent: Cleaned up exposed properties and added a description for each of them.
 
Features:
 * Added API for registering for push notifications.
 * Added generic API methods to make any kind of registration or login flow.
 * Added Identity server API: lookup3pid, requestEmailValidation, validateEmail and bind3PID.
 * Management of event redaction: there is a new method in the SDK to redact an event and the SDK updates its data on redaction event.
 
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
 * When long pressing on a message, the app shows the JSON string of the Matrix event.
 * On this screen, the user can redact the event - if he has enough power level.
 * Use home server media repository facilities to use lower image size for thumbnails and avatars
 * Settings screen: show build version with the app version.
 * Settings screen: added an option to hide information related to redacted event.
 * Settings screen: added an option to enable reading of local phonebook. The country is required to internationalise phone numbers.

Features:
 * Push notifications.
 * Added a contacts screen that displays Matrix users the user had interactions with and contacts from the device phonebook.
 * Contacts from the device phonebook who have an email linked to a Matrix user id are automatically recognised.

Bug fixes:
 * SYIOS-53 - multilines text input that expands as you type mutiplines would be nice
 * SYIOS-45 - Need to check the thumbnail params requested by iOS
 * SYIOS-55 - High resolution avatars create memory pressure
 * SYIOS-57 - Back pagination does not work well for self chat
 * SYIOS-56 - add cache size handling in settings
 * SYIOS-60 - In a self chat, Console takes ages to paginate back even if messages are in cache
 * SYIOS-61 - Chat room : cannot scroll to bottom when keyboard is opened whereas the growing textview contains multi-lines text.
 * SYIOS-63 - calculate room names for 3+ memebers if no room name/alias
 * SYIOS-44 - Credentials persist across logout
 * SYIOS-64 - Chat room : unexpected blank lines are added into history when user types in growing textview
 * SYIOS-65 - IOS8 : in case of search in recents, keyboard is not dismisssed when user selects a room.
 * SYIOS-16 Add option in Console to join room thanks to its alias



Changes in Matrix iOS SDK in 0.2.1 (2015-01-14)
===============================================

-----
 SDK
-----
Improvements:
 * [MXSession startWithMessagesLimit] takes a new callback parameter to indicate when data has been loaded from the MXStore.
 
Features:
 * Added typing notification API.
 * MXRESTClient provides helpers to resolve Matrix Content URI ("mxc://...") and their thumbnail.
 
Bug fixes:
 * Fixed 1:1 room renaming
 * SYIOS-37 - When restarting Matrix Console from the cache, users presences are lost
 
-----------------
 Matrix Console
-----------------
Improvements:
 * UX improvements.
 * The app starts quicker thanks to data available in cache.
 * Added a count of unread messages in the recents view.
 * SYIOS-38 - UX improvement for updating avatar & display name in settings
 * SYIOS-41 - File uploads (and downloads) should be able to happen in parallel, with basic progress meters
 * SYIOS-25 - Console: display app version in settings
 * Code improvement: Media Manager refactoring

Features:
 * Typing notifications.
 * Show progress information for uploading and downloading media. There is a pie chart progress plus network stats.
 * Added pitch to zoom gesture on images
 * Added bing alert. Bing words can be defined in the settings screen.
 * SYIOS-28 - There is no way to view a user's mxid (or other profile info) on iOS
 
Bug fixes:
 * SYIOS-33 - Current dev shows lots of rooms with blank recents entries which crash on entry
 * SYIOS-42 - Avatar & displayname missing in the "More" tab
 * SYIOS-43 - Recents tab on an iPad mini always shows a room view
 * SYIOS-51 - spinner appears when backgrounding recents page
 * SYIOS-50 - When you post a multiline message, the bubble vertical spacing gets confused.
 
 
 
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
 * Added MXFileStore, a MXStore implementation to store Matrix events permanently on the file system.
 * SYIOS-2 - MXRoom: add shortcut methods like inviteUser, postMessage…
 * SYIOS-3 - Add API to set the power level of an user.
 * SYIOS-7 - Add the ability to cancel [MXRoom paginateBackMessages].
 
Bug fixes:
 * SYIOS-10 - mxSession: myUser lost his displayName after joining a public room.
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
 * SYIOS-15 - Entering a room should show all cached history from global initialsync.
 * SYIOS-21 - All login failures trigger 'Invalid username / password'
 * SYIOS-22 - Invalid username / password dialog box disappears automatically about half a second after appearing
 * SYIOS-23 - With multiple devices, a message sent from one device does not appear on another
 * Recents getting stuck after settings changes.



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
