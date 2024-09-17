//
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
#if IS_TEST_RUN
import SwiftyBeaver
#else
@_implementationOnly import SwiftyBeaver
#endif

/// Various MXLog configuration options. Used in conjunction with `MXLog.configure()`
@objc public class MXLogConfiguration: NSObject {
    /// the desired log level. `.verbose` by default.
    @objc public var logLevel = MXLogLevel.verbose
    
    /// whether logs should be written directly to files. `false` by default.
    @objc public var redirectLogsToFiles = false
    
    /// the maximum total space to use for log files in bytes. `100MB` by default.
    @objc public var logFilesSizeLimit: UInt = 100 * 1024 * 1024 // 100MB
    
    /// the maximum number of log files to use before rolling. `50` by default.
    @objc public var maxLogFilesCount: UInt = 50
    
    /// the subname for log files. Files will be named as 'console-[subLogName].log'. `nil` by default
    @objc public var subLogName: String?
}

/// MXLog logging levels. Use .none to disable logging entirely.
@objc public enum MXLogLevel: UInt {
    case none
    case verbose
    case debug
    case info
    case warning
    case error
}

private var logger: SwiftyBeaver.Type = {
    let logger = SwiftyBeaver.self
    MXLog.configureLogger(logger, withConfiguration: MXLogConfiguration())
    return logger
}()

/**
 Logging utility that provies multiple logging levels as well as file output and rolling.
 Its purpose is to provide a common entry for customizing logging and should be used throughout the code.
 Please see `MXLog.h` for Objective-C options.
 */
@objc public class MXLog: NSObject {
    /// Method used to customize MXLog's behavior.
    /// Called automatically when first accessing the logger with the default values.
    /// Please see `MXLogConfiguration` for all available options.
    /// - Parameters:
    ///     - configuration: the `MXLogConfiguration` instance to use
    @objc public static func configure(_ configuration: MXLogConfiguration) {
        configureLogger(logger, withConfiguration: configuration)
    }
    
