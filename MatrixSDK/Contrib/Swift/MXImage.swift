//
//  MXImage.swift
//  MatrixSDK
//
//  Created by Avery Pierce on 7/21/17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

import Foundation

#if os(iOS)
    public typealias MXImage = UIImage
#elseif os(OSX)
    public typealias MXImage = NSImage
#endif
