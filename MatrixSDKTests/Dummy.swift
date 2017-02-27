/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

/*
 Dummy Swift file.
 
 Without a swift file in the MatrixSDKTests bundle, Xcode won't be able
 to run the tests. If "Gather Coverage Data" is enabled, you will see an
 error message that says:
 
    Code Coverage Data Generation Failed
    Unable to retrieve the profile data files from <Device Name>
 
 THIS IS MISLEADING! The issue doesn't have anything to do with code
 coverage. In fact, if you disable "Gather Coverage Data", the task will
 fail silently.
 
 If you delete this Swift file, you may find that the tests continue to run
 without issues. DECEPTION! If another developer attempts to clone this
 repository without a swift file in the test bundle, the tests will not run!
 */
