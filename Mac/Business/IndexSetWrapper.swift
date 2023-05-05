//
//  IndexSetWrapper.swift
//  MiaoYan
//
//  Created by Tw93 on 2023/5/5.
//  Copyright © 2023 MiaoYan App. All rights reserved.
//

import Foundation

class IndexSetWrapper: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        return true
    }

    let indexSet: IndexSet

    init(indexSet: IndexSet) {
        self.indexSet = indexSet
        super.init()
    }

    required init?(coder aDecoder: NSCoder) {
        guard let intArray = aDecoder.decodeObject(of: NSArray.self, forKey: "indexSet") as? [Int] else {
            return nil
        }
        self.indexSet = IndexSet(intArray)
        super.init()
    }

    func encode(with aCoder: NSCoder) {
        let intArray = indexSet.map { $0 }
        aCoder.encode(intArray, forKey: "indexSet")
    }
}

