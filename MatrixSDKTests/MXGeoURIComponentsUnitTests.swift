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

import XCTest

@testable import MatrixSDK

class MXGeoURIComponentsUnitTests: XCTestCase {
        
    func testParsingSucceed() throws {
                
        let geoURIString = "geo:53.99803101552848,-8.25347900390625;u=10"
        
        let expectedLatitude: Double = 53.99803101552848
        let expectedLongitude: Double = -8.25347900390625
        
        let geoURIComponents = MXGeoURIComponents(geoURI: geoURIString)
        
        guard let geoURIComponents = geoURIComponents else {
            XCTFail("coordinates should not be nil")
            return
        }

        XCTAssertEqual(geoURIComponents.latitude, expectedLatitude)
        XCTAssertEqual(geoURIComponents.longitude, expectedLongitude)
    }
    
    func testParsingWithAltitudeSucceed() throws {
                
        let geoURIString = "geo:53.99803101552848,-8.25347900390625,0;u=164"
        
        let latitude: Double = 53.99803101552848
        let longitude: Double = -8.25347900390625
        
        let geoURIComponents = MXGeoURIComponents(geoURI: geoURIString)
        
        XCTAssertNotNil(geoURIComponents)
        XCTAssertEqual(geoURIComponents?.latitude, latitude)
        XCTAssertEqual(geoURIComponents?.longitude, longitude)
    }
    
    func testParsingFails() throws {
        
        let geoURIString = "geo:53.99803101552848.-8.25347900390625"
        
        let geoURIComponents = MXGeoURIComponents(geoURI: geoURIString)
                
        XCTAssertNil(geoURIComponents)
    }
    
    func testSerializationSucceed() throws {
                
        let expectedGeoURI = "geo:53.99803101552848,-8.25347900390625"
        
        let latitude: Double = 53.99803101552848
        let longitude: Double = -8.25347900390625
        
        let geoURIComponents = MXGeoURIComponents(latitude: latitude, longitude: longitude)
        
        XCTAssertEqual(geoURIComponents.geoURI, expectedGeoURI)
    }
}
