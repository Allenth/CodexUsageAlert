import Foundation
import UsageCore

do {
    let snapshot = try CodexAppServerClient().fetchSnapshot()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = CommandLine.arguments.contains("--pretty")
        ? [.prettyPrinted, .sortedKeys]
        : [.sortedKeys]
    let data = try encoder.encode(snapshot)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
} catch {
    let message = error.localizedDescription + "\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