    public static func verbose(_ message: @autoclosure () -> Any,
                               _ file: String = #file,
                               _ function: String = #function,
                               line: Int = #line,
                               context: Any? = nil) {
        logger.verbose(message(), file, function, line: line, context: context)
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logVerbose(_ message: String, file: String, function: String, line: Int) {
        logger.verbose(message, file, function, line: line)
    }
    
    public static func debug(_ message: @autoclosure () -> Any,
                             _ file: String = #file,
                             _ function: String = #function,
                             line: Int = #line,
                             context: Any? = nil) {
        logger.debug(message(), file, function, line: line, context: context)
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logDebug(_ message: String, file: String, function: String, line: Int) {
        logger.debug(message, file, function, line: line)
    }
    
    public static func info(_ message: @autoclosure () -> Any,
                            _ file: String = #file,
                            _ function: String = #function,
                            line: Int = #line,
                            context: Any? = nil) {
        logger.info(message(), file, function, line: line, context: context)
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logInfo(_ message: String, file: String, function: String, line: Int) {
        logger.info(message, file, function, line: line)
    }
    
    public static func warning(_ message: @autoclosure () -> Any,
                               _ file: String = #file,
                               _ function: String = #function,
                               line: Int = #line,
                               context: Any? = nil) {
        logger.warning(message(), file, function, line: line, context: context)
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logWarning(_ message: String, file: String, function: String, line: Int) {
        logger.warning(message, file, function, line: line)
    }
    
    /// Log error with additional details
    ///
    /// - Parameters:
    ///     - message: Description of the error without any variables (this is to improve error aggregations by type)
    ///     - context: Additional context-dependent details about the issue
    public static func error(_ message: StaticString,
                             _ file: String = #file,
                             _ function: String = #function,
                             line: Int = #line,
                             context: Any? = nil) {
        logger.error(message, file, function, line: line, context: context)
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logError(_ message: String,
                                      file: String,
                                      function: String,
                                      line: Int,
                                      context: Any? = nil) {
        logger.error(message, file, function, line: line, context: context)
    }
    
    /// Log failure with additional details
    ///
    /// A failure is any type of programming error which should never occur in production. In `DEBUG` configuration
    /// any failure will raise `assertionFailure`
    ///
    /// - Parameters:
    ///     - message: Description of the error without any variables (this is to improve error aggregations by type)
    ///     - context: Additional context-dependent details about the issue
    public static func failure(_ message: StaticString,
                               _ file: String = #file,
                               _ function: String = #function,
                               line: Int = #line,
                               context: Any? = nil) {
        logger.error(message, file, function, line: line, context: context)
        #if DEBUG
        assertionFailure("\(message)")
        #endif
    }
    
    @available(swift, obsoleted: 5.4)
    @objc public static func logFailure(_ message: String,
                                        file: String,
                                        function: String,
                                        line: Int,
                                        context: Any? = nil) {
        logger.error(message, file, function, line: line, context: context)
        #if DEBUG
        assertionFailure("\(message)")
        #endif
    }
    
    // MARK: - Private
    
    fileprivate static func configureLogger(_ logger: SwiftyBeaver.Type, withConfiguration configuration: MXLogConfiguration) {
        if let subLogName = configuration.subLogName {
            MXLogger.setSubLogName(subLogName)
        }
        
        MXLogger.redirectNSLog(toFiles: configuration.redirectLogsToFiles,
                               numberOfFiles: configuration.maxLogFilesCount,
                               sizeLimit: configuration.logFilesSizeLimit)
        
        guard configuration.logLevel != .none else {
            logger.removeAllDestinations()
            return
        }
        
        logger.removeAllDestinations()
        
        let consoleDestination = ConsoleDestination()
        consoleDestination.useNSLog = true
        consoleDestination.asynchronously = false
        consoleDestination.format = "$DHH:mm:ss.SSS$d$Z $C$M $X$c" // Format is `Time Color Message Context`, see https://docs.swiftybeaver.com/article/20-custom-format
        consoleDestination.levelColor.verbose = ""
        consoleDestination.levelColor.debug = ""
        consoleDestination.levelColor.info = ""
        consoleDestination.levelColor.warning = "⚠️ "
        consoleDestination.levelColor.error = "🚨 "
        
        switch configuration.logLevel {
        case .verbose:
            consoleDestination.minLevel = .verbose
        case .debug:
            consoleDestination.minLevel = .debug
        case .info:
            consoleDestination.minLevel = .info
        case .warning:
            consoleDestination.minLevel = .warning
        case .error:
            consoleDestination.minLevel = .error
        case .none:
            break
        }
        logger.addDestination(consoleDestination)
        
        #if !DEBUG
        // Non-debug builds will log fatal issues to analytics if tracking consent provided
        let analytics = MXAnalyticsDestination()
        logger.addDestination(analytics)
        #endif
    }
}

/// Convenience wrapper around `MXLog` which formats all logs as "[Name] function: <message>"
///
/// Note: Ideally the `format` of `ConsoleDestination` is set to track filename and function automatically
/// (e.g. as `consoleDestination.format = "[$N] $F $C $M $X")`, but this would require the removal of all
/// manually added filenames in logs.
struct MXNamedLog {
    let name: String
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.debug(formattedMessage(message, function: function), file, function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        logger.warning(formattedMessage(message, function: function), file, function, line: line)
    }
    
    /// Logging errors requires a static message, all other details must be sent as additional parameters
    func error(_ message: StaticString, context: Any? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logger.error(formattedMessage(message, function: function), file, function, line: line, context: context)
    }
    
    /// Logging failures requires a static message, all other details must be sent as additional parameters
    func failure(_ message: StaticString, context: Any? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        logger.error(formattedMessage(message, function: function), file, function, line: line, context: context)
        #if DEBUG
        assertionFailure("\(message)")
        #endif
    }
    
    private func formattedMessage(_ message: Any, function: String) -> String {
        "[\(name)] \(function): \(message)"
    }
}
