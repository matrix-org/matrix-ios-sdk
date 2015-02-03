Build instructions
==================

Before opening the Matrix SDK workspace, you need to build it.


The project has some third party library dependencies declared in a pod file. You need to run the CocoaPods command to download them and to set up the Matrix SDK workspace::

        $ pod install

Then, open ``MatrixSDK.xcworkspace``. 


Tests
=====

The tests in the SDK Xcode project are both unit and integration tests.

Out of the box, the tests use one of the home servers (located at http://localhost:8080 )of the "Demo Federation of Homeservers" (https://github.com/matrix-org/synapse#running-a-demo-federation-of-homeservers). You have to start them from your local Synapse folder::

      $ demo/start.sh --no-rate-limit

Then, you can run the tests from the Xcode Test navigator tab or select the MatrixSDKTests scheme and click on the "Test" action.

Push Notifications
==================

To use push notifications, you will need to set up a push gateway. When you call setPusherWithPushkey, this creates a pusher on the Home Server that your session is logged in to. This will send HTTP notifications to a URL you supply as the 'url' key in the 'data' argument to setPusherWithPushkey. Matrix provides a reference push gateway, 'sygnal', which can be found at https://github.com/matrix-org/sygnal

You will need to set up a push gateway at a publicly accessible URL. This push gateway will be the server that has the private key you used to request your APNS certificate. Your push gateway needs to expose on path that accept a POST request to send notifications: see the HTTP Push Notification Protocol section the Matrix Spercification for more details. As per the specification, Matrix strongly recommends that the path of this URL be '/_matrix/push/v1/notify'. The URL of this endpoint is the URL your client should put into the 'url' value of the 'data' dictionary.
