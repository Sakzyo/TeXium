import XCTest
@testable import TeXiumCore

final class GitSynchronizationTests: TemporaryProjectTest {
    private func git(_ args: [String], at url: URL) async throws -> String { try await GitService.run(args, root: url).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func identity(_ url: URL) async throws {
        _ = try await git(["config", "user.name", "TeXium Test"], at: url)
        _ = try await git(["config", "user.email", "test@example.invalid"], at: url)
        _ = try await git(["config", "commit.gpgsign", "false"], at: url)
    }
    private func commit(_ text: String, at url: URL, file: String = "main.tex") async throws {
        try text.write(to: url.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try await GitService.commit(message: text, stageAll: true, root: url)
    }
    private func fixture() async throws -> (URL, URL, URL) {
        let bare = root.appendingPathComponent("remote.git")
        let local = root.appendingPathComponent("Local Project")
        let other = root.appendingPathComponent("Other Writer")
        _ = try await git(["init", "--bare", "--initial-branch=main", bare.path], at: root)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try await GitService.initialize(root: local); try await identity(local)
        try await commit("Initial manuscript", at: local)
        _ = try await git(["remote", "add", "origin", bare.path], at: local)
        _ = try await GitSynchronizationService.perform(.synchronize, root: local)
        try await GitService.clone(bare.path, to: other); try await identity(other)
        return (local, other, bare)
    }
    private func refused(_ action: GitSyncAction, at url: URL, contains: String) async {
        do { _ = try await GitSynchronizationService.perform(action, root: url); XCTFail("Expected refusal") }
        catch { XCTAssertTrue(error.localizedDescription.contains(contains), error.localizedDescription) }
    }
    func testPublishFetchPullAndPush() async throws {
        let (local, other, bare) = try await fixture()
        let initial = try await GitService.inspect(root: local)
        XCTAssertEqual(initial.upstream, "origin/main"); XCTAssertEqual(initial.ahead, 0)
        try await commit("Remote revision", at: other)
        _ = try await GitSynchronizationService.perform(.push, root: other)
        let fetched = try await GitSynchronizationService.perform(.fetch, root: local)
        XCTAssertEqual(fetched.state.behind, 1)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("main.tex")), "Initial manuscript")
        let pulled = try await GitSynchronizationService.perform(.synchronize, root: local)
        XCTAssertEqual(pulled.state.behind, 0)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("main.tex")), "Remote revision")
        try await commit("Local revision", at: local)
        let outgoing = try await GitService.inspect(root: local); XCTAssertEqual(outgoing.ahead, 1)
        let pushed = try await GitSynchronizationService.perform(.push, root: local)
        XCTAssertEqual(pushed.state.ahead, 0)
        let remoteText = try await git(["show", "main:main.tex"], at: bare); XCTAssertEqual(remoteText, "Local revision")
    }
    func testDirtyWorkAndDivergencePreserveBothHistories() async throws {
        let (local, other, bare) = try await fixture()
        try await commit("Remote work", at: other); _ = try await GitSynchronizationService.perform(.push, root: other)
        try "Unsaved to Git".write(to: local.appendingPathComponent("main.tex"), atomically: true, encoding: .utf8)
        let head = try await git(["rev-parse", "HEAD"], at: local)
        await refused(.synchronize, at: local, contains: "Commit your changes")
        let after = try await git(["rev-parse", "HEAD"], at: local); XCTAssertEqual(head, after)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("main.tex")), "Unsaved to Git")
        try await GitService.commit(message: "Independent local work", stageAll: true, root: local)
        let localHead = try await git(["rev-parse", "HEAD"], at: local)
        let remoteHead = try await git(["rev-parse", "main"], at: bare)
        await refused(.synchronize, at: local, contains: "diverged")
        let keptLocal = try await git(["rev-parse", "HEAD"], at: local)
        let keptRemote = try await git(["rev-parse", "main"], at: bare)
        XCTAssertEqual(localHead, keptLocal); XCTAssertEqual(remoteHead, keptRemote)
        let state = try await GitService.inspect(root: local); XCTAssertEqual(state.ahead, 1); XCTAssertEqual(state.behind, 1)
    }
    func testConflictAndDetachedHeadAreRefused() async throws {
        let (local, other, _) = try await fixture()
        try await commit("Other conflict", at: other); _ = try await GitSynchronizationService.perform(.push, root: other)
        try await commit("Local conflict", at: local); _ = try await GitSynchronizationService.perform(.fetch, root: local)
        _ = try await GitService.execute(["merge", "origin/main"], root: local)
        let conflict = try await GitService.inspect(root: local); XCTAssertTrue(conflict.conflicted); XCTAssertTrue(conflict.operationInProgress)
        await refused(.synchronize, at: local, contains: "conflict resolution")
        _ = try await git(["merge", "--abort"], at: local)
        _ = try await git(["switch", "--detach"], at: local)
        await refused(.push, at: local, contains: "detached HEAD")
    }
    func testPullNeverPushesAndSyncWithoutOutgoingDoesNotNeedPushAccess() async throws {
        let (local, other, bare) = try await fixture()
        try await commit("Incoming", at: other); _ = try await GitSynchronizationService.perform(.push, root: other)
        // A rejecting server hook proves an incoming-only sync never attempts a push.
        let hook = bare.appendingPathComponent("hooks/pre-receive")
        try "#!/bin/sh\necho 'push forbidden' >&2\nexit 1\n".write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        _ = try await GitSynchronizationService.perform(.synchronize, root: local)
        try await commit("Outgoing", at: local)
        let pulled = try await GitSynchronizationService.perform(.pull, root: local)
        XCTAssertEqual(pulled.state.ahead, 1)
        await refused(.push, at: local, contains: "push forbidden")
    }
    func testDeletedRemoteBranchRequiresExplicitPush() async throws {
        let (local, _, bare) = try await fixture()
        _ = try await git(["update-ref", "-d", "refs/heads/main"], at: bare)
        await refused(.synchronize, at: local, contains: "deleted")
        let republished = try await GitSynchronizationService.perform(.push, root: local)
        XCTAssertTrue(republished.state.remoteBranchExists)
    }
    func testDifferentUpstreamBranchAndRemoteSelection() async throws {
        let (local, _, _) = try await fixture()
        _ = try await git(["branch", "-m", "writing"], at: local)
        try await commit("Writing branch", at: local)
        let state = try await GitService.inspect(root: local)
        XCTAssertEqual(state.branch, "writing"); XCTAssertEqual(state.remoteBranch, "main")
        let result = try await GitSynchronizationService.perform(.synchronize, root: local)
        XCTAssertEqual(result.state.upstream, "origin/main"); XCTAssertEqual(result.state.ahead, 0)
    }
    func testConnectionPreservesExistingRemoteAndRejectsNestedRoots() async throws {
        let (local, _, _) = try await fixture()
        do { _ = try await GitSynchronizationService.perform(.fetch, root: local, remoteName: "missing"); XCTFail("Never silently switch destinations") }
        catch { XCTAssertTrue(error.localizedDescription.contains("selected remote")) }
        let repo = try GitHubRepository("https://github.com/example/manuscript")
        do { try await GitService.connectGitHub(repo, remoteName: "origin", root: local); XCTFail("Must preserve origin") } catch {}
        try await GitService.connectGitHub(repo, remoteName: "github", root: local)
        let state = try await GitService.inspect(root: local, preferredRemote: "github"); XCTAssertEqual(state.remote?.github, repo)
        let nested = local.appendingPathComponent("chapters"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        do { try await GitService.initialize(root: nested); XCTFail("No nested repositories") } catch {}
        do { try await GitService.clone("unused", to: local); XCTFail("No overwrite") } catch {}
    }
    func testUnbornBranchAndAmbiguousDestinationAreRefused() async throws {
        try await GitService.initialize(root: root)
        _ = try await git(["remote", "add", "origin", root.appendingPathComponent("missing.git").path], at: root)
        await refused(.synchronize, at: root, contains: "first local commit")
        try await identity(root); try await commit("Initial", at: root)
        _ = try await git(["remote", "set-url", "--push", "origin", "/different.git"], at: root)
        await refused(.push, at: root, contains: "another")
    }
    func testIsolatedKeychainRoundTrip() throws {
        // Unique test-only service; never inspect or modify an existing credential.
        let store = GitHubCredentialStore(service: "app.texium.tests.github." + UUID().uuidString)
        let account = "texium-verification"
        defer { try? store.remove(account: account) }
        XCTAssertNil(try store.token(account: account))
        try store.save(token: "synthetic-test-token", account: account)
        XCTAssertEqual(try store.token(account: account), "synthetic-test-token")
        try store.save(token: "synthetic-replacement-token", account: account)
        XCTAssertEqual(try store.token(account: account), "synthetic-replacement-token")
        try store.remove(account: account)
        XCTAssertNil(try store.token(account: account))
    }
    func testGitHubURLsAndCredentialIsolation() throws {
        for value in ["https://github.com/owner/project", "https://github.com/owner/project.git/", "git@github.com:owner/project.git", "ssh://git@github.com/owner/project.git"] {
            let repo = try GitHubRepository(value); XCTAssertEqual(repo.fullName, "owner/project"); XCTAssertEqual(repo.webURL.absoluteString, "https://github.com/owner/project")
        }
        for value in ["https://github.com.evil.test/a/b", "http://github.com/a/b", "https://token@github.com/a/b", "https://github.com/a/b/tree/main", "https://github.com/a/b?token=x", "git@github.com:../repo", "https://github.com/a/%2Fetc", "https://github.com:443/a/b"] {
            XCTAssertThrowsError(try GitHubRepository(value), value)
        }
        var reads = 0
        for input in ["protocol=https\nhost=evil.test\n\n", "protocol=http\nhost=github.com\n\n", "protocol=https\nhost=github.com\nusername=other\n\n", "protocol=https\nhost=github.com\nhost=evil.test\n\n"] {
            let result = try GitHubCredentialProtocol.response(input: input, action: "get", account: "writer") { reads += 1; return "synthetic-secret" }
            XCTAssertEqual(result, "")
        }
        for action in ["store", "erase"] { _ = try GitHubCredentialProtocol.response(input: "protocol=https\nhost=github.com\n\n", action: action, account: "writer") { reads += 1; return "synthetic-secret" } }
        XCTAssertEqual(reads, 0)
        let valid = try GitHubCredentialProtocol.response(input: "protocol=https\nhost=github.com\n\n", action: "get", account: "writer") { "synthetic-secret" }
        XCTAssertEqual(valid, "username=writer\npassword=synthetic-secret\n\n")
        let auth = GitAuthentication(executable: URL(fileURLWithPath: "/App's Folder/TeXium"), account: "writer")
        XCTAssertFalse(auth.configuration.joined().contains("synthetic-secret"))
        XCTAssertTrue(auth.configuration.contains("http.followRedirects=false"))
    }
}
