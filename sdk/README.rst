Build instructions
==================

Before opening the Matrix SDK workspace, you need to build it.


The project has some third party library dependencies declared in a pod file. You need to run the CocoaPods command to download them and to set up the Matrix SDK workspace::

        $ pod install

Then, open ``MatrixSDK.xcworkspace``. 


Tests
=====

You can run unitary testing from the Xcode Test navigator tab or select the MatrixSDKTests scheme and launch the "Test" action.