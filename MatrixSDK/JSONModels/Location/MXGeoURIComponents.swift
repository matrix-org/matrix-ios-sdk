// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

/// A structure that parses a geo URI (i.e. geo:53.99803101552848,-8.25347900390625;u=10) and constructs their constituent parts.
@objcMembers
public class MXGeoURIComponents: NSObject {
    
    // MARK: - Properties
    
    public let latitude: Double
    public let longitude: Double
    public let geoURI: String
    
    // MARK: - Setup
    
    public convenience init?(geoURI: String) {
        
        guard let (latitude, longitude) = Self.parseCoordinates(from: geoURI) else {
            return nil
        }
        self.init(latitude: latitude, longitude: longitude)
    }
    
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.geoURI = Self.geoURI(with: latitude, and: longitude)
        
        super.init()
    }
    
    // MARK: - Private
    
    // Parse a geo URI string like "geo:53.99803101552848,-8.25347900390625;u=10"
    private class func parseCoordinates(from geoURIString: String) -> (Double, Double)? {
        
        guard let locationString = geoURIString.components(separatedBy: ":").last?.components(separatedBy: ";").first else {
            return nil
        }
        
        let locationComponents = locationString.components(separatedBy: ",")
        
        guard locationComponents.count >= 2 else {
            return nil
        }
        
        guard let latitude = Double(locationComponents[0]), let longitude = Double(locationComponents[1]) else {
            return nil
        }

        return (latitude, longitude)
    }
    
    // Return a geo URI string like "geo:53.99803101552848,-8.25347900390625"
    private class func geoURI(with latitude: Double, and longitude: Double) -> String {
        return "geo:\(latitude),\(longitude)"
    }
}
