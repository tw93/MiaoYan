import Foundation

class Repository {
    private var git: Git
    private var name: String
    private var workTree: URL
    private var debug: Bool

    init(git: Git, debug: Bool, project: Project, workTree: URL) {
        self.git = git
        self.debug = debug
        self.workTree = workTree
        self.name = project.getShortSign() + " - " + project.label + ".git"
    }

    private func exec(args: [String]) -> String? {
        let env = getEnvironment()

        return git.exec(args: args, env: env)
    }

    public func getEnvironment() -> [String: String] {
        let repo = git.getRepositoriesHome().appendingPathComponent(name)
        return ["GIT_DIR": repo.path, "GIT_WORK_TREE": workTree.path]
    }

    public func initialize(from: Project) {
        let repo = git.getRepositoriesHome().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: repo.path) else { return }

        let output = exec(args: ["init"])

        if debug {
            print("Repo init: \(String(describing: output))")
        }
    }

    public func commit(fileName: String) {
        let add = exec(args: ["add", "\(fileName)"])
        let commit = exec(args: ["commit", "-m", "'\(fileName) update'"])

        if debug {
            print("Add file: \(String(describing: add))")
            print("Commit file: \(String(describing: commit))")
        }
    }

    public func commitAll() {
        let add = exec(args: ["add", "."])
        let commit = exec(args: ["commit", "-m", "'Scheduled snapshot'"])

        if debug {
            print("Add files: \(String(describing: add))")
            print("Commit files: \(String(describing: commit))")
        }
    }

    public func getCommits(by fileName: String) -> [Commit] {
        var commits = [Commit]()
        if let log = exec(args: ["log", "--follow", "--", "\(fileName)"]) {
            let commitsList = log.matchingStrings(regex: "(?:commit) ([0-9a-z]{32})")

            for commit in commitsList {
                if let hash = commit.last {
                    commits.append(Commit(hash: hash))
                }
            }

            let datesList = log.matchingStrings(regex: "(?:Date):   ([^\\n]*)")
            var dateId = 0
            for date in datesList {
                if let dateString = date.last {
                    commits[dateId].setDate(date: dateString)
                }
                dateId += 1
            }
        }

        return commits
    }

    public func checkout(commit: Commit, fileName: String) {
        let output = exec(args: ["checkout", commit.getHash(), "\(fileName)"])

        if debug {
            print("Checkout file: \(String(describing: output))")
        }
    }
}
