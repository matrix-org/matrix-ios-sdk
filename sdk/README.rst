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