//
//  StorageEntity+CoreDataProperties.swift
//  
//
//  Created by Oleksandr Glushchenko on 11/14/17.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension StorageEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<StorageEntity> {
        return NSFetchRequest<StorageEntity>(entityName: "StorageEntity")
    }

    @NSManaged public var name: String?
    @NSManaged public var path: String?

}
