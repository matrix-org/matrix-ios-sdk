// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

/// Measurement unit for Stopwatch.
@objc public enum MXStopwatchMeasurementUnit: UInt {
    case seconds
    case milliseconds
}

@objcMembers public class MXStopwatch: NSObject {
    
    private var startDate: Date
    
    /// Initializer.
    public override init() {
        startDate = Date()
        super.init()
    }
    
    //  MARK: - Public Interface
    
    /// Measure time since last init/reset.
    /// - Parameter type: Unit of measurement. See `StopwatchMeasurementUnit`.
    /// - Returns: Measured time in desired type.
    public func measure(in type: MXStopwatchMeasurementUnit = .milliseconds) -> TimeInterval {
        switch type {
        case .seconds:
            return measuredTimeInSeconds
        case .milliseconds:
            return measuredTimeInMilliseconds
        }
    }
    
    /// Measure time since last init/reset and convert it into a readable string in the desired unit. Does not make convertions between units.
    /// - Parameter type: Unit of measurement. See `StopwatchMeasurementUnit`.
    /// - Returns: User readable string with measured time.
    public func readable(in type: MXStopwatchMeasurementUnit = .milliseconds) -> String {
        switch type {
        case .seconds:
            return String(format: "%.0fs", measuredTimeInSeconds)
        case .milliseconds:
            return String(format: "%.0fms", measuredTimeInMilliseconds)
        }
    }
    
    /// Reset the stopwatch.
    public func reset() {
        startDate = Date()
    }
    
    //  MARK: - Private Methods
    
    private var measuredTimeInSeconds: TimeInterval {
        return Date().timeIntervalSince(startDate)
    }
    
    private var measuredTimeInMilliseconds: TimeInterval {
        return measuredTimeInSeconds * 1000
    }
    
}
