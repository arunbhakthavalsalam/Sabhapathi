import Foundation
import Combine
import Darwin

/// Manages the lifecycle of the Python FastAPI backend process.
final class PythonBackendManager: ObservableObject {
    static let shared = PythonBackendManager()

    @Published var isRunning = false
    @Published var lastError: String?

    private var process: Process?
    private var healthTimer: Timer?
    private var backendOutput = ""
    private let port = 9457
    private let host = "127.0.0.1"
    private let logFileURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Sabhapathi")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("backend.log")
    }()

    var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    func start() {
        guard process == nil else { return }
        terminateStaleBackendListeners()

        let process = Process()
        self.process = process
        backendOutput = ""
        lastError = nil

        let backendRoot = findBackendRoot()
        let pythonPath = findPython()
        process.executableURL = URL(fileURLWithPath: pythonPath)

        process.arguments = ["-m", "sabhapathi_backend"]
        process.currentDirectoryURL = URL(fileURLWithPath: backendRoot)

        // Set environment
        var env = ProcessInfo.processInfo.environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        appendLog("=== Backend start ===")
        appendLog("python: \(pythonPath)")
        appendLog("backendRoot: \(backendRoot)")

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            DispatchQueue.main.async {
                self?.backendOutput.append(output)
                self?.appendLog(output)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.isRunning = false
                if let process = self?.process, process.terminationStatus != 0 {
                    let message = self?.backendOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.lastError = message?.isEmpty == false
                        ? message
                        : "Python backend exited with code \(process.terminationStatus)."
                }
                self?.process = nil
            }
        }

        do {
            try process.run()
            startHealthPolling()
        } catch {
            lastError = "Failed to start Python backend: \(error.localizedDescription)"
            self.process = nil
        }
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let process {
            appendLog("=== Backend stop requested (pid \(process.processIdentifier)) ===")
            stopProcess(process)
        }
        process = nil
        isRunning = false
    }

    private func startHealthPolling() {
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }

    private func checkHealth() {
        let url = baseURL.appendingPathComponent("health")
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self?.isRunning = true
                    self?.lastError = nil
                    // Slow down polling once healthy
                    self?.healthTimer?.invalidate()
                    self?.healthTimer = Timer.scheduledTimer(
                        withTimeInterval: 10.0, repeats: true
                    ) { [weak self] _ in
                        self?.checkHealth()
                    }
                } else if let error {
                    self?.isRunning = false
                    if self?.process == nil {
                        self?.lastError = "Backend unavailable: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    private func findPython() -> String {
        // Prefer bundled/dev virtualenvs so the app uses the same dependencies as the backend setup.
        let candidates = [
            Bundle.main.resourcePath.map { "\($0)/PythonBackend/venv/bin/python3" },
            Bundle.main.resourcePath.map { "\($0)/python/bin/python3" },
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("PythonBackend")
                .appendingPathComponent("venv")
                .appendingPathComponent("bin")
                .appendingPathComponent("python3")
                .path,
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ].compactMap { $0 }

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return "/usr/bin/python3"
    }

    private func findBackendRoot() -> String {
        if let bundledRoot = Bundle.main.resourceURL?
            .appendingPathComponent("PythonBackend")
            .path,
           FileManager.default.fileExists(atPath: bundledRoot) {
            return bundledRoot
        }

        return URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PythonBackend")
            .path
    }

    private func appendLog(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    private func stopProcess(_ process: Process) {
        if !process.isRunning { return }

        process.terminate()
        if waitForExit(process, timeout: 1.5) { return }

        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(process, timeout: 1.0)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return !process.isRunning
    }

    private func terminateStaleBackendListeners() {
        let pids = listeningPIDs(on: port).filter { $0 != getpid() }
        guard !pids.isEmpty else { return }

        appendLog("Found existing listeners on port \(port): \(pids.map(String.init).joined(separator: ", "))")

        for pid in pids {
            kill(pid, SIGTERM)
        }

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))

        let stubbornPIDs = listeningPIDs(on: port).filter { pids.contains($0) }
        for pid in stubbornPIDs {
            appendLog("Force killing stale backend listener \(pid)")
            kill(pid, SIGKILL)
        }
    }

    private func listeningPIDs(on port: Int) -> [pid_t] {
        let lsofCandidates = [
            "/usr/sbin/lsof",
            "/usr/bin/lsof",
        ]

        guard let lsofPath = lsofCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            appendLog("lsof not available; cannot inspect port \(port)")
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-n", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            appendLog("Failed to inspect port \(port): \(error.localizedDescription)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
    }
}
