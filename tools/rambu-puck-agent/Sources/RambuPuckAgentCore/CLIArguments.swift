import Foundation

public enum CLIArguments: Equatable, Sendable {
    case pair(code: String, name: String)
    case listen(detectAudio: Bool)
    case help

    public static func parse(_ arguments: [String]) throws -> CLIArguments {
        guard let command = arguments.first else { return .help }
        if command == "--help" || command == "-h" || command == "help" {
            return .help
        }
        if command == "listen" {
            if arguments.count == 1 {
                return .listen(detectAudio: false)
            }
            guard arguments == ["listen", "--detect-audio"] else {
                throw CLIError.invalidArguments
            }
            return .listen(detectAudio: true)
        }
        if command == "pair" {
            guard arguments.count == 5,
                  let codeIndex = arguments.firstIndex(of: "--code"),
                  let nameIndex = arguments.firstIndex(of: "--name"),
                  codeIndex + 1 < arguments.count,
                  nameIndex + 1 < arguments.count else {
                throw CLIError.invalidArguments
            }
            let code = arguments[codeIndex + 1]
            let name = arguments[nameIndex + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard code.count == 6, code.allSatisfy(\.isNumber), !name.isEmpty else {
                throw CLIError.invalidArguments
            }
            return .pair(code: code, name: name)
        }
        throw CLIError.invalidArguments
    }
}

public enum CLIError: Error, CustomStringConvertible {
    case invalidArguments

    public var description: String {
        "Invalid arguments. Run rambu-puck-agent --help for usage."
    }
}
