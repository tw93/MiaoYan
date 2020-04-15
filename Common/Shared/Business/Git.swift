//
//  Git.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/7/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class Git {

    static var instance: Git?

    private var home: URL
    private var repositories: URL
    private var debug: Bool

    public static func sharedInstance() -> Git {
        guard let git = self.instance else {
            self.instance = Git(storage: UserDefaultsManagement.gitStorage)
            return self.instance!
        }
        return git
    }

    public static func resetInstance() {
        instance = nil
    }

    init(debug: Bool = true, storage: URL) {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let home = library.appendingPathComponent("Git")

        if !FileManager.default.fileExists(atPath: home.path) {
            try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: nil)
        }

        let configDst = home.appendingPathComponent(".gitconfig")
        let templatesDst = home.appendingPathComponent("templates")

        if !FileManager.default.fileExists(atPath: configDst.path),
            let gitBundlePath = Bundle.main.path(forResource: "Git", ofType: ".bundle") {
            let gitBundle = URL(fileURLWithPath: gitBundlePath)

            let configSrc = gitBundle.appendingPathComponent(".gitconfig")
            let templatesSrc = gitBundle.appendingPathComponent("templates")

            try? FileManager.default.copyItem(at: configSrc, to: configDst)
            try? FileManager.default.copyItem(at: templatesSrc, to: templatesDst)
        }

        self.home = home
        self.debug = debug
        self.repositories = storage
    }

    public func getRepositoriesHome() -> URL {
        return repositories
    }

    public func pathToGit() -> String? {
        let gitReleaseURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/git")
        if FileManager.default.fileExists(atPath: gitReleaseURL.path) {
            return gitReleaseURL.path
        }

        return Bundle.main.path(forResource: "git", ofType: "")
    }

    public func exec(args: [String], env: [String: String]? = nil) -> String? {
        guard let launchPath = pathToGit() else { return nil }

        let process = Process()

        process.launchPath = launchPath

        var defaultEnv = [
            "GIT_CONFIG_NOSYSTEM": "true",
            "HOME": home.path
        ]

        if let env = env {
            defaultEnv = env.merging(defaultEnv) { $1 }
        }

        process.environment = defaultEnv
        process.arguments = args

        let pipe = Pipe()

        process.standardOutput = pipe
        process.standardError = pipe

        if #available(OSX 10.13, *) {
            do {
                try process.run()
            } catch {
                if debug {
                    print("Can't run git process: \(error.localizedDescription)")
                }

                return nil
            }
        } else {
            process.launch()
        }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            return output
        }

        return nil
    }

    public func getVersion() -> String? {
        if let version = exec(args: ["--version"]) {
            return version
        }

        return nil
    }

    public func getRepository(by project: Project) -> Repository {
        let repository = Repository(git: self, debug: debug, project: project, workTree: project.url)
        repository.initialize(from: project)

        return repository
    }
}
