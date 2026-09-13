import Foundation

public struct TeXDistribution: Sendable {
    public let directory: URL
    public let tools: [String: URL]
    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = directory.path + ":/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        // TeX still needs project-relative reads. Its paranoid output policy
        // prevents TeX itself from writing to arbitrary absolute paths.
        env["openout_any"] = "p"
        return env
    }
    public static func discover(customPath: String = "") -> TeXDistribution? {
        var paths = customPath.isEmpty ? [] : [customPath]
        paths += ["/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for path in paths {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let names = ["latexmk", "pdflatex", "xelatex", "lualatex", "latex", "bibtex", "biber", "synctex", "texcount", "dvipdfmx"]
            let tools = Dictionary(uniqueKeysWithValues: names.compactMap { name -> (String, URL)? in
                let url = directory.appendingPathComponent(name)
                return FileManager.default.isExecutableFile(atPath: url.path) ? (name, url) : nil
            })
            if tools["pdflatex"] != nil || tools["xelatex"] != nil || tools["lualatex"] != nil { return TeXDistribution(directory: directory, tools: tools) }
        }
        return nil
    }
}
public struct BuildResult: Sendable {
    public let status: Int32
    public let log: String
    public let diagnostics: [Diagnostic]
    public let pdfURL: URL?
    public let syncTeXURL: URL?
    public let elapsed: TimeInterval
}
public enum CompilationService {
    public static let buildFolder = ".texium-build"
    public static func buildDirectory(root: URL) throws -> URL {
        let literal = root.appendingPathComponent(buildFolder, isDirectory: true)
        if (try? literal.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw TeXiumError.message("The reserved .texium-build directory must not be a symbolic link. Rename that link before compiling so generated-file cleanup cannot affect source files.")
        }
        return try ProjectFileSystem.resolve(buildFolder, in: root)
    }
    public static func build(root: URL, configuration: BuildConfiguration, distribution: TeXDistribution, scratch: Bool = false, draft: Bool = false, output: (@Sendable (String) -> Void)? = nil) async throws -> BuildResult {
        let start = Date()
        let main = try ProjectFileSystem.resolve(configuration.mainFile, in: root)
        guard main.pathExtension == "tex", FileManager.default.fileExists(atPath: main.path) else { throw TeXiumError.message("Choose an existing main .tex document in the Project menu.") }
        let build = try buildDirectory(root: root)
        let identity = build.appendingPathComponent("project-root.txt")
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        // latexmk and SyncTeX caches contain absolute source paths. A copied or
        // moved project must rebuild rather than reuse the previous location.
        let previousRoot = try? String(contentsOf: identity, encoding: .utf8)
        if scratch || previousRoot != canonicalRoot { try clearAuxiliary(root: root) }
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try canonicalRoot.write(to: identity, atomically: true, encoding: .utf8)
        let job = main.deletingPathExtension().lastPathComponent
        // latexmk configuration files can execute Perl before shell-escape flags
        // take effect. -norc is deliberate, including for unknown project folders.
        guard let latexmk = distribution.tools["latexmk"] else { throw TeXiumError.message("latexmk is required for reliable multi-pass bibliography and reference builds. Install latexmk with your TeX distribution, then choose its binary folder in Settings → LaTeX.") }
        guard distribution.tools[configuration.engine.rawValue] != nil else { throw TeXiumError.message("\(configuration.engine.title) is unavailable in \(distribution.directory.path). Choose an installed engine or another TeX folder.") }
        var args = ["-norc", configuration.engine.latexmkFlag, "-interaction=nonstopmode", "-file-line-error", "-synctex=1", configuration.shellPolicy.flag, "-outdir=" + buildFolder]
        if draft && configuration.engine == .pdfLaTeX { args.append("-draftmode") }
        args += ["./" + configuration.mainFile]
        output?(([latexmk.path] + args).joined(separator: " ") + "\n")
        let result = try await ProcessRunner().run(executable: latexmk, arguments: args, directory: root, environment: distribution.environment, output: output)
        let logURL = build.appendingPathComponent(job + ".log")
        let finalTeXLog = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        let log = result.output + "\n" + finalTeXLog
        try log.write(to: build.appendingPathComponent("texium-build.log"), atomically: true, encoding: .utf8)
        let generatedPDF = build.appendingPathComponent(job + ".pdf")
        let generatedSync = build.appendingPathComponent(job + ".synctex.gz")
        var stablePDF: URL?; var stableSync: URL?
        // A failed build must never replace the last successful PDF or SyncTeX.
        if result.status == 0 && !draft && FileManager.default.fileExists(atPath: generatedPDF.path) {
            let stable = try ProjectFileSystem.resolve(buildFolder + "/preview", in: root)
            try FileManager.default.createDirectory(at: stable, withIntermediateDirectories: true)
            stablePDF = stable.appendingPathComponent(job + ".pdf")
            try Data(contentsOf: generatedPDF).write(to: stablePDF!, options: .atomic)
            if FileManager.default.fileExists(atPath: generatedSync.path) {
                stableSync = stable.appendingPathComponent(job + ".synctex.gz")
                try Data(contentsOf: generatedSync).write(to: stableSync!, options: .atomic)
            }
        }
        return BuildResult(status: result.status, log: log, diagnostics: DiagnosticsParser.parse(finalTeXLog.isEmpty ? log : finalTeXLog, mainFile: configuration.mainFile), pdfURL: stablePDF, syncTeXURL: stableSync, elapsed: Date().timeIntervalSince(start))
    }
    public static func clearAuxiliary(root: URL) throws {
        let build = try buildDirectory(root: root)
        guard FileManager.default.fileExists(atPath: build.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: build, includingPropertiesForKeys: nil) where url.lastPathComponent != "preview" {
            try FileManager.default.removeItem(at: url)
        }
    }
}
