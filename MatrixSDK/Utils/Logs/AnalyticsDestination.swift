//
//  AnalyticsDestination.swift
//  MatrixSDK
//
//  Created by Element on 22/08/2022.
//

import Foundation
import SwiftyBeaver

/// SwiftyBeaver log destination that sends errors to analytics tracker
class AnalyticsDestination: BaseDestination {
    override var asynchronously: Bool {
        get {
            return false
        }
        set {
            assertionFailure("Cannot be used asynchronously to preserve strack trace")
        }
    }
    
    override var minLevel: SwiftyBeaver.Level {
        get {
            return .error
        }
        set {
            assertionFailure("Analytics should not track anything less severe than errors")
        }
    }
    
    override func send(_ level: SwiftyBeaver.Level, msg: String, thread: String, file: String, function: String, line: Int, context: Any? = nil) -> String? {
        let message = super.send(level, msg: msg, thread: thread, file: file, function: function, line: line, context: context)
        #if !DEBUG
        MXSDKOptions.sharedInstance().analyticsDelegate?.trackNonFatalIssue(msg, details: formattedDetails(from: context))
        #endif
        return message
    }
    
    private func formattedDetails(from context: Any?) -> [String: Any]? {
        guard let context = context else {
            return nil
        }
        
        if let dictionary = context as? [String: Any] {
            return dictionary
        } else if let error = context as? Error {
            return [
                "error": error.localizedDescription
            ]
        } else {
            return [
                "context": String(describing: context)
            ]
        }
    }
}
