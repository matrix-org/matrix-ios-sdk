Matrix iOS SDK
==============

This open-source library allows you to build iOS apps compatible with Matrix (http://www.matrix.org), an open standard for interoperable Instant Messaging and VoIP.

This SDK implements an interface to communicate with the Matrix Home Server API which is defined at http://matrix.org/docs/api/client-server/.


WARNING: Work in progess
========================

The SDK is in its early days of development. It is actually unusable as is. Please wait for our official launch announcement before using it.


Installation
============

The SDK uses CocoaPods (http://cocoapods.org/) as library dependency manager.
The best way to add the SDK to your application project is to add the MatrixSDK dependency to your Podfile::
    
      pod 'MatrixSDK', :path => '../../MatrixSDK.podspec' // TODO: Register our podspec at cocoaPods


Usage
=====

One file to import::

      #import <MatrixSDK/MatrixSDK.h>

Three main classes to know:

:``MXHomeServer``:
    This class exposes Matrix Client-Server API that does not require the user to be authenticated. With this class, you can get a list of public rooms available on an home server. You can also register or login a user so that you can open a MXSession to the home server.
  
:``MXSession``:
    This class exposes Matrix Client-Server API that requires the user to be authenticated.
  
:``MXData``:
    This class manages the data received from the Matrix Home Server for you. It gets past and live data (using a MXSession instance), stores it and serves it to the app.

