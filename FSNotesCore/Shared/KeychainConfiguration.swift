/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 A simple struct that defines the service and access group to be used by the sample apps.
 */

import Foundation

struct KeychainConfiguration {
    static let serviceName = "MiaoYanApp"

    /*
     Specifying an access group to use with `KeychainPasswordItem` instances
     will create items shared accross both apps.
     
     For information on App ID prefixes, see:
     https://developer.apple.com/library/ios/documentation/General/Conceptual/DevPedia-CocoaCore/AppID.html
     and:
     https://developer.apple.com/library/ios/technotes/tn2311/_index.html
     */
    //    static let accessGroup = "[YOUR APP ID PREFIX].com.example.apple-samplecode.GenericKeychainShared"

    /*
     Not specifying an access group to use with `KeychainPasswordItem` instances
     will create items specific to each app.
     */
    static let accessGroup: String? = nil
}
