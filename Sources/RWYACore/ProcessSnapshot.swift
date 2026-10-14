import Foundation

public struct ProcessSample: Equatable, Sendable {
    public let command: String   // full executable path as reported by ps
    public let cpu: Double       // instantaneous %CPU
    public init(command: String, cpu: Double) { self.command = command; self.cpu = cpu }
}

public protocol ProcessSource: Sendable {
    func snapshot() -> [ProcessSample]
}

/// Reads the process table through `ps`.
public struct PSProcessSource: ProcessSource {
    public init() {}

    public func snapshot() -> [ProcessSample] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pcpu=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " "),
                  let cpu = Double(trimmed[..<space]) else { return nil }
            let command = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
            return ProcessSample(command: command, cpu: cpu)
        }
    }
}
