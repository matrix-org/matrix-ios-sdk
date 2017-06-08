#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright 2016 OpenMarket Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


'''
Script to symbolicate addresses of a crash dump by using a dSYMs file map 
(located in XXXXXX.app.dSYM/Contents/Resources/DWARF).

It symbolicates only symbols that belong to the app, not system symbols.

It automatically downloads the symbols file from the Matrix Jenkins and thus
needs your credentials.
Make sure to set them in credentials.py.

You can put several crash dumps into one txt file.
The script will handle all txt files of the directory as a crash dump
and generates the converted files into the "output" folder.

'''

import sys, os, shutil, copy, re, glob
import requests, time
import credentials

def symbolicate(crashLogData):

    if not ("Build: " in crashLogData):
        print "Error: Can't determine build version"
        exit(-1)
        
    # Find the version of the app that generated the crash
    app = crashLogData.split("Application: ")[1] .split(" ", 1)[0]
    buildVersion = crashLogData.split("Build: ")[1] .split("\n", 1)[0]
    
    # Remove any white characters
    buildVersion = re.sub("\s", "", buildVersion)

    # Check the symbols FILE is here
    dSYMSFile = os.path.join("symbols", app, buildVersion, app)
    if not os.path.exists(dSYMSFile):

        # No, get it from the Matrix Jenkins
        if app == "matrixConsole":
             if "develop" in buildVersion:
                  jenkinsJob = "MatrixConsoleiOSDevelop"
             else:
                  jenkinsJob = "MatrixConsoleiOS"
        elif app == "Riot":
             if "develop" in buildVersion:
                  jenkinsJob = "RiotiOSDevelop"
             else:
                  jenkinsJob = "RiotiOS"
                        
        jenkinsBuild = re.findall(r"#(.*)", buildVersion)
        if len(jenkinsBuild):
             jenkinsBuild = jenkinsBuild[0]
        
        if not jenkinsJob or not jenkinsBuild:
            print "Error: Can't extract build version"
            exit(-1)
        
        XCArchiveTarGzURL = "http://matrix.org/jenkins/view/MatrixView/job/%s/%s/artifact/out/*.tar.gz/*zip*/out.zip" % (jenkinsJob, jenkinsBuild)

        print "Downloading symbols for %s (Build %s) at %s..." % (app, buildVersion, XCArchiveTarGzURL)
        responseCode = download_xcarchive_tar_gz(app, XCArchiveTarGzURL, dSYMSFile)
        
        if not 200 == responseCode:
            print "Error: Can't download the symbols file (Responce code: %d)" % responseCode
            if 401 == responseCode:
                print "Check your credentials in credentials.py"
            exit(-1)

    # Quick sanitization of HLTM chars
    crashLogData = crashLogData.replace("&lt;", "<").replace("&gt;", ">")
    
    # Extract memory addresses of our symbors
    memoryLocations = re.findall(r"(0x.*) %s \+ (.*)" % app, crashLogData)

    for (address, offset) in memoryLocations:

        # Convert the relative address in hex (implicitly required by atos) and the offset 
        loadAddress = hex(int(address, 16) - int(offset))

        # Use system tool to retrieve the symbol
        #print("atos -arch arm64 -o %s -l %s %s > symbol.tmp" % (dSYMSFile, loadAddress, address))
        os.system("atos -arch arm64 -o %s -l %s %s > symbol.tmp" % (dSYMSFile, loadAddress, address))

        # Extract the symbol
        file = open("symbol.tmp")
        symbol = file.read().replace("\n", "")
        file.close()
        os.remove("symbol.tmp")

        crashLogData =  crashLogData.replace(offset, "%s -> %s" % (offset, symbol))

    # Check result
    if "Signal detected:" in crashLogData:
        # In the case of a signal, we must find the handleSignal symbol in the result
        if not "handleSignal" in crashLogData:
            crashLogData = crashLogData + "\n* Warning: This symbolication seems invalid!\n"
    else:
        # In the case of a NS Exception, if the crash occured on the main thread, we must find the start and the main function at the call stack root.
        # If it is from another thread (ie its stack starts with start_wqthread), we can't validate the result
        if not "start_wqthread" in crashLogData:
            if not ("main" in crashLogData and "start" in crashLogData):
                crashLogData = crashLogData + "\n* Warning: This symbolication seems invalid!\n"

    return crashLogData

def downloadFile(url, login, password, destination):
    # Clean first
    if  os.path.exists(destination):
        os.remove(destination)

    r = requests.get(url, stream=True, auth=requests.auth.HTTPBasicAuth(login, password))
    
    if 200 == r.status_code:
        if not os.path.exists(os.path.dirname(destination)):
             os.makedirs(os.path.dirname(destination))
        
        with open(destination, 'wb') as fd:
            size = 0
            for chunk in r.iter_content(1024):
                fd.write(chunk)

    return r.status_code

def download_xcarchive_tar_gz(app, url, destination, appVersion=""):
    # First download the file
    targzFile = "/tmp/xcarchive.tar.gz"

    # Clean first
    if  os.path.exists("/tmp/%s.xcarchive" % app):
        os.system("rm -rf /tmp/%s.xcarchive" % app)

    responseCode = downloadFile(url, credentials.jenkins['login'], credentials.jenkins['password'], targzFile)
    if 200 == responseCode:
        # Not very nice: Let Mac OSX untargzipped everything
        os.system("open %s" % targzFile)
        print "Sleeping 5s to let time for the system to unzip xcarchive.tar.gz..."
        time.sleep(5)

        # And copy the symbol file at requested destination
        if not os.path.exists(os.path.dirname(destination)):
            os.makedirs(os.path.dirname(destination))

        print "cp /tmp/%s.xcarchive/dSYMs/%s.app.dSYM/Contents/Resources/DWARF/%s %s" % (app, app, app, destination)
        os.system("cp /tmp/%s.xcarchive/dSYMs/%s.app.dSYM/Contents/Resources/DWARF/%s %s" % (app, app, app, destination))

        # Check the expected symbols file is here 
        if not os.path.exists(destination):
            print "Error: Can't extract the symbols file"
            responseCode = 404

    return responseCode


if __name__ == "__main__":

    if not len(glob.glob("*.log")):
        print "Error: No .log files found in current folder"
        exit(-1)

    # Clean output dir
    if os.path.exists("output"):
        os.system("rm -rf output")
    os.mkdir("output")

    # Process every crash dump (all log files of this directory)
    for sFile in glob.glob("*.log"):
        print "# Processing %s" % sFile

        oFile = open(sFile)
        crashLogData = oFile.read()
        oFile.close()

        crashLogData = symbolicate(crashLogData)

        oFile = open("output/" + sFile, "w")
        oFile.write(crashLogData)
        oFile.close()

        print crashLogData
        print "Stored in %s" % ("output/" + sFile)
