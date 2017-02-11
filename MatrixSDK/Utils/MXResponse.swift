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

import Foundation




/**
 Captures the result of an API call and it's associated success data.
 
 # Examples:
 
 Use a switch statement to handle both a success and an error:
 
     mxRestClient.publicRooms { response in
         switch response {
         case .success(let rooms):
             // Do something useful with these rooms
             break
         
         case .failure(let error):
             // Handle the error in some way
             break
         }
     }
 
 Silently ignore the failure case:
 
     mxRestClient.publicRooms { response in
         guard let rooms = response.value else { return }
         // Do something useful with these rooms
     }
 
 */
public enum MXResponse<T> {
    case success(T)
    case failure(Error)
    
    /// Indicates whether the API call was successful
    public var isSuccess: Bool {
        switch self {
        case .success:  return true
        default:        return false
        }
    }
    
    /// The response's success value, if applicable
    public var value: T? {
        switch self {
        case .success(let value): return value
        default: return nil
        }
    }
    
    /// Indicates whether the API call failed
    public var isFailure: Bool {
        return !isSuccess
    }
    
    /// The response's error value, if applicable
    public var error: Error? {
        switch self {
        case .failure(let error): return error
        default: return nil
        }
    }
}




/**
 Reports ongoing progress of a process, and encapsulates relevant
 data when the operation succeeds or fails.
 
 # Examples:
 
 Use a switch statement to handle each case:
 
     mxRestClient.uploadContent( ... ) { progress in
         switch progress {
         case .progress(let progress):
             // Update progress bar
             break
        
         case .success(let contentUrl):
             // Do something with the url
             break
 
         case .failure(let error):
             // Handle the error
             break
         }
     }
 
 Ignore progress updates. Wait until operation is complete.
 
     mxRestClient.uploadContent( ... ) { progress in
         guard progress.isComplete else { return }
 
         if let url = progress.value {
            // Do something with the url
         } else {
            // Handle the error
         }
     }
 */
public enum MXProgress<T> {
    case progress(Progress)
    case success(T)
    case failure(Error)
    
    /// Indicates whether the call is complete.
    public var isComplete: Bool {
        switch self {
        case .success, .failure: return true
        default: return false
        }
    }
    
    /// The current progress. If the process is already complete, this will return nil.
    public var progress: Progress? {
        switch self {
        case .progress(let progress): return progress
        default: return nil
        }
    }
    
    /// Indicates whether the API call was successful.
    /// Returns false if the process is still incomplete.
    public var isSuccess: Bool {
        switch self {
        case .success:   return true
        default:        return false
        }
    }
    
    /// The response's success value, if applicable
    public var value: T? {
        switch self {
        case .success(let value): return value
        default: return nil
        }
    }
    
    /// Indicates whether the API call failed.
    /// Returns false if the process is still incomplete.
    public var isFailure: Bool {
        switch self {
        case .failure:  return true
        default:        return false
        }
    }
    
    /// The response's error value, if applicable
    public var error: Error? {
        switch self {
        case .failure(let error): return error
        default: return nil
        }
    }
}
