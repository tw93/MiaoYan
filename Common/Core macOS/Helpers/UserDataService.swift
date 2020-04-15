//
//  UserDataService.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 1/30/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

public class UserDataService {
    public static let instance = UserDataService()

    fileprivate var _searchTrigger = false
    fileprivate var _lastRenamed: URL?
    fileprivate var _fsUpdates = false
    fileprivate var _isNotesTableEscape = false
    fileprivate var _isDark = false

    fileprivate var _lastType: Int?
    fileprivate var _lastProject: URL?
    fileprivate var _lastName: String?

    fileprivate var _importProgress = false

    public var searchTrigger: Bool {
        get {
            return _searchTrigger
        }
        set {
            _searchTrigger = newValue
        }
    }

    public var focusOnImport: URL? {
        get {
            return _lastRenamed
        }
        set {
            _lastRenamed = newValue
        }
    }

    public var fsUpdatesDisabled: Bool {
        get {
            return _fsUpdates
        }
        set {
            _fsUpdates = newValue
        }
    }

    public var isNotesTableEscape: Bool {
        get {
            return _isNotesTableEscape
        }
        set {
            _isNotesTableEscape = newValue
        }
    }

    public var isDark: Bool {
        get {
            return _isDark
        }
        set {
            _isDark = newValue
        }
    }

    public var lastType: Int? {
        get {
            return _lastType
        }
        set {
            _lastType = newValue
        }
    }

    public var lastName: String? {
        get {
            return _lastName
        }
        set {
            _lastName = newValue
        }
    }

    public var lastProject: URL? {
        get {
            return _lastProject
        }
        set {
            _lastProject = newValue
        }
    }

    public func resetLastSidebar() {
        _lastProject = nil
        _lastType = nil
        _lastName = nil
    }

    public var skipSidebarSelection: Bool {
        get {
            return _importProgress
        }
        set {
            _importProgress = newValue
        }
    }
}
