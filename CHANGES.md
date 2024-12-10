## Changes in 0.27.17 (2024-12-10)

No significant changes.


## Changes in 0.27.16 (2024-11-12)

No significant changes.


## Changes in 0.27.15 (2024-10-15)

No significant changes.


## Changes in 0.27.14 (2024-09-17)

No significant changes.


## Changes in 0.27.13 (2024-08-20)

🙌 Improvements

- Add UTC timestamps to console log lines. ([#7472](https://github.com/vector-im/element-ios/issues/7472))

📄 Documentation

- Drop the requirement for "real" or "legally identifiable" name in order to contribute, in line with updated Foundation policy. ([#1875](https://github.com/matrix-org/matrix-ios-sdk/pull/1875))


## Changes in 0.27.12 (2024-07-23)

🙌 Improvements

- Expose MXRroomPowerLevels Swift wrappers to Element ([#1869](https://github.com/matrix-org/matrix-ios-sdk/pull/1869))

🐛 Bugfixes

- Fix CallKit audio session late init in VoIP call. ([#1866](https://github.com/matrix-org/matrix-ios-sdk/pull/1866))


## Changes in 0.27.11 (2024-06-18)

No significant changes.


## Changes in 0.27.10 (2024-06-17)

No significant changes.


## Changes in 0.27.9 (2024-06-13)

No significant changes.


## Changes in 0.27.8 (2024-05-29)

🙌 Improvements

- When sorting room list alphabetically, sort it case-insensitive. ([#1851](https://github.com/matrix-org/matrix-ios-sdk/pull/1851))
- Crypto: Update crypto SDK to 0.4.1 ([#1853](https://github.com/matrix-org/matrix-ios-sdk/pull/1853))


## Changes in 0.27.7 (2024-05-01)

No significant changes.


## Changes in 0.27.6 (2024-02-07)

No significant changes.


## Changes in 0.27.5 (2024-01-09)

🐛 Bugfixes

- Update regex for email address to be aligned email format in RFC 5322 ([#1826](https://github.com/matrix-org/matrix-ios-sdk/pull/1826))

🧱 Build

- Update CocoaPods and other gems. ([#1835](https://github.com/matrix-org/matrix-ios-sdk/pull/1835))


## Changes in 0.27.4 (2023-11-28)

🐛 Bugfixes

- Fix unhandled callback when the session is nil. ([#1833](https://github.com/matrix-org/matrix-ios-sdk/pull/1833))


## Changes in 0.27.3 (2023-10-04)

🐛 Bugfixes

- Prevent crash when sending file with unrecognised file extension (no associated mime type) (mimetype)

🧱 Build

- Update Cocoapods to 1.13.0. ([#1820](https://github.com/matrix-org/matrix-ios-sdk/pull/1820))


## Changes in 0.27.2 (2023-09-12)

🐛 Bugfixes

- Fix | QR code verification failing due to incorrect encoding padding ([#1816](https://github.com/vector-im/element-ios/issues/1816))


## Changes in 0.27.1 (2023-08-29)

✨ Features

- Delegate OIDC compatibility flag added. ([#1811](https://github.com/matrix-org/matrix-ios-sdk/pull/1811))
- Added the authentication property to the well known. ([#1812](https://github.com/matrix-org/matrix-ios-sdk/pull/1812))
- Function that allows to generate from the well known authentication, a logout mas URL given the device ID. ([#1813](https://github.com/matrix-org/matrix-ios-sdk/pull/1813))

🐛 Bugfixes

- Fixes power level events force unwrap crash ([#1809](https://github.com/matrix-org/matrix-ios-sdk/pull/1809))
- Prevent keyed archiver encoding crashes when writing read receipts to the file store ([#1810](https://github.com/vector-im/element-ios/issues/1810))
- Fix incoming push notifications not triggering sounds ([#7636](https://github.com/vector-im/element-ios/issues/7636))


## Changes in 0.27.0 (2023-08-15)

✨ Features

- Add support for device hydration through the Crypto SDK (uses MSC3814) ([#1807](https://github.com/matrix-org/matrix-ios-sdk/pull/1807))

🐛 Bugfixes

- Fix parsing logic for legacy location events ([#1801](https://github.com/matrix-org/matrix-ios-sdk/pull/1801))

⚠️ API Changes

- Remove MXDehydrationService and old client methods. ([#1807](https://github.com/matrix-org/matrix-ios-sdk/pull/1807))


## Changes in 0.26.12 (2023-06-21)

🐛 Bugfixes

- Ignore push rules with unknown condition kinds ([#7601](https://github.com/vector-im/element-ios/issues/7601))


## Changes in 0.26.11 (2023-06-13)

🙌 Improvements

- MSC3912 implementation: the stable property with_relations has been renamed with_rel_types ([#7563](https://github.com/vector-im/element-ios/issues/7563))
- Updated Jitsi meet sdk to 8.1.2-lite. ([#7565](https://github.com/vector-im/element-ios/issues/7565))
- MSC3987 implementation: the 'dont_notify' action for a push_rule is now deprecated and replaced by an empty action list. ([#7576](https://github.com/vector-im/element-ios/issues/7576))

🐛 Bugfixes

- Fixes a bug where an unhelpful message is shown rather than the threads empty state. ([#7551](https://github.com/vector-im/element-ios/issues/7551))


## Changes in 0.26.10 (2023-05-16)

🙌 Improvements

- Crypto: Enable Crypto SDK by default ([#1770](https://github.com/matrix-org/matrix-ios-sdk/pull/1770))
- Crypto: Deprecate MXLegacyCrypto ([#1772](https://github.com/matrix-org/matrix-ios-sdk/pull/1772))

🐛 Bugfixes

- Poll: Refreshing the poll when receiving pollEnd can break the chronological order in the store. ([#1776](https://github.com/matrix-org/matrix-ios-sdk/pull/1776))
- Fix breadcrumb list not updating when leaving a room. Contributed by @JanNikGra. ([#1777](https://github.com/vector-im/element-ios/issues/1777))


## Changes in 0.26.9 (2023-04-18)

🐛 Bugfixes

- Cross-signing: Setup cross-signing with empty auth session ([#1774](https://github.com/matrix-org/matrix-ios-sdk/pull/1774))


## Changes in 0.26.8 (2023-04-18)

🙌 Improvements

- Crypto: Update Crypto SDK ([#1767](https://github.com/matrix-org/matrix-ios-sdk/pull/1767))
- Cross-signing: Ensure device signed after restoring cross-signing keys ([#1768](https://github.com/matrix-org/matrix-ios-sdk/pull/1768))
- Crypto: Remove legacy crypto store ([#1769](https://github.com/matrix-org/matrix-ios-sdk/pull/1769))


## Changes in 0.26.7 (2023-04-12)

🙌 Improvements

- Crypto: Upgrade Crypto SDK ([#1765](https://github.com/matrix-org/matrix-ios-sdk/pull/1765))

🐛 Bugfixes

- Crypto: Delete data for mismatched accounts ([#1763](https://github.com/matrix-org/matrix-ios-sdk/pull/1763))


## Changes in 0.26.6 (2023-04-04)

🙌 Improvements

- Bugfix: Ensure related event nullability ([#1746](https://github.com/matrix-org/matrix-ios-sdk/pull/1746))
- Add constants for mention room power levels and check decrypted event content for @room mentions. ([#1750](https://github.com/matrix-org/matrix-ios-sdk/pull/1750))
- Crypto: Display correct SDK version ([#7457](https://github.com/vector-im/element-ios/issues/7457))

🐛 Bugfixes

- Fix invitations count in all chats list. ([#6871](https://github.com/vector-im/element-ios/issues/6871))

⚠️ API Changes

- Crypto: Add event decryption decoration instead of untrusted property ([#1743](https://github.com/matrix-org/matrix-ios-sdk/pull/1743))

🧱 Build

- Upgrade JitsiMeetSDK to 7.0.1-lite. ([#1754](https://github.com/matrix-org/matrix-ios-sdk/pull/1754))


## Changes in 0.26.5 (2023-03-28)

🙌 Improvements

- Crypto: Upgrade verification if necessary ([#1751](https://github.com/matrix-org/matrix-ios-sdk/pull/1751))


## Changes in 0.26.4 (2023-03-22)

🐛 Bugfixes

- Crypto: Do not show current session as unverified ([#7446](https://github.com/vector-im/element-ios/issues/7446))


## Changes in 0.26.3 (2023-03-22)

No significant changes.


## Changes in 0.26.2 (2023-03-21)

🙌 Improvements

- Crypto: Always update tracked users when sharing keys ([#1733](https://github.com/matrix-org/matrix-ios-sdk/pull/1733))
- CryptoV2: Fully deprecate MXCryptoStore ([#1735](https://github.com/matrix-org/matrix-ios-sdk/pull/1735))
- Make CallKit maximumCallGroups configurable. ([#1738](https://github.com/matrix-org/matrix-ios-sdk/pull/1738))
- Crypto: Simplify user verification state ([#1740](https://github.com/matrix-org/matrix-ios-sdk/pull/1740))
- Rageshakes: Identify crypto module ([#1742](https://github.com/matrix-org/matrix-ios-sdk/pull/1742))
- Session: Improved session startup progress ([#7417](https://github.com/vector-im/element-ios/issues/7417))

🐛 Bugfixes

- MXCallManager: Make call transfer requests sequential. ([#1739](https://github.com/matrix-org/matrix-ios-sdk/pull/1739))


## Changes in 0.26.1 (2023-03-13)

🐛 Bugfixes

- All chats: revert "Unread" rooms filter behaviour. ([#1736](https://github.com/matrix-org/matrix-ios-sdk/pull/1736))


## Changes in 0.26.0 (2023-03-07)

🙌 Improvements

- CryptoV2: Control CryptoSDK via feature flag ([#1719](https://github.com/matrix-org/matrix-ios-sdk/pull/1719))
- Update MatrixSDKCrypto ([#1725](https://github.com/matrix-org/matrix-ios-sdk/pull/1725))
- Use correct next users with keys query ([#1726](https://github.com/matrix-org/matrix-ios-sdk/pull/1726))
- Creating a direct room with a third party will now use their email as the m.direct ID and their obfuscated email as the room title. ([#1727](https://github.com/matrix-org/matrix-ios-sdk/pull/1727))

🐛 Bugfixes

- Fixed incorrect filtering of "unread rooms" in the all chats list. ([#1723](https://github.com/matrix-org/matrix-ios-sdk/pull/1723))
- Unread rooms: Move the storage file to a better location. ([#1730](https://github.com/matrix-org/matrix-ios-sdk/pull/1730))
- Fixed a crash when roomSummary is nil. ([#1731](https://github.com/matrix-org/matrix-ios-sdk/pull/1731))
- Fix room list last message when the key comes late. ([#6848](https://github.com/vector-im/element-ios/issues/6848))

⚠️ API Changes

- MXRoomSummary: displayname has been renamed to displayName ([#1731](https://github.com/matrix-org/matrix-ios-sdk/pull/1731))


## Changes in 0.25.2 (2023-02-21)

🙌 Improvements

- Polls: add fallback text for poll ended events. ([#1713](https://github.com/matrix-org/matrix-ios-sdk/pull/1713))
- Push Rules: Apply push rules client side for encrypted rooms, including mentions and keywords. ([#1714](https://github.com/matrix-org/matrix-ios-sdk/pull/1714))
- Typealias MXResponse to Swift.Result ([#1715](https://github.com/matrix-org/matrix-ios-sdk/pull/1715))
- CryptoV2: Unify verification event processing ([#1717](https://github.com/matrix-org/matrix-ios-sdk/pull/1717))
- Encryption: add encryption to rooms' last messages.
  WARNING: the migration to this database version will cause an initial full sync. ([#1718](https://github.com/matrix-org/matrix-ios-sdk/pull/1718))

🐛 Bugfixes

- Avoid sending a verification cancel request while the session is closed
  Fix of some retain cycles ([#1716](https://github.com/matrix-org/matrix-ios-sdk/pull/1716))
- Fix an issue where MXMediaLoader would not start downloading until the end of the scroll. ([#1721](https://github.com/matrix-org/matrix-ios-sdk/pull/1721))


## Changes in 0.25.1 (2023-02-07)

✨ Features

- Add mark as unread option for rooms ([#7253](https://github.com/vector-im/element-ios/issues/7253))

🙌 Improvements

- Polls: add more information in PollProtocol for poll history. ([#1691](https://github.com/matrix-org/matrix-ios-sdk/pull/1691))
- CryptoV2: Decrypt notifications ([#1695](https://github.com/matrix-org/matrix-ios-sdk/pull/1695))
- CryptoV2: Upload fallback keys ([#1697](https://github.com/matrix-org/matrix-ios-sdk/pull/1697))
- CryptoV2: Set passphrase for the crypto store ([#1699](https://github.com/matrix-org/matrix-ios-sdk/pull/1699))
- Backup: Import legacy backup in batches ([#1701](https://github.com/matrix-org/matrix-ios-sdk/pull/1701))
- Notifications: add completion blocks in the API. ([#1702](https://github.com/matrix-org/matrix-ios-sdk/pull/1702))
- CryptoV2: New CryptoMachine on each background operation ([#1704](https://github.com/matrix-org/matrix-ios-sdk/pull/1704))
- CryptoV2: Fix JSONDictionary of keys query responses ([#1707](https://github.com/matrix-org/matrix-ios-sdk/pull/1707))
- CryptoV2: Enable Crypto SDK for production ([#1708](https://github.com/matrix-org/matrix-ios-sdk/pull/1708))

🐛 Bugfixes

- Fix some scenarios where an answered call continues to ring ([#1710](https://github.com/matrix-org/matrix-ios-sdk/pull/1710))


## Changes in 0.25.0 (2023-02-02)

🙌 Improvements

- CryptoV2: Decrypt notifications ([#1695](https://github.com/matrix-org/matrix-ios-sdk/pull/1695))
- CryptoV2: Upload fallback keys ([#1697](https://github.com/matrix-org/matrix-ios-sdk/pull/1697))
- CryptoV2: Set passphrase for the crypto store ([#1699](https://github.com/matrix-org/matrix-ios-sdk/pull/1699))
- Backup: Import legacy backup in batches ([#1701](https://github.com/matrix-org/matrix-ios-sdk/pull/1701))
- CryptoV2: New CryptoMachine on each background operation ([#1704](https://github.com/matrix-org/matrix-ios-sdk/pull/1704))
- CryptoV2: Fix JSONDictionary of keys query responses ([#1707](https://github.com/matrix-org/matrix-ios-sdk/pull/1707))
- CryptoV2: Enable Crypto SDK for production ([#1708](https://github.com/matrix-org/matrix-ios-sdk/pull/1708))


## Changes in 0.24.8 (2023-01-24)

✨ Features

- Implement MSC3912: Relation-based redactions ([#1688](https://github.com/matrix-org/matrix-ios-sdk/pull/1688))

🙌 Improvements

- CryptoV2: Add keys query scheduler ([#1676](https://github.com/matrix-org/matrix-ios-sdk/pull/1676))
- CryptoV2: Create crypto migration data ([#1681](https://github.com/matrix-org/matrix-ios-sdk/pull/1681))
- CryptoSDK: Perform crypto migration if necessary ([#1684](https://github.com/matrix-org/matrix-ios-sdk/pull/1684))
- Rename MXSessionSyncProgress ([#1686](https://github.com/matrix-org/matrix-ios-sdk/pull/1686))
- CryptoV2: Batch migrate olm and megolm sessions ([#1687](https://github.com/matrix-org/matrix-ios-sdk/pull/1687))
- CryptoV2: Extract room event encryption ([#1689](https://github.com/matrix-org/matrix-ios-sdk/pull/1689))
- CryptoV2: Migration improvements ([#1692](https://github.com/matrix-org/matrix-ios-sdk/pull/1692))

🐛 Bugfixes

- Messages' replies: fix localizations issues. ([#1685](https://github.com/matrix-org/matrix-ios-sdk/pull/1685))


## Changes in 0.24.7 (2023-01-10)

✨ Features

- Threads: Load the thread list using server-side sorting and pagination ([#6059](https://github.com/vector-im/element-ios/issues/6059))

🙌 Improvements

- Add API to delete user's account data. ([#1651](https://github.com/matrix-org/matrix-ios-sdk/pull/1651))
- Change Sync parser to delete empty account_data events. ([#1656](https://github.com/matrix-org/matrix-ios-sdk/pull/1656))
- CryptoV2: Disable notification decryption ([#1662](https://github.com/matrix-org/matrix-ios-sdk/pull/1662))
- CryptoV2: Verification request and QR listener ([#1663](https://github.com/matrix-org/matrix-ios-sdk/pull/1663))
- Analytics: Do not track cancellation errors ([#1664](https://github.com/matrix-org/matrix-ios-sdk/pull/1664))
- Polls: ensure polls are up to date after they are closed. ([#1672](https://github.com/matrix-org/matrix-ios-sdk/pull/1672))
- Polls: handle decryption errors. ([#1673](https://github.com/matrix-org/matrix-ios-sdk/pull/1673))
- Polls: add support for rendering/replying to poll ended events. ([#1674](https://github.com/matrix-org/matrix-ios-sdk/pull/1674))
- Remove commented device property on MXPushRulesRespose. ([#1677](https://github.com/matrix-org/matrix-ios-sdk/pull/1677))


## Changes in 0.24.6 (2022-12-13)

🙌 Improvements

- Change invites count logic. ([#1645](https://github.com/matrix-org/matrix-ios-sdk/pull/1645))
- Crypto: Fail launch when unavailable crypto ([#1646](https://github.com/matrix-org/matrix-ios-sdk/pull/1646))
- Add message id for to-device events ([#1652](https://github.com/matrix-org/matrix-ios-sdk/pull/1652))
- CryptoV2: Update to latest Verification API ([#1654](https://github.com/matrix-org/matrix-ios-sdk/pull/1654))

🧱 Build

- Update Ruby gems. ([#1655](https://github.com/matrix-org/matrix-ios-sdk/pull/1655))


## Changes in 0.24.5 (2022-11-29)

🙌 Improvements

- CryptoV2: Import progress for room keys ([#1637](https://github.com/matrix-org/matrix-ios-sdk/pull/1637))
- CryptoV2: Run all tasks with default priority ([#1639](https://github.com/matrix-org/matrix-ios-sdk/pull/1639))
- CryptoV2: Fix backup performance ([#1641](https://github.com/matrix-org/matrix-ios-sdk/pull/1641))
- MXSession: Calculate sync progress state ([#1643](https://github.com/matrix-org/matrix-ios-sdk/pull/1643))
- CryptoV2: Add support to decrypt notifications and receive keys ([#1644](https://github.com/matrix-org/matrix-ios-sdk/pull/1644))
- Pod: Fix linting on release mode & run fastlane lint on release configuration. ([#1648](https://github.com/matrix-org/matrix-ios-sdk/pull/1648))


## Changes in 0.24.4 (2022-11-29)

🙌 Improvements

- CryptoV2: Import progress for room keys ([#1637](https://github.com/matrix-org/matrix-ios-sdk/pull/1637))
- CryptoV2: Run all tasks with default priority ([#1639](https://github.com/matrix-org/matrix-ios-sdk/pull/1639))
- CryptoV2: Fix backup performance ([#1641](https://github.com/matrix-org/matrix-ios-sdk/pull/1641))
- MXSession: Calculate sync progress state ([#1643](https://github.com/matrix-org/matrix-ios-sdk/pull/1643))
- CryptoV2: Add support to decrypt notifications and receive keys ([#1644](https://github.com/matrix-org/matrix-ios-sdk/pull/1644))


## Changes in 0.24.3 (2022-11-15)

✨ Features

- Threads: added support to read receipts (MSC3771) ([#6663](https://github.com/vector-im/element-ios/issues/6663))
- Threads: added support to notifications count (MSC3773) ([#6664](https://github.com/vector-im/element-ios/issues/6664))
- Threads: added support to labs flag for read receipts ([#7029](https://github.com/vector-im/element-ios/issues/7029))
- Threads: notification count in main timeline including un participated threads ([#7038](https://github.com/vector-im/element-ios/issues/7038))

🙌 Improvements

- CryptoV2: Room event decryption ([#1627](https://github.com/matrix-org/matrix-ios-sdk/pull/1627))
- CryptoV2: Bugfixes ([#1630](https://github.com/matrix-org/matrix-ios-sdk/pull/1630))
- CryptoV2: Log decryption errors separately ([#1632](https://github.com/matrix-org/matrix-ios-sdk/pull/1632))
- Adds the sending of read receipts for poll start/end events ([#1633](https://github.com/matrix-org/matrix-ios-sdk/pull/1633))

🐛 Bugfixes

- Tests: Fix or disable flakey integration tests ([#1628](https://github.com/matrix-org/matrix-ios-sdk/pull/1628))
- Threads: removed "unread_thread_notifications" from sync filters for server that doesn't support MSC3773 ([#7066](https://github.com/vector-im/element-ios/issues/7066))
- Threads: Display number of unread messages above threads button ([#7076](https://github.com/vector-im/element-ios/issues/7076))

📄 Documentation

- Doc: Update the synapse installation section with poetry usage ([#1625](https://github.com/matrix-org/matrix-ios-sdk/pull/1625))


## Changes in 0.24.2 (2022-11-01)

🙌 Improvements

- CryptoV2: Manual key export / import ([#1608](https://github.com/matrix-org/matrix-ios-sdk/pull/1608))
- CryptoV2: Set local trust and deprecate legacy verification method ([#1613](https://github.com/matrix-org/matrix-ios-sdk/pull/1613))
- Crypto: Define MXCrypto and MXCrossSigning as protocols ([#1614](https://github.com/matrix-org/matrix-ios-sdk/pull/1614))
- CryptoV2: Cross-sign self after restoring session ([#1616](https://github.com/matrix-org/matrix-ios-sdk/pull/1616))
- Crypto: Curate MXCrypto protocol methods ([#1618](https://github.com/matrix-org/matrix-ios-sdk/pull/1618))
- Crypto: Complete MXCryptoV2 implementation ([#1620](https://github.com/matrix-org/matrix-ios-sdk/pull/1620))

🚧 In development 🚧

- Device Manger: Multi session sign out. ([#1619](https://github.com/vector-im/element-ios/issues/1619))


## Changes in 0.24.1 (2022-10-18)

🙌 Improvements

- Support additional content in voice message. ([#1595](https://github.com/matrix-org/matrix-ios-sdk/pull/1595))
- Key verification: Refactor verification manager, requests, transactions ([#1599](https://github.com/matrix-org/matrix-ios-sdk/pull/1599))
- Crypto: Refactor QR transactions ([#1602](https://github.com/matrix-org/matrix-ios-sdk/pull/1602))
- CryptoV2: Integrate Mac-compatible MatrixSDKCrypto ([#1603](https://github.com/matrix-org/matrix-ios-sdk/pull/1603))
- CryptoV2: Unencrypted verification events ([#1605](https://github.com/matrix-org/matrix-ios-sdk/pull/1605))
- Crypto: Remove megolm decrypt cache build flag ([#1606](https://github.com/matrix-org/matrix-ios-sdk/pull/1606))
- Device Manager: Exposed method to update client information. ([#1609](https://github.com/vector-im/element-ios/issues/1609))
- CryptoV2: Manual device verification ([#6781](https://github.com/vector-im/element-ios/issues/6781))
- Add support for m.local_notification_settings.<device-id> in account_data ([#6797](https://github.com/vector-im/element-ios/issues/6797))
- CryptoV2: Incoming verification requests ([#6809](https://github.com/vector-im/element-ios/issues/6809))
- CryptoV2: QR code verification ([#6859](https://github.com/vector-im/element-ios/issues/6859))

🐛 Bugfixes

- Fix users' display name in messages. ([#6850](https://github.com/vector-im/element-ios/issues/6850))

Others

- Expose rest client method for generating login tokens through MSC3882 ([#1601](https://github.com/matrix-org/matrix-ios-sdk/pull/1601))


## Changes in 0.24.0 (2022-10-04)

🙌 Improvements

- Crypto: Enable group session cache by default ([#1575](https://github.com/matrix-org/matrix-ios-sdk/pull/1575))
- Crypto: Extract key backup engine ([#1578](https://github.com/matrix-org/matrix-ios-sdk/pull/1578))
- MXSession: Set client information data if needed on resume. ([#1582](https://github.com/matrix-org/matrix-ios-sdk/pull/1582))
- MXDevice: Move to dedicated file and implement MSC-3852. ([#1583](https://github.com/matrix-org/matrix-ios-sdk/pull/1583))
- Add `enableNewClientInformationFeature` sdk option, disabled by default (PSG-799). ([#1588](https://github.com/matrix-org/matrix-ios-sdk/pull/1588))
- Remove MXRoom's partialTextMessage support ([#6670](https://github.com/vector-im/element-ios/issues/6670))
- CryptoV2: Key backups ([#6769](https://github.com/vector-im/element-ios/issues/6769))
- CryptoV2: Key gossiping ([#6773](https://github.com/vector-im/element-ios/issues/6773))
- User sessions: Add support for MSC3881 ([#6787](https://github.com/vector-im/element-ios/issues/6787))

🧱 Build

- Disable codecov/patch. ([#1579](https://github.com/matrix-org/matrix-ios-sdk/pull/1579))

⚠️ API Changes

- Upgrade minimum iOS and OSX deployment target to 13.0 and 10.15 respectively ([#1574](https://github.com/matrix-org/matrix-ios-sdk/pull/1574))

Others

- Avoid main thread assertion if we can't get the application ([#6754](https://github.com/vector-im/element-ios/issues/6754))


## Changes in 0.23.19 (2022-09-28)

🐛 Bugfixes

- CVE-2022-39255: Olm/Megolm protocol confusion ([Security advisory](https://github.com/matrix-org/matrix-ios-sdk/security/advisories/GHSA-hw6g-j8v6-9hcm))
- CVE-2022-39257: Impersonation via forwarded Megolm sessions ([Security advisory](https://github.com/matrix-org/matrix-ios-sdk/security/advisories/GHSA-qxr3-5jmq-xcf4))

## Changes in 0.23.18 (2022-09-07)

✨ Features

- MXKeyBackup: Add support for symmetric key backups. ([#1542](https://github.com/matrix-org/matrix-ios-sdk/pull/1542))
- CryptoSDK: Outgoing SAS User Verification Flow ([#6443](https://github.com/vector-im/element-ios/issues/6443))
- CryptoV2: Self-verification flow ([#6589](https://github.com/vector-im/element-ios/issues/6589))

🙌 Improvements

- Allow setting room alias regardless of join rule ([#1559](https://github.com/matrix-org/matrix-ios-sdk/pull/1559))
- Crypto: Cache inbound group sessions when decrypting ([#1566](https://github.com/matrix-org/matrix-ios-sdk/pull/1566))
- Crypto: Create lazy in-memory room encryptors ([#1570](https://github.com/matrix-org/matrix-ios-sdk/pull/1570))
- App Layout: Increased store version to force clear cache ([#6616](https://github.com/vector-im/element-ios/issues/6616))

🐛 Bugfixes

- Fix incoming calls sometimes ringing after being answered on another client ([#6614](https://github.com/vector-im/element-ios/issues/6614))

🧱 Build

- Xcode project(s) updated via Xcode recommended setting ([#1543](https://github.com/matrix-org/matrix-ios-sdk/pull/1543))
- MXLog: Ensure MXLogLevel.none works if it is set after another log level has already been configured. ([#1550](https://github.com/matrix-org/matrix-ios-sdk/issues/1550))

📄 Documentation

- README: Update the badge header ([#1569](https://github.com/matrix-org/matrix-ios-sdk/pull/1569))
- Update README for correct Swift usage. ([#1552](https://github.com/matrix-org/matrix-ios-sdk/issues/1552))

Others

- Crypto: User and device identity objects ([#1531](https://github.com/matrix-org/matrix-ios-sdk/pull/1531))
- Analytics: Log all errors to analytics ([#1558](https://github.com/matrix-org/matrix-ios-sdk/pull/1558))
- Improve MXLog file formatting and fix log message format ([#1564](https://github.com/matrix-org/matrix-ios-sdk/pull/1564))


## Changes in 0.23.17 (2022-08-31)

🙌 Improvements

- KeyBackups: Add build flag for symmetric backup ([#1567](https://github.com/matrix-org/matrix-ios-sdk/pull/1567))


## Changes in 0.23.16 (2022-08-24)

✨ Features

- MXKeyBackup: Add support for symmetric key backups. ([#1542](https://github.com/matrix-org/matrix-ios-sdk/pull/1542))
- CryptoSDK: Outgoing SAS User Verification Flow ([#6443](https://github.com/vector-im/element-ios/issues/6443))

🙌 Improvements

- App Layout: Increased store version to force clear cache ([#6616](https://github.com/vector-im/element-ios/issues/6616))

🧱 Build

- Xcode project(s) updated via Xcode recommended setting ([#1543](https://github.com/matrix-org/matrix-ios-sdk/pull/1543))
- MXLog: Ensure MXLogLevel.none works if it is set after another log level has already been configured. ([#1550](https://github.com/matrix-org/matrix-ios-sdk/issues/1550))

📄 Documentation

- Update README for correct Swift usage. ([#1552](https://github.com/matrix-org/matrix-ios-sdk/issues/1552))

Others

- Crypto: User and device identity objects ([#1531](https://github.com/matrix-org/matrix-ios-sdk/pull/1531))
- Analytics: Log all errors to analytics ([#1558](https://github.com/matrix-org/matrix-ios-sdk/pull/1558))


## Changes in 0.23.15 (2022-08-10)

🐛 Bugfixes

- MXSpaceService: Fix a crash on Synapse 1.65 following changes to the /hierarchy API. ([#6547](https://github.com/vector-im/element-ios/issues/6547))


## Changes in 0.23.14 (2022-08-09)

🙌 Improvements

- CI: Enable integration tests on GitHub actions ([#1537](https://github.com/matrix-org/matrix-ios-sdk/pull/1537))
- App Layout: Added breadcrumbs data fetcher and updated room summary data type to reflect new needs ([#6407](https://github.com/vector-im/element-ios/issues/6407))
- App Layout: added MXSpace.minimumPowerLevelForAddingRoom() and MXSpaceService.rootSpaces ([#6410](https://github.com/vector-im/element-ios/issues/6410))

🐛 Bugfixes

- MXRestClient: Send an empty dictionary when calling /join to be spec compliant. ([#6481](https://github.com/vector-im/element-ios/issues/6481))
- App Layout: exclude room summaries without notifications from unread list ([#6511](https://github.com/vector-im/element-ios/issues/6511))


## Changes in 0.23.13 (2022-07-26)

🙌 Improvements

- MXRoom: Support reply to beacon info event. ([#6423](https://github.com/vector-im/element-ios/issues/6423))
- MXBeaconAggregations: Handle beacon info redaction. ([#6470](https://github.com/vector-im/element-ios/issues/6470))

🐛 Bugfixes

- Fix formatted_body content for unformatted events ([#6446](https://github.com/vector-im/element-ios/issues/6446))

🧱 Build

- Disable nightly tests for now as they're always timing out. ([#1523](https://github.com/matrix-org/matrix-ios-sdk/pull/1523))

Others

- Reduce project warnings ([#1527](https://github.com/matrix-org/matrix-ios-sdk/pull/1527))
- Crypto: Convert verification request and transaction to protocols ([#1528](https://github.com/matrix-org/matrix-ios-sdk/pull/1528))


## Changes in 0.23.12 (2022-07-13)

🐛 Bugfixes

- Fix JingleCallStack UI threading crashes ([#6415](https://github.com/vector-im/element-ios/issues/6415))


## Changes in 0.23.11 (2022-07-12)

✨ Features

- Analytics: Track non-fatal issues if consent provided ([#1503](https://github.com/matrix-org/matrix-ios-sdk/pull/1503))
- Crypto: Integrate Rust-based OlmMachine to encrypt / decrypt messages ([#6357](https://github.com/vector-im/element-ios/issues/6357))

🙌 Improvements

- Include ID server access token when making a 3pid invite (and creating a room). ([#6385](https://github.com/vector-im/element-ios/issues/6385))

🐛 Bugfixes

- MXiOSAudioOutputRouter: fixed issue that prevents the system to properly switch from built-in to bluetooth output. ([#5368](https://github.com/vector-im/element-ios/issues/5368))
- Fix MXCall answer not being sent to server in some cases ([#6359](https://github.com/vector-im/element-ios/issues/6359))

Others

- Integration tests should wait until the room is ready ([#1516](https://github.com/matrix-org/matrix-ios-sdk/pull/1516))
- Analytics: Log errors with details in analytics ([#1517](https://github.com/matrix-org/matrix-ios-sdk/pull/1517))
- Secret Storage: Detect multiple valid SSSS keys ([#4569](https://github.com/vector-im/element-ios/issues/4569))


## Changes in 0.23.10 (2022-06-28)

✨ Features

- Add missing "user_busy" MXCallHangupEvent ([#1342](https://github.com/vector-im/element-ios/issues/1342))

🐛 Bugfixes

- Handle empty pagination end token on timeline end reached ([#6347](https://github.com/vector-im/element-ios/issues/6347))

⚠️ API Changes

- Drop support for iOS 10 and 32-bit architectures ([#1501](https://github.com/matrix-org/matrix-ios-sdk/pull/1501))

🧱 Build

- CI: Add concurrency to GitHub Actions. ([#5039](https://github.com/vector-im/element-ios/issues/5039))
- Add Codecov for unit tests coverage. ([#6306](https://github.com/vector-im/element-ios/issues/6306))

Others

- Crypto: Subclass MXCrypto to enable work-in-progress Rust sdk ([#1496](https://github.com/matrix-org/matrix-ios-sdk/pull/1496))
- MXBackgroundSyncService - Expose separate method for fetching a particular room's read marker event without causing extra syncs. ([#1500](https://github.com/matrix-org/matrix-ios-sdk/pull/1500))
- Crypto: Integrate new Rust-based MatrixSDKCrypto framework for DEBUG builds ([#1501](https://github.com/matrix-org/matrix-ios-sdk/pull/1501))


## Changes in 0.23.9 (2022-06-14)

🐛 Bugfixes

- Fix a crash on start if the user has a very large number of unread events in a room ([#1490](https://github.com/matrix-org/matrix-ios-sdk/pull/1490))
- Prevent invalid room names on member count underflows. ([#6227](https://github.com/vector-im/element-ios/issues/6227))
- Location sharing: Fix geo URI parsing with altitude component. ([#6247](https://github.com/vector-im/element-ios/issues/6247))

⚠️ API Changes

- MXRestClient: Add `logoutDevices` parameter to `changePassword` method. ([#6175](https://github.com/vector-im/element-ios/issues/6175))
- Mark MXRestClient init as `required` for mocking. ([#6179](https://github.com/vector-im/element-ios/issues/6179))


## Changes in 0.23.8 (2022-06-03)

🐛 Bugfixes

- Room state: Reload room state if detected empty on disk ([#1483](https://github.com/matrix-org/matrix-ios-sdk/pull/1483))
- Remove unwanted parts from replies new_content body/formatted_body ([#3517](https://github.com/vector-im/element-ios/issues/3517))
- MXBackgroundStore: Avoid clearing file store if event stream token is missing. ([#5924](https://github.com/vector-im/element-ios/issues/5924))
- MXRestClient: limit the query length to 2048 for joinRoom ([#6224](https://github.com/vector-im/element-ios/issues/6224))
- Bump realm to 10.27.0 to fix crypto performance issue. ([#6239](https://github.com/vector-im/element-ios/issues/6239))

🚧 In development 🚧

- Location sharing: Authorize only one live beacon info per member and per room. ([#6100](https://github.com/vector-im/element-ios/issues/6100))

Others

- Crypto: Add more logs when encrypting messages ([#1476](https://github.com/matrix-org/matrix-ios-sdk/pull/1476))


## Changes in 0.23.7 (2022-05-31)

🐛 Bugfixes

- MXSession: Recreate room summaries when detected missing. ([#5924](https://github.com/vector-im/element-ios/issues/5924))
- Fixed crashes on invalid casting of MXUser to MXMyUser causing unrecognized selectors on the mxSession property. ([#6187](https://github.com/vector-im/element-ios/issues/6187))
- MXCoreDataRoomSummaryStore: Make removing a room summary synchronous. ([#6218](https://github.com/vector-im/element-ios/issues/6218))

⚠️ API Changes

- MXTools: generateTransactionId no longer returns an optional in Swift. ([#1477](https://github.com/matrix-org/matrix-ios-sdk/pull/1477))

🚧 In development 🚧

- Location sharing: Persist beacon info summaries to disk. ([#6199](https://github.com/vector-im/element-ios/issues/6199))

Others

- MXFileStore: Add extra logs when saving and loading room state ([#1478](https://github.com/matrix-org/matrix-ios-sdk/pull/1478))
- MXBackgroundSyncServiceTests: Add tests for outdated gappy syncs. ([#6142](https://github.com/vector-im/element-ios/issues/6142))


## Changes in 0.23.6 (2022-05-19)

No significant changes.


## Changes in 0.23.5 (2022-05-18)

✨ Features

- Add `io.element.video` room type. ([#6149](https://github.com/vector-im/element-ios/issues/6149))

🙌 Improvements

- Rooms: support for attributedPartialTextMessage storage ([#3526](https://github.com/vector-im/element-ios/issues/3526))

🚧 In development 🚧

- MXBeaconInfoSummary: Add room id and support device id update after start location sharing. ([#5722](https://github.com/vector-im/element-ios/issues/5722))

Others

- Update check for server-side threads support to match spec. ([#1460](https://github.com/matrix-org/matrix-ios-sdk/pull/1460))


## Changes in 0.23.4 (2022-05-05)

🙌 Improvements

- Crypto: Share Megolm session keys when inviting a new user ([#4947](https://github.com/vector-im/element-ios/issues/4947))
- Authentication: Add MXUsernameAvailability and isUsernameAvailable method on MXRestClient. ([#5648](https://github.com/vector-im/element-ios/issues/5648))

🐛 Bugfixes

- MXSpaceService: added method firstRootAncestorForRoom ([#5965](https://github.com/vector-im/element-ios/issues/5965))
- MXRoom: Update room summary after removing/refreshing unsent messages. ([#6040](https://github.com/vector-im/element-ios/issues/6040))

🚧 In development 🚧

- Location sharing: Handle live location beacon event. Handle beacon info + beacon data aggregation. ([#6021](https://github.com/vector-im/element-ios/issues/6021))
- Location sharing: Handle stop live location sharing. ([#6070](https://github.com/vector-im/element-ios/issues/6070))
- Location sharing: MXBeaconInfoSummary add isActive property. ([#6113](https://github.com/vector-im/element-ios/issues/6113))

## Changes in 0.23.3 (2022-04-20)

🙌 Improvements

- Location sharing: Handle live location sharing start event. ([#5903](https://github.com/vector-im/element-ios/issues/5903))
- Add a preferred presence property to MXSession ([#5995](https://github.com/vector-im/element-ios/issues/5995))
- Pods: Upgrade JitsiMeetSDK to 5.0.2 and re-enable building for ARM64 simulator. ([#6018](https://github.com/vector-im/element-ios/issues/6018))

🐛 Bugfixes

- MatrixSDK: Fix some crashes after 1.8.10. ([#6023](https://github.com/vector-im/element-ios/issues/6023))

Others

- Fix some warnings. ([#1440](https://github.com/matrix-org/matrix-ios-sdk/pull/1440))


## Changes in 0.23.2 (2022-04-05)

🙌 Improvements

- Room: Return room identifier and known servers when resolving alias ([#4858](https://github.com/vector-im/element-ios/issues/4858))
- MXRestClient: Use the stable hierarchy endpoint from MSC2946 ([#5144](https://github.com/vector-im/element-ios/issues/5144))
- MXPublicRoom: added implementation for JSONDictionary ([#5953](https://github.com/vector-im/element-ios/issues/5953))

🐛 Bugfixes

- MXEventListener/MXRoomSummary: Fix retain cycles ([#5058](https://github.com/vector-im/element-ios/issues/5058))
- Sync Spaces order with web ([#5134](https://github.com/vector-im/element-ios/issues/5134))
- VoIP: Recreate CXProvider if a call cannot be hung up ([#5189](https://github.com/vector-im/element-ios/issues/5189))
- MXThreadingService: Apply edits on thread root and latest events of a thread list. ([#5845](https://github.com/vector-im/element-ios/issues/5845))
- MXThread: Fix redacted events & fix undecrypted events. ([#5877](https://github.com/vector-im/element-ios/issues/5877))
- Room: Do not commit to file store after typing a single character ([#5906](https://github.com/vector-im/element-ios/issues/5906))
- Move `handleRoomKeyEvent` logic back to `MXSession`. ([#5938](https://github.com/vector-im/element-ios/issues/5938))
- MXSuggestedRoomListDataFetcher: Spaces shouldn't be displayed as suggested rooms ([#5978](https://github.com/vector-im/element-ios/issues/5978))

⚠️ API Changes

- Location sharing: Add new event asset type for pin drop location sharing ([#5858](https://github.com/vector-im/element-ios/issues/5858))


## Changes in 0.23.1 (2022-03-28)

🙌 Improvements

- MXRestClient: Use the stable hierarchy endpoint from MSC2946 ([#5144](https://github.com/vector-im/element-ios/issues/5144))

🐛 Bugfixes

- Sync Spaces order with web ([#5134](https://github.com/vector-im/element-ios/issues/5134))


## Changes in 0.23.0 (2022-03-22)

✨ Features

- MXSpace: added canAddRoom() method ([#5230](https://github.com/vector-im/element-ios/issues/5230))
- MXRoomAliasAvailabilityChecker: added extractLocalAliasPart() ([#5233](https://github.com/vector-im/element-ios/issues/5233))

🙌 Improvements

- Space creation: Added home server capabilities, room alias validator, restricted join rule, refined space related API, and added tests ([#5224](https://github.com/vector-im/element-ios/issues/5224))
- Added room upgrade API call and the ability to (un)suggest a room for a space ([#5231](https://github.com/vector-im/element-ios/issues/5231))
- MXSpaceService: added `spaceSummaries` property ([#5401](https://github.com/vector-im/element-ios/issues/5401))
- Threads: Fix deleted thread root & decrypt thread list. ([#5441](https://github.com/vector-im/element-ios/issues/5441))
- Threads: Replace property for in-thread replies. ([#5704](https://github.com/vector-im/element-ios/issues/5704))
- MXRoomEventFilter: Update property names for relation types and senders. ([#5705](https://github.com/vector-im/element-ios/issues/5705))
- MXThreadingService: Use versions instead of capabilities to check threads server support. ([#5744](https://github.com/vector-im/element-ios/issues/5744))
- MXEventContentRelatesTo: Update reply fallback property name and reverse the logic. ([#5790](https://github.com/vector-im/element-ios/issues/5790))
- Threads: Update all properties to stable values. ([#5791](https://github.com/vector-im/element-ios/issues/5791))
- Room: API to ignore the sender of a room invite before the room is joined ([#5807](https://github.com/vector-im/element-ios/issues/5807))
- MXRoom: Do not try to guess threadId for replies, get that as a parameter. ([#5829](https://github.com/vector-im/element-ios/issues/5829))
- MXThreadingService: Fix number of replies & notification/highlight counts for threads. ([#5843](https://github.com/vector-im/element-ios/issues/5843))

🐛 Bugfixes

- MXThreadEventTimeline: Decrypt events fetched from server. ([#5749](https://github.com/vector-im/element-ios/issues/5749))
- MXRoom: Fix retain cycles, in particular between MXRoomOperation and its block. ([#5805](https://github.com/vector-im/element-ios/issues/5805))
- Timeline: Prevent skipping an item between each pagination batch ([#5819](https://github.com/vector-im/element-ios/issues/5819))
- Crypto: Distinguish between original and edit message when preventing replay attacks ([#5835](https://github.com/vector-im/element-ios/issues/5835))
- MXThreadEventTimeline: Fix processing order of thread events & fix empty thread screen issue. ([#5840](https://github.com/vector-im/element-ios/issues/5840))
- Timeline: Paginated events always show the most recent edit ([#5848](https://github.com/vector-im/element-ios/issues/5848))
- MXFileStore: Log when filters cannot be saved or loaded ([#5873](https://github.com/vector-im/element-ios/issues/5873))


## Changes in 0.22.6 (2022-03-14)

🙌 Improvements

- Room: API to ignore the sender of a room invite before the room is joined ([#5807](https://github.com/vector-im/element-ios/issues/5807))


## Changes in 0.22.5 (2022-03-08)

🙌 Improvements

- Room data filters: strict matches support ([#1379](https://github.com/matrix-org/matrix-ios-sdk/pull/1379))
- Analytics: Add event composition tracking and isSpace for joined room events. ([#5365](https://github.com/vector-im/element-ios/issues/5365))
- MXEvent+Extensions: Do not highlight any event that the current user sent. ([#5552](https://github.com/vector-im/element-ios/issues/5552))

🐛 Bugfixes

- Room: fix crash on members count not being always properly set ([#4949](https://github.com/vector-im/element-ios/issues/4949))
- MXSuggestedRoomListDataFetcher: hide suggested rooms that a user is already part of ([#5276](https://github.com/vector-im/element-ios/issues/5276))
- MXFileStore: Do not reuse room files if the room is marked for deletion ([#5717](https://github.com/vector-im/element-ios/issues/5717))


## Changes in 0.22.4 (2022-02-25)

🙌 Improvements

- MXThreadingService: Add thread creation delegate method. ([#5694](https://github.com/vector-im/element-ios/issues/5694))


## Changes in 0.22.3 (2022-02-24)

🐛 Bugfixes

- Thread Safety: Replace all objc_sync_enter/exit methods with recursive locks. ([#5675](https://github.com/vector-im/element-ios/issues/5675))


## Changes in 0.22.2 (2022-02-22)

🙌 Improvements

- Added support for unstable poll prefixes. ([#5114](https://github.com/vector-im/element-ios/issues/5114))
- Exclude all files and directories from iCloud and iTunes backup ([#5498](https://github.com/vector-im/element-ios/issues/5498))
- MXSession & MXThreadingService: Implement server capabilities api & implement thread list api according to server capabilities. ([#5540](https://github.com/vector-im/element-ios/issues/5540))
- MXThreadEventTimeline: Replace context api with relations api. ([#5629](https://github.com/vector-im/element-ios/issues/5629))

🐛 Bugfixes

- Settings: fix phone number validation through custom URL ([#3562](https://github.com/vector-im/element-ios/issues/3562))
- MXRoomListData: Consider all properties when comparing room list data. ([#5537](https://github.com/vector-im/element-ios/issues/5537))

🧱 Build

- Use the --no-rate-limit flag as mentioned in the README ([#1352](https://github.com/vector-im/element-ios/issues/1352))


## Changes in 0.22.1 (2022-02-16)

🐛 Bugfixes

- Fix e2ee regression introduced by #1358 ([#5564](https://github.com/vector-im/element-ios/issues/5564))


## Changes in 0.22.0 (2022-02-09)

✨ Features

- Add .well-known parsing for tile server / map style configurations. ([#5298](https://github.com/vector-im/element-ios/issues/5298))

🙌 Improvements

- Introduce `MXThreadingService` and `MXThread` classes. ([#5068](https://github.com/vector-im/element-ios/issues/5068))
- MXThreadingService: Expose threads of a room. ([#5092](https://github.com/vector-im/element-ios/issues/5092))
- Threads: Include redacted root events into threads. ([#5119](https://github.com/vector-im/element-ios/issues/5119))
- MXSession: Avoid event/null requests and reprocess bg sync cache if received when processing. ([#5426](https://github.com/vector-im/element-ios/issues/5426))
- MXRoomListDataFetcherDelegate: Add `totalCountsChanged` parameter to delegate method. ([#5448](https://github.com/vector-im/element-ios/issues/5448))

🐛 Bugfixes

- 🐛 Protect the spacesPerId variable by a barrier - Fixes Thread 1: EXC_BAD_ACCESS crash that would occur whenever multiple concurrent threads would attempt to mutate spacesPerId at the same time ([#1350](https://github.com/vector-im/element-ios/issues/1350))
- Fix for display name and avatar shown incorrectly for users that have left the room. ([#2827](https://github.com/vector-im/element-ios/issues/2827))
- Protect against encryption state loss ([#5184](https://github.com/vector-im/element-ios/issues/5184))
- MXSpace: fix space invites blocks space graph build ([#5432](https://github.com/vector-im/element-ios/issues/5432))
- MXCoreDataRoomSummaryStore: Fix main context merges from persistent store. ([#5462](https://github.com/vector-im/element-ios/issues/5462))
- MXSession: Do not pause the session if a sync fails due to cancellation. ([#5509](https://github.com/vector-im/element-ios/issues/5509))
- CoreData: Fix fetch requests fetching only specific properties. ([#5519](https://github.com/vector-im/element-ios/issues/5519))

⚠️ API Changes

- MXRestClient & MXRoom: Introduce `threadId` parameters for event sending methods. ([#5068](https://github.com/vector-im/element-ios/issues/5068))

🧱 Build

- Update Fastfile to use Xcode 13.2 on CI. ([#4883](https://github.com/vector-im/element-ios/issues/4883))

Others

- Add WIP to towncrier. ([#1349](https://github.com/matrix-org/matrix-ios-sdk/pull/1349))


## Changes in 0.21.0 (2022-01-25)

✨ Features

- MXRoomSummaryStore & MXRoomListDataManager: Implementation with Core Data. ([#4384](https://github.com/vector-im/element-ios/issues/4384))
- Allow editing poll start events. ([#5114](https://github.com/vector-im/element-ios/issues/5114))
- Added static location sharing sending and rendering support. ([#5298](https://github.com/vector-im/element-ios/issues/5298))

🙌 Improvements

- MXCoreDataRoomSummaryStore: Use nested contexts to better manage main context updates. ([#5412](https://github.com/vector-im/element-ios/issues/5412))
- Only count joined rooms when profiling sync performance. ([#5429](https://github.com/vector-im/element-ios/issues/5429))

🐛 Bugfixes

- Fixes DTMF(dial tones) during voice calls. ([#5375](https://github.com/vector-im/element-ios/issues/5375))
- MXCoreDataRoomListDataFetcher: Update fetchRequest if properties changed before fetching the first page. ([#5377](https://github.com/vector-im/element-ios/issues/5377))
- MXSession: Fix remove room race case. ([#5412](https://github.com/vector-im/element-ios/issues/5412))


## Changes in 0.20.16 (2022-01-11)

🙌 Improvements

- MXResponse has been frozen for binary compatibility when building as an XCFramework. ([#1002](https://github.com/matrix-org/matrix-ios-sdk/pull/1002))
- MXTaskProfile: Add an MXTaskProfileName enum instead of individual strings for Name and Category. ([#5035](https://github.com/vector-im/element-ios/issues/5035))

⚠️ API Changes

- MXAnalyticsDelegate: The generic methods have been replaced with type safe ones for each event tracked. ([#5035](https://github.com/vector-im/element-ios/issues/5035))


## Changes in 0.20.15 (2021-12-14)

🙌 Improvements

- Expose missing Jingle headers in umbrella header ([#1308](https://github.com/matrix-org/matrix-ios-sdk/pull/1308))

⚠️ API Changes

- MXTools: Add an error parameter to the failure of +convertVideoAssetToMP4:withTargetFileSize:success:failure: ([#4749](https://github.com/vector-im/element-ios/issues/4749))


## Changes in 0.20.14 (2021-12-09)

🐛 Bugfixes

- Sending blank m.room.encryption on iOS will disable encryption ([Security advisory](https://github.com/matrix-org/matrix-ios-sdk/security/advisories/GHSA-fxvm-7vhj-wj98))

## Changes in 0.20.13 (2021-12-06)

Others

- Replace semantic imports with classic ones to enable use of the SDK in Kotlin Multiplatform Mobile projects ([#5046](https://github.com/vector-im/element-ios/issues/5046))


## Changes in 0.20.12 (2021-12-06)

🐛 Bugfixes

- Fix release 0.20.11 ([#5247](https://github.com/vector-im/element-ios/issues/5247))


## Changes in 0.20.11 (2021-12-03)

✨ Features

- Moved from /space to /hierarchy API to support pagination ([#4893](https://github.com/vector-im/element-ios/issues/4893))
- Adds clientPermalinkBaseUrl for a custom permalink base url. ([#4981](https://github.com/vector-im/element-ios/issues/4981))
- Added poll specific event sending methods, event aggregator and model builder. ([#5114](https://github.com/vector-im/element-ios/issues/5114))

🐛 Bugfixes

- Initialize imagesCacheLruCache before caching - caching operations would fail silently because cache was not initialized ([#1281](https://github.com/vector-im/element-ios/issues/1281))
- MXRoom: Fix reply event content for just thread-aware clients. ([#5007](https://github.com/vector-im/element-ios/issues/5007))
- Add ability to get roomAccountData from MXBackgroundSyncService to fix badge bug from virtual rooms. ([#5155](https://github.com/vector-im/element-ios/issues/5155))
- Fixed duplicated children ids in MXSpaces ([#5181](https://github.com/vector-im/element-ios/issues/5181))
- Do not expose headers that should be use privately inside the framework. ([#5194](https://github.com/vector-im/element-ios/issues/5194))
- Fix for the in-call screen freezing on a new PSTN call. ([#5223](https://github.com/vector-im/element-ios/issues/5223))

🧱 Build

- Build: Update to Xcode 12.5 in the Fastfile and macOS 11 in the GitHub actions. ([#5195](https://github.com/vector-im/element-ios/issues/5195))


## Changes in 0.20.10 (2021-11-17)

🙌 Improvements

- Made room list fetch sort and filter options structs. Removed fetch options references from them and made them equatable. Comparing them in the fetch options before refreshing the fetchers. ([#4384](https://github.com/vector-im/element-ios/issues/4384))
- MXRealmCryptoStore: Reuse background tasks and use new api for remaining perform operations. ([#4431](https://github.com/vector-im/element-ios/issues/4431))

🐛 Bugfixes

- MXAggregations: Ensure the store is cleared when the file store is cleared. ([#3884](https://github.com/vector-im/element-ios/issues/3884))
- MXSpaceService: abort graph building when session is closing ([#5049](https://github.com/vector-im/element-ios/issues/5049))
- Fixed retain cycles between background tasks and themselves, and between the background task expiration handler and the background mode handler. ([#5054](https://github.com/vector-im/element-ios/issues/5054))
- MXRoomSummaryUpdater: Fix upgraded rooms being marked as visible if the tombstone event comes in as part of a limited sync. ([#5080](https://github.com/vector-im/element-ios/issues/5080))
- MXRoomListDataFilterOptions: Filter out any cached room previews. ([#5083](https://github.com/vector-im/element-ios/issues/5083))
- MXRoomListDataSortOptions: Fix room ordering regression. ([#5105](https://github.com/vector-im/element-ios/issues/5105))
- Fixed fallback key signature validation. ([#5120](https://github.com/vector-im/element-ios/issues/5120))
- MXSession: Make session resumable from paused state & avoid to-device events catchup request when paused or pause requested. ([#5127](https://github.com/vector-im/element-ios/issues/5127))
- Room ordering: Improve membership event filtering. ([#5150](https://github.com/vector-im/element-ios/issues/5150))


## Changes in 0.20.9 (2021-10-21)

🐛 Bugfixes

- MXRoomListDataFilterOptions: Fix predicate for orphaned rooms. ([#5031](https://github.com/vector-im/element-ios/issues/5031))


## Changes in 0.20.8 (2021-10-20)

🙌 Improvements

- RoomSummaries: Introduce `MXRoomListDataManager` and implementation. ([#4384](https://github.com/vector-im/element-ios/issues/4384))
- MXIdentityService: Add an areAllTermsAgreed property. ([#4484](https://github.com/vector-im/element-ios/issues/4484))

🐛 Bugfixes

- MXMemoryStore: Add missing synthesize for `areAllIdentityServerTermsAgreed`. ([#1264](https://github.com/matrix-org/matrix-ios-sdk/issues/1264))
- Fixed space preview toast is broken if I'm not a member when clicking on a link ([#4966](https://github.com/vector-im/element-ios/issues/4966))


## Changes in 0.20.7 (2021-10-13)

🐛 Bugfixes

- [MXSPaceService, MXSpaceNotificationCounter] Avoid calling SDK dispatch queue synchroniously ([#4999](https://github.com/vector-im/element-ios/issues/4999))


## Changes in 0.20.6 (2021-10-12)

🐛 Bugfixes

- fixed crash in `MXSpaceService.prepareData()` ([#4979](https://github.com/vector-im/element-ios/issues/4979))


## Changes in 0.20.5 (2021-10-08)

🙌 Improvements

- Tests: Improve tests suites execution time by fixing leaked MXSession instances that continued to run in background. ([#4875](https://github.com/vector-im/element-ios/issues/4875))
- Added dynamism and compile time safety to room name and send reply event localizable strings. ([#4899](https://github.com/vector-im/element-ios/issues/4899))
- Pods: Update JitsiMeetSDK and Realm. ([#4939](https://github.com/vector-im/element-ios/issues/4939))
- Start a background task for every Realm transaction. ([#4964](https://github.com/vector-im/element-ios/issues/4964))

🐛 Bugfixes

- Apply threading model for Spaces and cache space graph ([#4898](https://github.com/vector-im/element-ios/issues/4898))

⚠️ API Changes

- MXRoomSummaryUpdater: Combine ignoreMemberProfileChanges and eventsFilterForMessages into a single property called allowedLastMessageEventTypes. ([#4451](https://github.com/vector-im/element-ios/issues/4451))
- `MXSendReplyEventStringsLocalizable` is now `MXSendReplyEventStringLocalizerProtocol` and `MXRoomNameStringsLocalizable` is now `MXRoomNameStringLocalizerProtocol` ([#4899](https://github.com/vector-im/element-ios/issues/4899))

🧱 Build

- Bundler: Update CocoaPods and fastlane. ([#4951](https://github.com/vector-im/element-ios/issues/4951))


## Changes in 0.20.4 (2021-09-30)

🐛 Bugfixes

- MXSpaceService: Fix a crash due to recursion depth limit ([#4919](https://github.com/vector-im/element-ios/issues/4919))


## Changes in 0.20.3 (2021-09-28)

🙌 Improvements

- Renaming DM rooms to [User Name](Left) after the only other participant leaves. ([#4717](https://github.com/vector-im/element-ios/issues/4717))

🐛 Bugfixes

- MXSpaceService: fixed crash in MXSpaceService.prepareData ([#4910](https://github.com/vector-im/element-ios/issues/4910))
- MXSession: Make `directRooms` property atomic and copying. ([#4911](https://github.com/vector-im/element-ios/issues/4911))
- MXSpaceNotificationCounter: fixed crash in MXSpaceNotificationCounter.isRoomMentionsOnly. ([#4912](https://github.com/vector-im/element-ios/issues/4912))
- MXRoom: fixed crash in MXRoom.toSpace() ([#4913](https://github.com/vector-im/element-ios/issues/4913))
- MXSession: Allow pausing on syncInProgress state. ([#4915](https://github.com/vector-im/element-ios/issues/4915))
- fixed Spaces still visible after logging in with another account ([#4916](https://github.com/vector-im/element-ios/issues/4916))
- MXSpaceService: fixed App may not start in 1.6.0 ([#4919](https://github.com/vector-im/element-ios/issues/4919))


## Changes in 0.20.2 (2021-09-24)

✨ Features

- Implemented Olm fallback key support. ([#4406](https://github.com/vector-im/element-ios/issues/4406))
- Added room summary API call ([#4498](https://github.com/vector-im/element-ios/issues/4498))
- Added support to get suggested rooms ([#4500](https://github.com/vector-im/element-ios/issues/4500))
- Initial yet naive algortihm for building the graph of rooms ([#4509](https://github.com/vector-im/element-ios/issues/4509))
- Added support for Explore rooms ([#4571](https://github.com/vector-im/element-ios/issues/4571))

🙌 Improvements

- Add fallback keys to the dehydrated device info and sign it with the MSK. ([#4255](https://github.com/vector-im/element-ios/issues/4255))
- Cross-signing: Sign the key backup with the MSK. ([#4338](https://github.com/vector-im/element-ios/issues/4338))


## Changes in 0.20.1 (2021-09-16)

🙌 Improvements

- MXRoomSummary: Introduce `markAllAsReadLocally` method. ([#4822](https://github.com/vector-im/element-ios/issues/4822))

🐛 Bugfixes

- MXSession: Introduce `pauseable` property and pause the session gracefully when sync request cancelled. ([#4834](https://github.com/vector-im/element-ios/issues/4834))


## Changes in 0.20.0 (2021-09-09)

✨ Features

- MXRestClient: Add previewForURL method which fetches an MXURLPreview. ([#888](https://github.com/vector-im/element-ios/issues/888))

🙌 Improvements

- MXStore: Introduce loadRoomMessages async method to lazy load room messages. ([#4382](https://github.com/vector-im/element-ios/issues/4382))
- MXStore: Introduce loadReceiptsForRoom async method to lazy load room receipts. ([#4383](https://github.com/vector-im/element-ios/issues/4383))
- MXTools: Add fileSizeToString function that uses NSByteCountFormatter. ([#4479](https://github.com/vector-im/element-ios/issues/4479))
- MXFileStore: Synchronize creation of room message, outgoing room messages and room receipts data. ([#4788](https://github.com/vector-im/element-ios/issues/4788))

🐛 Bugfixes

- MXUser.m: Add a property `latestUpdateTS` to update the user's avatar and displayname only when event.originServerTs > latestUpdateTS. Contributed by Anna. ([#1207](https://github.com/vector-im/element-ios/issues/1207))
- MXSession: Revert state after processing background cache. ([#4021](https://github.com/vector-im/element-ios/issues/4021))
- Prevent expired verification requests from showing when opening the app. ([#4472](https://github.com/vector-im/element-ios/issues/4472))
- Don't show personal avatar in rooms when not explicitly set ([#4766](https://github.com/vector-im/element-ios/issues/4766))
- MXMemoryStore: Fix unexpected room unread count zeroing. ([#4796](https://github.com/vector-im/element-ios/issues/4796))
- MXCrossSigning.setupWithPassword failure block not called from the main thread. ([#4804](https://github.com/vector-im/element-ios/issues/4804))

⚠️ API Changes

- MXStore: `getEventReceipts` method is now async.
  MXRoom: `getEventReceipts` method is now async. ([#4383](https://github.com/vector-im/element-ios/issues/4383))


## Changes in 0.19.8 (2021-08-26)

✨ Features

- MxNotificationCenter: For new account notification settings and keywords support, added updatePushRuleActions and addContentRuleWithMatchingRuleIdAndPattern. Also fixed the url encoding on ruleId. ([#4467](https://github.com/vector-im/element-ios/issues/4467))

🙌 Improvements

- MXSession: Introduce `MXSessionStateProcessingLocalCache` state. Merge local cached sync responses when resuming the session. ([#4471](https://github.com/vector-im/element-ios/issues/4471))
- MXRoom: Added extensible keys to sent file payloads. ([#4720](https://github.com/vector-im/element-ios/issues/4720))


## Changes in 0.19.7 (2021-08-11)

🙌 Improvements

- MXRoomSummaryUpdater: Add variants of updateSummaryDisplayname and updateSummaryAvatar methods that can exclude specified user IDs. ([#4609](https://github.com/vector-im/element-ios/issues/4609))

🐛 Bugfixes

- Tests: Fix a crash in various tests from a missing `storeMaxUploadSize` method. ([#1175](https://github.com/matrix-org/matrix-ios-sdk/issues/1175))
- MXAggregations: Fixes reactions not being updated from bundled relationships. ([#3884](https://github.com/vector-im/element-ios/issues/3884))
- MXSession: Fix `fixRoomsSummariesLastMessage` method for last messages and improve it to use a hash not to run every time ([#4440](https://github.com/vector-im/element-ios/issues/4440))
- VoIP: Fix detection of other party when joined the room. ([#4664](https://github.com/vector-im/element-ios/issues/4664))
- MXRoomState: Fix a crash on `aliases` getter. ([#4678](https://github.com/vector-im/element-ios/issues/4678))
- MXOlmDevice: Fix a crash on `sessionIdsForDevice` method. ([#4679](https://github.com/vector-im/element-ios/issues/4679))

⚠️ API Changes

- SSO: Stable ids for MSC 2858. ([#4362](https://github.com/vector-im/element-ios/issues/4362))
- MXRestClient: Removed /send_relation to manage reactions as it was never implemented. ([#4507](https://github.com/vector-im/element-ios/issues/4507))

🧱 Build

- CHANGES.md: Use towncrier to manage the change log. More info in [CONTRIBUTING](CONTRIBUTING.md#changelog). ([#1196](https://github.com/matrix-org/matrix-ios-sdk/pull/1196), [#4393](https://github.com/vector-im/element-ios/issues/4393))

📄 Documentation

- Convert CHANGES and CONTRIBUTING to MarkDown. ([#4393](https://github.com/vector-im/element-ios/issues/4393))


## Changes in 0.19.6 (2021-07-29)

🐛 Bugfix
 * MXCryptoStore: Keep current store version after resetting data to avoid dead state on an initial sync ([#4594](https://github.com/vector-im/element-ios/issues/4594)).
 * Prevent session pause until reject/hangup event is sent ([#4612](https://github.com/vector-im/element-ios/issues/4612)).
 * Only post identity server changed notification if the server actually changed.
 * Fix audio routing issues for Bluetooth devices ([#4622](https://github.com/vector-im/element-ios/issues/4622)).

Others

 * Separated CI jobs into individual actions

## Changes in 0.19.5 (2021-07-22)

🙌 Improvements

 * MXRoomSummary: Cache local unread event count ([#4585](https://github.com/vector-im/element-ios/issues/4585)).

🐛 Bugfix
 * MXCryptoStore: Use UI background task to make sure that write operations complete ([#4579](https://github.com/vector-im/element-ios/issues/4579)).

## Changes in 0.19.4 (2021-07-15)

🙌 Improvements

 * MXTools: Default to 1080p when converting a video ([#4478](https://github.com/vector-im/element-ios/issues/4478)).
 * MXEvent: add support for voice messages
 * MXRoom: Add support for sending slow motion videos using AVAsset ([#4483](https://github.com/vector-im/element-ios/issues/4483)).
 * MXSendReplyEventStringsLocalizable: Added senderSentAVoiceMessage property

🐛 Bugfix
 * Fix QR self verification with QR code (#1147)
 * VoIP: Check for virtual users on attended call transfers.
 * MXBackgroundCryptoStore: Remove read-only Realm and try again if Olm account not found in crypto store ([#4534](https://github.com/vector-im/element-ios/issues/4534)).

⚠️ API Changes

 * MXSDKOptions: Add videoConversionPresetName to customise video conversion quality.
 * MXRoom: Added duration and sample parameters on the sendVoiceMessage method ([#4090](https://github.com/vector-im/element-ios/issues/4090))

Others

 * Fixed a nullability warning and some header warnings.


## Changes in 0.19.3 (2021-06-30)

🙌 Improvements

 * MXDehydrationService: Support full rehydration feature ([#1117](https://github.com/vector-im/element-ios/issues/1117)).
 * MXSDKOptions: Add wellknownDomainUrl to customise the domain for wellknown ([##4489](https://github.com/vector-im/element-ios/issues/#4489)).
 * MXSession: Refresh homeserverWellknown on every start.
 * MXRoom: Added support for posting `m.image`s with BlurHash (MSC 2448).
 * VoIP: Implement bridged version for call transfers.
 * VoIP: Implement MXiOSAudioOutputRouter.

🐛 Bugfix
 * 

⚠️ API Changes

 * MXCall: `audioToSpeaker` property removed. Use `audioOutputRouter` instead.
 * MXCallStackCall: `audioToSpeaker` property removed. Audio routing should be handled high-level.

## Changes in 0.19.2 (2021-06-24)

🙌 Improvements

 * MXSDKOptions: Introduce an option to auto-accept room invites.

🐛 Bugfix
 * MXSession.homeserverWellknown was no more computed since 0.19.0.

## Changes in 0.19.1 (2021-06-21)

🙌 Improvements

 * MXRoomLastMessage: Use MXKeyProvider methods to encrypt/decrypt last message dictionary.
 * VoIP: Change hold direction to send-only.
 * Encrypted Media: Remove redundant and undocumented mimetype fields from encrypted attachments ([#4303](https://github.com/vector-im/element-ios/issues/4303)).
 * MXRecoveryService: Expose checkPrivateKey to validate a private key ([#4430](https://github.com/vector-im/element-ios/issues/4430)).
 * VoIP: Use headphones and Bluetooth devices when available for calls.

🐛 Bugfix
 * MXSession: Fix app that can fail to resume ([#4417](https://github.com/vector-im/element-ios/issues/4417)).
 * MXRealmCryptoStore: Run migration once before opening read-only Realms ([#4418](https://github.com/vector-im/element-ios/issues/4418)).
 * VoIP: Handle offers when peer connection is stable ([#4421](https://github.com/vector-im/element-ios/issues/4421)).
 * MXEventTimeline: Fix regression on clear cache where the last message of an encrypted room is not encrypted.
 * MXBackgroundSyncService: Make credentials public ([#3695](https://github.com/vector-im/element-ios/issues/3695)).
 * MXCredentials: Implement equatable & hashable methods ([#3695](https://github.com/vector-im/element-ios/issues/3695)).

⚠️ API Changes

 * MXRoomSummary: `lastMessageEvent` property removed for performance reasons ([#4360](https://github.com/vector-im/element-ios/issues/4360)).
 * MXRoomSummary: All properties about lastMessage are moved into `lastMessage` property.
 * MXSession: Does not compute anymore last events for every room summaries by default. Use -[MXSession eventWithEventId:inRoom:success:failure:] method to load the last event for a room summary.
 * MXRoom: Added method for seding voice messages ([#4090](https://github.com/vector-im/element-ios/issues/4090)).
 * MXMediaManager: Added `mimeType` param to download encrypted media methods ([#4303](https://github.com/vector-im/element-ios/issues/4303)).
 * MXEncryptedContentFile: `mimetype` parameter removed ([#4303](https://github.com/vector-im/element-ios/issues/4303)).
 * MXEncryptedAttachments: `mimetype` parameters removed from encrypt attachment methods ([#4303](https://github.com/vector-im/element-ios/issues/4303)).

🧱 Build

 * build.sh: Include debug symbols when building XCFramework 

## Changes in 0.19.0 (2021-06-02)

✨ Features

 * Spaces: Support Space room type ([#4069](https://github.com/vector-im/element-ios/issues/4069)).

🙌 Improvements

 * MXSession: Cache initial sync response until it is fully handled ([#4317](https://github.com/vector-im/element-ios/issues/4317)).
 * MXStore: New commit method accepting a completion block.
 * MXCrypto: Decrypt events asynchronously and no more on the main thread )([#4306](https://github.com/vector-im/element-ios/issues/4306)).
 * MXSession: Add the decryptEvents method to decypt a bunch of events asynchronously.
 * MXSession: Make the eventWithEventId method decrypt the event if needed.
 * MXEventTimeline: Add NSCopying implementation so that another pagination can be done on the same set of data.
 * MXCrypto: eventDeviceInfo: Do not synchronise anymore the operation with the decryption queue.
 * MXRoomSummary: Improve reset resetLastMessage to avoid pagination loop and to limit number of decryptions.
 * MXSession: Limit the number of decryptions when processing an initial sync ([#4307](https://github.com/vector-im/element-ios/issues/4307)).
 * Adapt sync response models to new sync API ([#4309](https://github.com/vector-im/element-ios/issues/4309)).
 * MXKeyBackup: Do not reset the backup if forceRefresh() is called too early.
 * Pod: Update Realm to 10.7.6.
 * Pod: Update Jitsi to 3.5.0.
 * Pod: Update OLMKit to 3.2.4.
 * MXRealmCryptoStore: Use Realm instances as read-only in background store ([#4352](https://github.com/vector-im/element-ios/issues/4352)).
 * MXLog: centralised logging facility, use everywhere instead of NSLog ([#4351](https://github.com/vector-im/element-ios/issues/4351)).

🐛 Bugfix
 * MXRoomSummary: Fix decryption of the last message when it is edited ([#4322](https://github.com/vector-im/element-ios/issues/4322)).
 * MXCall: Check remote partyId for select_answer events ([#4337](https://github.com/vector-im/element-ios/issues/4337)).
 * MXSession: Fix used initial sync cache.

⚠️ API Changes

 * MXRoom: MXRoom.outgoingMessages does not decrypt messages anymore. Use MXSession.decryptEvents to get decrypted events.
 * MXSession: [MXSession decryptEvent:inTimeline:] is deprecated, use [MXSession decryptEvents:inTimeline:onComplete:] instead.
 * MXCrypto: [MXCrypto decryptEvent:inTimeline:] is deprecated, use [MXCrypto decryptEvents:inTimeline:onComplete:] instead.
 * MXCrypto: [MXCrypto hasKeysToDecryptEvent:] is now asynchronous.

## Changes in 0.18.12 (2021-05-12)

🙌 Improvements

 * MXPushGatewayRestClient: Add timeout param to the HTTP method.

🐛 Bugfix
 * MXRoomCreateContent: Fix room type JSON key.

## Changes in 0.18.11 (2021-05-07)

🙌 Improvements

 * MXCallKitAdapter: Update incoming calls if answered from application UI.
 * MXFileStore: Logs all files when a data corruption is detected (to track vector-im/element-ios/issues/4921).
 * MXCallManager: Fix call transfers flow for all types of transfers.
 * VoIP: Implement asserted identity for calls: MSC3086 (matrix-org/matrix-doc/pull/3086).

🐛 Bugfix
 * MXTools: Fix bad linkification of matrix alias and URL ([#4258](https://github.com/vector-im/element-ios/issues/4258)).
 * MXRoomSummary: Fix roomType property deserialization issue.
 * MXCall: Disable call transferee capability & fix call transfer feature check.

⚠️ API Changes

 * Spaces and room type: Remove all MSC1772 JSON key prefixes and use stable ones.

🧱 Build

 * Tests: Use UnitTests suffix for unit tests classes.
 * Tests: Cut some existing tests to separate unit tests and integration tests.
 * Tests: Create 4 test plans for the macOS target: AllTests, AllTestsWithSanitizers, UnitTests and UnitTestsWithSanitizers.
 * GH Actions: Run unit tests on every PR and develop branch update.
 * GH Actions: Run integration tests nightly on develop using last Synapse release.

## Changes in 0.18.10 (2021-04-22)

🙌 Improvements

 * MXHTTPOperation: Expose the HTTP response ([#4206](https://github.com/vector-im/element-ios/issues/4206)).
 * MXRoomPowerLevels: Handle undefined values and add init with default spec values.
 * MXRoomCreationParameters: Add roomType and powerLevelContentOverride properties. Add initial state events update method.
 * MXResponse: Add convenient uncurry method to convert a Swift method into Objective-C.
 * Add MXRoomInitialStateEventBuilder that enables to build initial state events.

🐛 Bugfix
 * MXCrypto: Disable optimisation on room members list to make sure we share keys to all ([#3807](https://github.com/vector-im/element-ios/issues/3807)).

## Changes in 0.18.9 (2021-04-16)

🐛 Bugfix
* Notifications: Fix sender display name that can miss ([##4222](https://github.com/vector-im/element-ios/issues/#4222)). 

## Changes in 0.18.8 (2021-04-14)

🐛 Bugfix
 * MXSession: Fix deadlock regression in resume() ([#4202](https://github.com/vector-im/element-ios/issues/4202)).
 * MXRoomMembers: Fix wrong view of room members when paginating ([#4204](https://github.com/vector-im/element-ios/issues/4204)).

## Changes in 0.18.7 (2021-04-09)

🙌 Improvements

 * Create secret storage with a given private key ([#4189](https://github.com/vector-im/element-ios/issues/4189)).
 * MXAsyncTaskQueue: New tool to run asynchronous tasks one at a time.
 * MXRestClient: Add the dehydratedDevice() method to get the dehydrated device data ([#4194](https://github.com/vector-im/element-ios/issues/4194)).

🐛 Bugfix
 * Notifications: Fix background sync out of memory (vector-im/element-ios#3957).
 * Notifications: MXBackgroundService: Keep all cached sync responses until there are processed by MXSession (vector-im/element-ios#4074).
 * Remove padding from base64 encoded `iv` value ([#4172](https://github.com/vector-im/element-ios/issues/4172)).
 * Check for null before changing a user's displayname or avatar URL based on an m.room.member event.

## Changes in 0.18.6 (2021-03-24)

🙌 Improvements

 * Support room type as described in MSC1840 ([#4050](https://github.com/vector-im/element-ios/issues/4050)).
 * Pods: Update JitsiMeetSDK, OHHTTPStubs, Realm ([#4120](https://github.com/vector-im/element-ios/issues/4120)).
 * MXCrypto: Do not load room members in e2e rooms after an initial sync.
 * MXRoomSummary: Add enableTrustTracking() to compute and maintain trust value for the given room ([#4115](https://github.com/vector-im/element-ios/issues/4115)).
 * VoIP: Virtual rooms implementation.
 * MXCrypto: Split network request `/keys/query` into smaller requests (250 users max) ([#4123](https://github.com/vector-im/element-ios/issues/4123)).

🐛 Bugfix
 * MXDeviceList: Fix memory leak.
 * MXDeviceListOperation: Fix memory leak.
 * MXRoomState/MXRoomMembers: Fix memory leak and copying.
 * MXKeyBackup: Add sanity checks to avoid crashes ([#4113](https://github.com/vector-im/element-ios/issues/4113)).
 * MXTools: Avoid releasing null pointer to fix crash on M1 simulator ([#4140](https://github.com/vector-im/element-ios/issues/4140))

🧱 Build

 * build.sh: Support passing CFBundleShortVersionString and CFBundleVersion when building an xcframework.
 * build.sh: When building an xcframework, zip the binary ready for distribution.

Others

 * GitHub Actions: Run pod lib lint

## Changes in 0.18.5 (2021-03-11)

🐛 Bugfix
 * VoIP: Fix too quick call answer failure ([#4109](https://github.com/vector-im/element-ios/issues/4109)).
 * Crypto: Duplicate message index after using the share extension (vector-im/element-ios#4104)

Others

 * Ignore event editors other than the original sender.

## Changes in 0.18.4 (2021-03-03)

🐛 Bugfix
 * MXCrossSigning: Fix setupWithPassword method crash when a grace period is enabled (Fix vector-im/element-ios#4099).

## Changes in 0.18.3 (2021-02-26)

🐛 Bugfix
 * Fix connection state & ice connection failures ([#4039](https://github.com/vector-im/element-ios/issues/4039)).

## Changes in 0.18.2 (2021-02-24)

🙌 Improvements

 * MXRoomState: Add creator user id property.
 * MXRoomSummary: Add creator user id property.
 * MXCrypto: Encrypt cached e2ee data using an external pickle key (vector-im/element-ios#3867).
 * Crypto: Upgrade OLMKit(3.2.2).

🐛 Bugfix
 * Fix calls from my own users ([#4031](https://github.com/vector-im/element-ios/issues/4031)).

🧱 Build

 * build.sh: Add xcframework argument to build a universal MatrixSDK.xcframework
 * MatrixSDKTests-macOS: Remove tests from macOS profile and archive builds to match iOS.

## Changes in 0.18.1 (2021-02-12)

🙌 Improvements

 * MXCredentials: Expose additional server login response data ([#4024](https://github.com/vector-im/element-ios/issues/4024)).

🐛 Bugfix
 * Support VP8/VP9 codecs in video calls ([#4026](https://github.com/vector-im/element-ios/issues/4026)).
 * Handle call rejects from other devices ([#4030](https://github.com/vector-im/element-ios/issues/4030)).

## Changes in 0.18.0 (2021-02-11)

🙌 Improvements

 * Pods: Update JitsiMeetSDK to 3.1.0.
 * Send VoIP analytics events ([#3855](https://github.com/vector-im/element-ios/issues/3855)).
 * Add hold support for CallKit calls ([#3834](https://github.com/vector-im/element-ios/issues/3834)).
 * Fix video call with web ([#3862](https://github.com/vector-im/element-ios/issues/3862)).
 * VoIP: Call transfers initiation ([#3872](https://github.com/vector-im/element-ios/issues/3872)).
 * VoIP: DTMF support in calls ([#3929](https://github.com/vector-im/element-ios/issues/3929)).

🐛 Bugfix
 * MXRoomSummary: directUserId may be missing (null) for a direct chat if it was joined on another device.

Others

 * README: Fix a couple of typos and improve consistency of the README.

## Changes in 0.17.11 (2021-02-03)

🙌 Improvements

 * MXMemory: New utility class to track memory usage.
 * MXRealmCryptoStore: Compact Realm DB only once, at the first usage.
 * MXLoginSSOIdentityProvider: Add new `brand` field as described in MSC2858 ([#3980](https://github.com/vector-im/element-ios/issues/3980)).
 * MXSession: Make `handleBackgroundSyncCacheIfRequiredWithCompletion` method public ([#3986](https://github.com/vector-im/element-ios/issues/3986)).
 * MXLogger: Remove log files that are no more part of the rotation.
 * MXLogger: Add an option to limit logs size ([##3903](https://github.com/vector-im/element-ios/issues/#3903)).
 * MXRestClient: Handle grace period in `authSessionForRequestWithMethod`.

🐛 Bugfix
 * Background Sync: Use autoreleasepool to limit RAM usage ([#3957](https://github.com/vector-im/element-ios/issues/3957)).
 * Background Sync: Do not compact Realm DB from background process.
 * MX3PidAddManager: Use a non empty client_secret to discover /account/3pid/add flows ([#3966](https://github.com/vector-im/element-ios/issues/3966)).
 * VoIP: Fix camera indicator when video call answered elsewhere ([#3971](https://github.com/vector-im/element-ios/issues/3971)).

## Changes in 0.17.10 (2021-01-27)

🙌 Improvements

 * MXRealmCryptoStore: New implementation of deleteStoreWithCredentials that does not need to open the realm DB.
 * MXRealmCryptoStore: store chain index of shared outbound group sessions to improve re-share session keys

🐛 Bugfix
 * MXBackgroundSyncService: Clear the bg sync crypto db if needed ([#3956](https://github.com/vector-im/element-ios/issues/3956)).
 * MXCrypto: Add a workaround when the megolm key is not shared to all members ([#3807](https://github.com/vector-im/element-ios/issues/3807)).

## Changes in 0.17.9 (2021-01-18)

🐛 Bugfix
 * MXEvent: Fix a regression on edits and replies in e2ee rooms ([#3944](https://github.com/vector-im/element-ios/issues/3944)).

## Changes in 0.17.8 (2021-01-15)

🐛 Bugfix
 * Avoid calling background task expiration handlers in app extensions ([#3935](https://github.com/vector-im/element-ios/issues/3935)).

## Changes in 0.17.7 (2021-01-14)

🙌 Improvements

 * MXCrypto: Store megolm outbound session to improve send time of first message after app launch ([##3904](https://github.com/vector-im/element-ios/issues/#3904)).
 * MXUIKitApplicationStateService: Add this service to track UIKit application state.

🐛 Bugfix
 * MXBackgroundSyncService: Fix `m.buddy` to-device event crashes ([#3889](https://github.com/vector-im/element-ios/issues/3889)).
 * MXBackgroundSyncService: Fix app deadlock created between the app process and the notification service extension process ([#3906](https://github.com/vector-im/element-ios/issues/3906)).
 * MXUIKitBackgroundTask: Avoid thread switching when creating a background task to keep threading model ([#3917](https://github.com/vector-im/element-ios/issues/3917)).

⚠️ API Changes

 * MXLoginSSOFlow: Use unstable identity providers field while the MSC2858 is not approved.

## Changes in 0.17.6 (2020-12-18)

🐛 Bugfix
 * MXUIKitBackgroundTask: Handle invalid identifier case, introduce a threshold for background time remaining, set expiration handler in initAndStart.

## Changes in 0.17.5 (2020-12-16)

✨ Features

 * Added MXKeyProvider to enable data encryption using keys given by client application (#3866)

🙌 Improvements

 * MXTaggedEvents: Expose "m.tagged_events" according to [MSC2437](https://github.com/matrix-org/matrix-doc/pull/2437).
 * Login flow: Add MXLoginSSOFlow to support multiple SSO Identity Providers ([MSC2858](https://github.com/matrix-org/matrix-doc/pull/2858)) ([#3846](https://github.com/vector-im/element-ios/issues/3846)).

🐛 Bugfix
 * MXRestClient: Fix the format of the request body when querying device keys for users (vector-im/element-ios#3539).
 * MXRoomSummary: Fix crash when decoding lastMessageData ([#3879](https://github.com/vector-im/element-ios/issues/3879)).

⚠️ API Changes

 *

## Changes in 0.17.4 (2020-12-02)

✨ Features

 * Added MXAes encryption helper class ([#3833](https://github.com/vector-im/element-ios/issues/3833)).

🙌 Improvements

 * Pods: Update JitsiMeetSDK to 2.11.0 to be able to build using Xcode 12.2 ([#3808](https://github.com/vector-im/element-ios/issues/3808)).
 * Pods: Update Realm to 10.1.4 to be able to `pod lib lint` using Xcode 12.2 ([#3808](https://github.com/vector-im/element-ios/issues/3808)).

🐛 Bugfix
 * MXSession: Fix a race conditions that prevented MXSession from actually being paused.
 * MXSession: Make sure the resume method call its completion callback.

⚠️ API Changes

 * MXRoomSummary: Add a property to indicate room membership transition state.

## Changes in 0.17.3 (2020-11-24)

🙌 Improvements

 * MXCrypto: Introduce MXCryptoVersion and MXCryptoMigration to manage logical migration between MXCrypto module updates.

🐛 Bugfix
 * MXOlmDevice: Make usage of libolm data process-safe (vector-im/element-ios/3817).
 * MXCrypto: Use MXCryptoMigration to purge all one time keys because some may be bad (vector-im/element-ios/3818).

## Changes in 0.17.2 (2020-11-17)

🐛 Bugfix
 * Podspec: Fix arm64 simulator issue with JitsiMeetSDK.
 * Realm: Stick on 10.1.2 because the CI cannot build.

## Changes in 0.17.1 (2020-11-17)

🐛 Bugfix
 * 

⚠️ API Changes

 * Update Realm to 10.2.1 and CocoaPods to 1.10.0.
 * CocoaPods 1.10.0 is mandatory.

 
 ## Changes in 0.17.0 (2020-11-13)

🙌 Improvements

 * MXAnalyticsDelegate: Make it fully agnostic on tracked data.
 * MXRealmCryptoStore: Compact DB files before getting out of memory error (vector-im/element-ios/3792).
 * Tools: Add MXProfiler to track some performance.

🐛 Bugfix
 * MXSession: Fix log for next stream token.
 * MXThrottler: Dispatch the block on the correct queue. This will prevent unexpected loops (vector-im/element-ios/3778).
 * Update JitsiMeetSDK to 2.10.2 (vector-im/element-ios/3712).

⚠️ API Changes

 * Xcode 12 is now mandatory for using the JingleCallStack sub pod.


## Changes in 0.16.20 (2020-10-27)

🙌 Improvements

 * Update GZIP to 1.3.0 (vector-im/element-ios/3570).
 * Update Realm to 5.4.8 (vector-im/element-ios/3570).
 * Update JitsiMeetSDK to 2.10.0 (vector-im/element-ios/3570).
 * Introduce MXBackgroundSyncService and helper classes ([#3579](https://github.com/vector-im/element-ios/issues/3579)).

🐛 Bugfix
 * 

⚠️ API Changes

 * SwiftSupport subspec removed. Swift is default now.

## Changes in 0.16.19 (2020-10-14)

🙌 Improvements

 * MXCrossSigning: Detect when cross-signing keys have been reset and send MXCrossSigningDidChangeCrossSigningKeysNotification.
 * MXSession: Introduce handleSyncResponse method to process sync responses from out of the session ([#3579](https://github.com/vector-im/element-ios/issues/3579)).
 * MXJSONModels: Implement JSONDictionary methods for MXSyncResponse and inner classes ([#3579](https://github.com/vector-im/element-ios/issues/3579)).

🐛 Bugfix
 * Tests: Fix testMXDeviceListDidUpdateUsersDevicesNotification.
 * MXCrossSigning: Trust cross-signing because we locally trust the device that created it.

## Changes in 0.16.18 (2020-10-13)

🐛 Bugfix
 * Fix nonstring msgtyped room messages, by removing msgtype from the wire and prev contents. 

## Changes in 0.16.17 (2020-10-09)

🙌 Improvements

 * MXCrypto: Add hasKeysToDecryptEvent method.

🐛 Bugfix
 * MXCrypto: Reset OTKs when some IDs are already used (https://github.com/vector-im/element-ios/issues/3721).
 * MXCrypto: Send MXCrossSigningMyUserDidSignInOnNewDeviceNotification and MXDeviceListDidUpdateUsersDevicesNotification on the main thread.
 * MXCrossSigning: Do not send MXCrossSigningMyUserDidSignInOnNewDeviceNotification again if the device has been verified from another thread.
 
## Changes in 0.16.16 (2020-09-30)

Features:
 * 

Improvements:
 * 

Bugfix:
 * MXBase64Tools: Make sure the SDK decode padded and unpadded base64 strings like other platforms (vector-im/riot-ios/issues/3667).
 * SSSS: Use unpadded base64 for secrets data (vector-im/riot-ios/issues/3669).
 * MXSession: Fix `refreshHomeserverWellknown` method not reading Well-Known from the homeserver domain ([#3653](https://github.com/vector-im/element-ios/issues/3653)).

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.15 (2020-09-03)

Features:
 * 

Improvements:
 * MXPushData: Implement JSONDictionary (vector-im/riot-ios/issues/3577).
 * MXFileStore: Make loadMetaData more robust.

Bugfix:
 * 

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.14 (2020-08-28)

Features:
 * 

Improvements:
 * 

Bugfix:
 * MXCredentials: Try to guess homeserver in credentials when not provided in wellknown ([#3448](https://github.com/vector-im/element-ios/issues/3448)). 

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.13 (2020-08-25)

Features:
 * 

Improvements:
 * Introduce handleCallEvent on MXCallManager. 

Bugfix:
 * Some room members count are wrong after clearing the cache

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.12 (2020-08-19)

Features:
 * 

Improvements:
 * Introduce HTTPAdditionalHeaders in MXSDKOptions.

Bugfix:
 * 

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.11 (2020-08-13)

Features:
 * Introduce MXPushGatewayRestClient (part of vector-im/element-ios#3452). 

Improvements:
 * 

Bugfix:
 * 

API Change:
 * Drop SwiftMatrixSDK (vector-im/element-ios#3518).

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.10 (2020-08-07)

Features:
 * 

Improvements:
 * 

Bugfix:
 * 

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * Fix "fastlane ios test" and generate html report.
 * Make tests crash instantly if no local synapse is running.
 * Do not use anymore NSAssert in tests.

## Changes in 0.16.9 (2020-08-05)

Features:
 * 

Improvements:
 * 

Bugfix:
 * 

API Change:
 * 

Translations:
 * 

Others:
 * 

Build:
 * 

Test:
 * 

## Changes in 0.16.8 (2020-07-28)
================================================

Improvements:
 * MXSession: Log next sync token.
 
Bug fix:
 * MXRoom: Reply: Use formatted body only if the message content format is known.
 * MXRoom: Reply: Avoid nested mx-reply tags.

## Changes in Matrix iOS SDK in 0.16.7 (2020-07-13)
================================================

Bug fix:
 * MXCreateRoomReponse: Remove undocumented roomAlias property (vector-im/riot-ios/issues/3300).
 * MXPushRuleSenderNotificationPermissionConditionChecker & MXPushRuleRoomMemberCountConditionChecker: Remove redundant room check (vector-im/riot-ios/issues/3354).
 * MXSDKOptions: Introduce enableKeyBackupWhenStartingMXCrypto option (vector-im/riot-ios/issues/3371).

## Changes in Matrix iOS SDK in 0.16.6 (2020-06-30)
================================================

Improvements:
 * MXCrypto: Only create one olm session at a time per device (vector-im/riot-ios/issues/2331).
 * MXCrossSigning: Add the bootstrapWithAuthParams method.
 * MXRecoveryService: Create this service to manage keys we want to store in SSSS.
 * MXRecoveryService: Add deleteRecovery.
 * MXRecoveryService: Add options to create and delete key backup automatically (vector-im/riot-ios/issues/3361).
 * MXSecretStorage: Add options to remove secrets and SSSS. 
 * MXWellKnown: Add JSONDictionary implementation to return original and extended data.
 * MXCrossSigning: Gossip the master key (vector-im/riot-ios/issues/3346).
 * MXRestClient: Add authSessionForRequestWithMethod to get an auth session for any requests.

Bug fix:
 * MXSecretShareManager: Fix crash in cancelRequestWithRequestId (vector-im/riot-ios/issues/3272).
 * MXIdentityService: Fix crash in handleHTTPClientError (vector-im/riot-ios/issues/3273).
 * MXSession: Add ignoreSessionState to backgroundSync method.
 * MXDeviceList: Fix crash in refreshOutdatedDeviceLists (vector-im/riot-ios/issues/3118).
 * MXDeviceListOperationsPool: Fix current device verification status put in MXDeviceUnknown instead of MXDeviceVerified (vector-im/riot-ios/issues/3343).

API break:
 * MXCrossSigning: Removed MXCrossSigningStateCanCrossSignAsynchronously.

## Changes in Matrix iOS SDK in 0.16.5 (2020-05-18)
================================================

Improvements:
 * MXSession: Update account data as soon as the endpoint returns.
 * MXSecretStorage: Add this class to support SSSS ([MSC1946(]https://github.com/matrix-org/matrix-doc/pull/1946).
 * SAS verification: Support new key agreement.
 * MatrixSDK/JingleCallStack: Update Jitsi Meet dependency to ~> 2.8.1 and upgrade the minimal iOS version to 11.0 because the Jitsi Meet framework requires it.
 * MXCallAudioSessionConfigurator: Add `configureAudioSessionAfterCallEnds` method.
 * MXCallKitAdapter: Move incoming audio configuration in `performAnswerCallAction` as recommended. Handle audio session configuration after call ends.
 
 Bug fix:
 * MXJingleCallAudioSessionConfigurator: Handle RTCAudioSession manually, enable audio when needed. Fix outgoing audio issue after consecutive incoming calls.

## Changes in Matrix iOS SDK in 0.16.4 (2020-05-07)
================================================

Improvements:
 * Minimal version for iOS is now 9.0.
 * Pod: Update AFNetworking version (#793).
 * Pod: Update Realm and OHTTPStubs.

## Changes in Matrix iOS SDK in 0.16.3 (2020-05-07)
================================================

Improvements:
 * MXCrypto: Allow to verify a device again to request private keys again from it.
 * Secrets: Validate received private keys for cross-signing and key backup before using them (vector-im/riot-ios/issues/3201).

## Changes in Matrix iOS SDK in 0.16.2 (2020-04-30)
================================================

Improvements:
 * Cross-signing: Make key gossip requests when the other device sent m.key.verification.done (vector-im/riot-ios/issues/3163).

Bug fix:
 * MXEventTimeline: Fix crash in paginate:.
 * MXSession: Fix crash in runNextDirectRoomOperation.

Doc fix:
 * Update the CONTRIBUTING.rst to point to correct file.

## Changes in Matrix iOS SDK in 0.16.1 (2020-04-24)
================================================

Improvements:
 * MXHTTPClient: Log HTTP requests methods.
 * MXCrypto: Make trustLevelSummaryForUserIds async (vector-im/riot-ios/issues/3126).
 * MXJingleCallAudioSessionConfigurator: Remove workaround since it is no longer needed (PR #815).

Bug fix:
 * Fix race condition in MXSecretShareManager (vector-im/riot-ios/issues/3123).
 * Too much MXDeviceInfoTrustLevelDidChangeNotification and MXCrossSigningInfoTrustLevelDidChangeNotification (vector-im/riot-ios/issues/3121).
 * VoiP: Fix remote ice candidates being added before remote description is setup (vector-im/riot-ios/issues/1784).
 * MXDeviceListOperationsPool: Post MXDeviceListDidUpdateUsersDevicesNotification notification only for new changes never seen before (vector-im/riot-ios/issues/3120).
 * MXIdentityService: Fix registration by email and all IS services by fixing Open Id token.

API break:
 * MXCrypto: trustLevelSummaryForUserIds: is now async.

## Changes in Matrix iOS SDK in 0.16.0 (2020-04-17)
================================================

Improvements:
 * Cross-Signing: Add a new module, MXCrossSigning, to handle device cross-signing (vector-im/riot-ios/issues/2890).
 * Verification by DM: Support QR code (vector-im/riot-ios/issues/2921).
 * MXCrypto: Change the threading model to make [MXCrypto decryptEvent:] less blocking.
 * MXCrypto: Restart broken Olm sessions ([MSC1719](https://github.com/matrix-org/matrix-doc/pull/1719)) (vector-im/riot-ios/issues/2129).
 * MXCrypto: Expose devicesForUser.
 * MXCrypto: the `setDeviceVerification` method now downloads all user's devices if the device is not yet known.
 * MXCrypto: Add the option to disable sending key share requests (`[MXCrypto setOutgoingKeyRequestsEnabled:]`).
 * MXRestClient: Use r0 APIs for crypto endpoints (PR #826).
 * MXDeviceList: Post `MXDeviceListDidUpdateUsersDevicesNotification` notification when users devices list are updated.
 * MXSession: Add credentials, myUserId and myDeviceId shorcuts.
 * MXSession: Add createRoomWithParameters with a MXRoomCreationParameters model class.
 * MXRoom: Add a method to retrieve trusted members count in an encrypted room.
 * MXRoomCreationParameters: Support the initial_state parameter and allow e2e on room creation (vector-im/riot-ios/issues/2943).
 * MXRoomSummary: Add the trust property to indicate trust in other users and devices in the room (vector-im/riot-ios/issues/2906).
 * Aggregations: Implement m.reference aggregations, aka thread ([MSC1849](https://github.com/matrix-org/matrix-doc/blob/matthew/msc1849/proposals/1849-aggregations.md)).
 * MXStore: Add a method to get related events for a specific event.
 * MXPublicRoom: Add canonical alias property.
 * MXLogger: Add a parameter to indicate the number of log files.
 * MXThrottler: Add this tool class to throttle actions.
 * Make enums conform to `Equatable`/`Hashable` where applicable.

Bug fix:
 * MXEventType: Fix Swift refinement.
 * MXCrypto: Fix users keys download that can fail in some condition
 * MXCryptoStore does not store device.algorithm (https://github.com/vector-im/riot-ios/issues/2896).

API break:
 * MXCrypto: Rename MXDeviceVerificationManager to MXKeyVerificationManager.
 * MXCrypto: the `downloadKeys` method now returns users cross-signing keys.
 * MXDeviceInfo: the `verified` property has been replaced by `trustLevel`.
 * MXSession & MXRestClient: the `createRoom` method with a long list of parameters
   has been replaced by `createRoomWithParameters`.

## Changes in Matrix iOS SDK in 0.15.2 (2019-12-05)
===============================================

Improvements:
 * Add macOS target with unit tests.

Bug fix:
 * MXCallAudioSessionConfigurator: Fix compilation issue with macOS.
 * MXRoomSummary: Fix potential crash when `_lastMessageOthers` is null.
 
API break:
 * MXCallAudioSessionConfigurator: Now unavailable for macOS.

## Changes in Matrix iOS SDK in 0.15.1 (2019-12-04)
===============================================

Improvements:
 * Well-known: Expose "m.integrations" according to [MSC1957](https://github.com/matrix-org/matrix-doc/pull/1957) (vector-im/riot-ios#2815).
 * MXSession: Expose and store homeserverWellknown.
 * SwiftMatrixSDK: Add missing start(withSyncFilter:) refinement to MXSession.swift.
 
Bug fix:
 * MXIdentityServerRestClient: Match registration endpoint to the IS r0.3.0 spec (vector-im/riot-ios#2824).

## Changes in Matrix iOS SDK in 0.15.0 (2019-11-06)
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

## Changes in Matrix iOS SDK in 0.14.0 (2019-10-11)
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

## Changes in Matrix iOS SDK in 0.13.1 (2019-08-08)
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

## Changes in Matrix iOS SDK in 0.13.0 (2019-07-16)
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

## Changes in Matrix iOS SDK in 0.12.5 (2019-05-03)
===============================================

Improvements:
 * Crypto: Handle partially-shared sessions better (vector-im/riot-ios/issues/2320).
 * Crypto: Support Interaction Device Verification (vector-im/riot-ios/issues/2322).
 * MXSession: add a global notification posted when the account data are updated from the homeserver.
 * VoIP: Use WebRTC framework included in Jitsi Meet SDK (vector-im/riot-ios/issues/1483).

Bug Fix:
 * MXRoomSummaryUpdater: Fix `MXRoomSummary.hiddenFromUser` property not being saved when associated room become tombstoned (vector-im/riot-ios/issues/2148).
 * MXFileStore not loaded with 0 rooms, thanks to @asydorov (PR #647).

## Changes in Matrix iOS SDK in 0.12.4 (2019-03-21)
===============================================

Bug Fix:
 * MXRestClient: Fix file upload with filename containing whitespace (PR #645).

## Changes in Matrix iOS SDK in 0.12.3 (2019-03-08)
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

## Changes in Matrix iOS SDK in 0.12.2 (2019-02-15)
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

## Changes in Matrix iOS SDK in 0.12.1 (2019-01-04)
===============================================

Improvements:
 * MXCrypto: Use the last olm session that got a message (vector-im/riot-ios/issues/2128).
 * MXScanManager: Support the encrypted body (the request body is now encrypted by default using the server public key).
 * MXMediaManager: Support the encrypted body.

Bug Fix:
 * MXCryptoStore: Stop duplicating devices in the store (vector-im/riot-ios/issues/2132).
 * MXPeekingRoom: the room preview is broken (vector-im/riot-ios/issues/2126).

## Changes in Matrix iOS SDK in 0.12.0 (2018-12-06)
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

## Changes in Matrix iOS SDK in 0.11.6 (2018-10-31)
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

## Changes in Matrix iOS SDK in 0.11.5 (2018-10-05)
===============================================

Improvements:
 * MXSession: Add eventWithEventId:inRoom: method.
 * MXRoomState: Add pinnedEvents to list pinned events ids.
 * MXServerNotices: Add this class to get notices from the user homeserver.

## Changes in Matrix iOS SDK in 0.11.4 (2018-09-26)
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

## Changes in Matrix iOS SDK in 0.11.3 (2018-08-27)
===============================================

Bug fix:
 * MXJSONModel: Manage `m.server_notice` empty tag sent due to a bug server side (PR #556).

## Changes in Matrix iOS SDK in 0.11.2 (2018-08-24)
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

## Changes in Matrix iOS SDK in 0.11.1 (2018-08-17)
===============================================

Improvements:
 * Tests: Add DirectRoomTests to test direct rooms management.

Bug fix:
 * Direct rooms can be lost on an initial /sync (vector-im/riot-ios/issues/1983).
 * Fix possible race conditions in direct rooms management.
 * Avoid to create an empty filter on each [MXSession start:]

## Changes in Matrix iOS SDK in 0.11.0 (2018-08-10)
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

## Changes in Matrix iOS SDK in 0.10.12 (2018-05-31)
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

## Changes in Matrix iOS SDK in 0.10.11 (2018-05-31)
=============================================== 

Improvements:
 * MXSession: Add setAccountData.
 * MXSession: Add account deactivation
 * MKTools: Create MXWeakify & MXStrongifyAndReturnIfNil

## Changes in Matrix iOS SDK in 0.10.10 (2018-05-23)
=============================================== 

Improvements:
 * MXTools: Regex optimisation: Cache regex of [MXTools stripNewlineCharacters:].
 * MXSession: Make MXAccountData member public.
 * Send Stickers: Manage local echo for sticker (vector-im/riot-ios#1860).
 * GDPR: Handle M_CONSENT_NOT_GIVEN error (vector-im/riot-ios#1871).

Bug fixes:
 * Groups: Avoid flair to make requests in loop in case the HS returns an empty response for `/publicised_groups` (vector-im/riot-ios#1869).

## Changes in Matrix iOS SDK in 0.10.9 (2018-04-23)
=============================================== 

Bug fixes:
 * Regression: Sending a photo from the photo library causes a crash.

## Changes in Matrix iOS SDK in 0.10.8 (2018-04-20)
=============================================== 

Improvements:
 * Pod: Update realm version (#483)
 * Render stickers in the timeline (vector-im/riot-ios#1819).

Bug fixes:
 * MatrixSDK/JingleCallStack: Upgrade the minimal iOS version to 9.0 because the WebRTC framework requires it (vector-im/riot-ios#1821).
 * App fails to logout on unknown token (vector-im/riot-ios#1839).
 * All rooms showing the same avatar (vector-im/riot-ios#1673).

## Changes in Matrix iOS SDK in 0.10.7 (2018-03-30)
=============================================== 

Improvements:
 * Make state event redaction handling gentler with homeserver (vector-im/riot-ios#1823).

Bug fixes:
 * Room summary is not updated after redaction of the room display name (vector-im/riot-ios#1822).

## Changes in Matrix iOS SDK in 0.10.6 (2018-03-12)
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
 
## Changes in Matrix iOS SDK in 0.10.5 (2018-02-09)
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

## Changes in Matrix iOS SDK in 0.10.4 (2017-11-30)
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

## Changes in Matrix iOS SDK in 0.10.3 (2017-11-13)
=============================================== 

Bug fixes:
 * A 1:1 invite is not displayed as a direct chat after clearing the cache.

## Changes in Matrix iOS SDK in 0.10.1 (2017-10-27)
===============================================

Improvements:
 * Notifications: implement @room notifications (vector-im/riot-meta#119).
 * MXTools: Add a reusable generateTransactionId method.
 * MXRoom: Prevent multiple occurrences of the room id in the direct chats dictionary of the account data. 
 
Bug fixes:
 * CallKit - When I reject or answer a call on one device, it should stop ringing on all other iOS devices (vector-im/riot-ios#1618).

API breaks:
 * Crypto: Remove MXFileCryptoStore (We stopped to maintain it one year ago).

## Changes in Matrix iOS SDK in 0.10.0 (2017-10-23)
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

## Changes in Matrix iOS SDK in 0.9.3 (2017-10-03)
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

## Changes in Matrix iOS SDK in 0.9.2 (2017-08-25)
===============================================

Improvements:
 * MXRoom: Added an option to send a file and keep it's filename, thanks to @aramsargsyan (#354).
 
Bug fixes:
 * MXHTTPClient: retain cycles, thanks to @morozkin (#350).
 * MXPushRuleEventMatchConditionChecker: inaccurate regex, thanks to @morozkin (#353).
 * MXRoomState: returning old data for some properties, thanks to @morozkin (#355).

API breaks:
 * Add a "stateKey" optional param to [MXRoom sendStateEventOfType:] and to [MXRestClient sendStateEventToRoom:].

## Changes in Matrix iOS SDK in 0.9.1 (2017-08-08)
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

## Changes in Matrix iOS SDK in 0.9.0 (2017-08-01)
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

## Changes in Matrix iOS SDK in 0.8.2 (2017-06-30)
===============================================

Improvements:
 * MXFileStore: Improve performance by ~5% (PR #318).

## Changes in Matrix iOS SDK in 0.8.1 (2017-06-23)
===============================================

Improvements:
 * MXFileStore: Improve performance by ~10% (PR #316).
 
Bug fixes:
 * VoIP: Fix outgoing call stays in "Call connecting..." whereas it is established (https://github.com/vector-im/riot-ios#1326).

## Changes in Matrix iOS SDK in 0.8.0 (2017-06-16)
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

## Changes in Matrix iOS SDK in 0.7.11 (2017-03-23)
===============================================

Improvements:
 * MXSDKOptions: Let the application define its own media cache version (see `mediaCacheAppVersion`).
 * MXMediaManager: Consider a cache version based on the version defined by the application and the one defined at the SDK level.

## Changes in Matrix iOS SDK in 0.7.10 (2017-03-21)
===============================================

Bug fix:
 * Registration with email failed when the email address is validated on the mobile phone.

## Changes in Matrix iOS SDK in 0.7.9 (2017-03-16)
===============================================

Improvements:
 * MXRestClient: Tell the server we support the msisdn flow login (with x_show_msisdn parameter).
 * MXRoomState: Make isEncrypted implementation more robust.
 * MXCrypto: add ensureEncryptionInRoom method.

Bug fixes:
 * MXCrypto: Fix a crash due to a signedness issue in the count of one-time keys to upload.
 * MXCall: In case of encrypted room, make sure that encryption is fully set up before answering (https://github.com/vector-im/riot-ios#1058)

## Changes in Matrix iOS SDK in 0.7.8 (2017-03-07)
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

## Changes in Matrix iOS SDK in 0.7.7 (2017-02-08)
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
 
## Changes in Matrix iOS SDK in 0.7.6 (2017-01-24)
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

## Changes in Matrix iOS SDK in 0.7.5 (2017-01-19)
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

## Changes in Matrix iOS SDK in 0.7.4 (2016-12-23)
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

## Changes in Matrix iOS SDK in 0.7.3 (2016-11-23)
===============================================

Improvements:
 * Crypto: Ignore reshares of known megolm sessions.
 
Bug fixes:
 * MXRestClient: Fix Delete Device API.
 
## Changes in Matrix iOS SDK in 0.7.2 (2016-11-22)
===============================================

Improvements:
 * MXRestClient: Add API to get information about user's devices.
 
Bug fixes:
 * Cannot invite user with dash in their user id (vector-im/vector-ios#812).
 * Crypto: Mitigate replay attack #162.

## Changes in Matrix iOS SDK in 0.7.1 (2016-11-18)
===============================================

Bug fixes:
* fix Signal detected: 11 at [MXRoomState memberName:] level.
* [Register flow] Register with a mail address fails (https://github.com/vector-im/vector-ios#799).

## Changes in Matrix iOS SDK in 0.7.0 (2016-11-16)
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

## Changes in Matrix iOS SDK in 0.6.17 (2016-09-27)
================================================

Improvements:
 * Move MXRoom.acknowledgableEventTypes into MXSession (#141).
 * MXTools: Update the regex used to detect room alias (Support '#' character in alias name).

Bug fixes:
 * Invite a left user doesn't display his displayname (https://github.com/vector-im/vector-ios#646).
 * The room preview does not always display the right member info (https://github.com/vector-im/vector-ios#643).
 * App got stuck and permenantly spinning (https://github.com/vector-im/vector-ios#655).

## Changes in Matrix iOS SDK in 0.6.16 (2016-09-15)
================================================

Bug fixes:
 * MXSession: In case of initialSync, mxsession.myUser.userId must be available before changing the state to MXSessionStateStoreDataReady (https://github.com/vector-im/vector-ios#623).

## Changes in Matrix iOS SDK in 0.6.15 (2016-09-14)
================================================

Bug fixes:
 * MXFileStore: The stored receipts may not be totally loaded on cold start.
 * MXNotificationCenter: The conditions of override and underride rules are defined in an array.

## Changes in Matrix iOS SDK in 0.6.14 (2016-09-08)
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

## Changes in Matrix iOS SDK in 0.6.13 (2016-08-25)
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

## Changes in Matrix iOS SDK in 0.6.12 (2016-08-01)
================================================

Improvements:
 * MXCallManager: Better handle call invites when the app resumes.
 * MXCall: Improve the sending of local ICE candidates to avoid HTTP 429(Too Many Requests) response
 * MXCall: Added the audioToSpeaker property to choose between the main and the ear speaker.
 * MXRoomState: Added the joinedMembers property.
 * MXLogger: Added the isMainThread information in crash logs.
 
Bug fixes:
 * MXJingleCallStackCall: Added sanity check on creation of RTCICEServer objects as crashes have been reported.

## Changes in Matrix iOS SDK in 0.6.11 (2016-07-26)
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

## Changes in Matrix iOS SDK in 0.6.10 (2016-07-15)
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

## Changes in Matrix iOS SDK in 0.6.9 (2016-07-01)
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
 
 
## Changes in Matrix iOS SDK in 0.6.8 (2016-06-01)
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

## Changes in Matrix iOS SDK in 0.6.7 (2016-05-04)
===============================================

Improvements:
 * Presence: Manage the currently_active parameter.
 * MXRestClient: Add API to reset the account password.
 * Ability to report abuse
 * Ability to ignore users

## Changes in Matrix iOS SDK in 0.6.6 (2016-04-26)
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

## Changes in Matrix iOS SDK in 0.6.5 (2016-04-08)
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

## Changes in Matrix iOS SDK in 0.6.4 (2016-03-17)
===============================================

Improvements:
 * MXRoom: Update unread events handling (ignore m.room.member events and redacted events).
 * MXRoomPowerLevels: power level values are signed.
 * MXStore: Retrieve the receipt for a user in a room.

Bug fixes:
 * App crashes on redacted event handling.
 * The account data changes are ignored (Favorites section is not refreshed correctly).

## Changes in Matrix iOS SDK in 0.6.3 (2016-03-07)
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

## Changes in Matrix iOS SDK in 0.6.2 (2016-02-09)
===============================================

Improvements:
 * MXRoom: Add an argument to limit the pagination to the messages from the store.
 * MXRoom: Support email invitation.

Bug fixes:
 * App crashes on resume if a pause is pending.
 * Account creation: reCaptcha is missing in registration fallback.

## Changes in Matrix iOS SDK in 0.6.1 (2016-01-29)
===============================================

Improvements:
 * Remove Mantle dependency (to improve performances).
 * JSON validation: Log errors (break only in DEBUG build).

Bug fixes:
 * SYIOS-203: iOS crashes on non numeric power levels.
 * MXRestClient: set APNS pusher failed on invalid params.

## Changes in Matrix iOS SDK in 0.6.0 (2016-01-22)
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

## Changes in Matrix iOS SDK in 0.5.7 (2015-11-30)
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

## Changes in Matrix iOS SDK in 0.5.6 (2015-11-13)
===============================================

Bug fixes:
 * MXRoomState: All room members have the same power level when a new state event is received.
 * MXRoom: The backward room state is corrupted (former display name and avatar are missing).

## Changes in Matrix iOS SDK in 0.5.5 (2015-11-12)
===============================================

Improvements:
 * MXMemoryStore: Improved [MXStore unreadEvents] implementation. It is 7-8 times quicker now.
 * MXRoomState: Added cache to [MXRoomState memberName:] to optimise it.
 * MXUser/MXRoomMember: Ignore non mxc avatar url.

## Changes in Matrix iOS SDK in 0.5.4 (2015-11-06)
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

## Changes in Matrix iOS SDK in 0.5.3 (2015-09-14)
===============================================

Improvements:
 * Clean the store before the initial room syncing.
 * MXHTTPClient: improve http client logs.

Bug fixes:
 * MXRoom: App crashes on invite room during initial sync.

## Changes in Matrix iOS SDK in 0.5.2 (2015-08-13)
===============================================

Improvements:
 * Fixed code that made Cocoapods 0.38.2 unhappy.

## Changes in Matrix iOS SDK in 0.5.1 (2015-08-10)
===============================================

Improvements:
 * MXRestClient: Add API to create push rules.
 * MXRestClient: Add API to update global notification settings.

## Changes in Matrix iOS SDK in 0.5.0 (2015-07-10)
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


## Changes in Matrix iOS SDK in 0.4.0 (2015-04-23)
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


## Changes in Matrix iOS SDK in 0.3.2 (2015-03-27)
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
 * SYIOS-107 - In-App notifications does not work since ## Changes in push rules
   spec.
 * SYIOS-108 - I can't re-enter existing chats when tapping through contact
   details.
 * On iOS 8, the app does not prompt user to upload logs after app crash. Rage
   shake is not working too.
 * Typing notification - Do not loop anymore to send typing notif in case of
   failure.
 

## Changes in Matrix iOS SDK in 0.3.1 (2015-03-03)
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
 

## Changes in Matrix iOS SDK in 0.3.0 (2015-02-23)
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


## Changes in Matrix iOS SDK in 0.2.2 (2015-02-05)
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



## Changes in Matrix iOS SDK in 0.2.1 (2015-01-14)
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
 
 
 
## Changes in Matrix iOS SDK in 0.2.0 (2014-12-19)
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



## Changes in Matrix iOS SDK in 0.1.0 (2014-12-09)
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
