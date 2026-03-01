import Foundation

let args = CommandLine.arguments
let cwd = FileManager.default.currentDirectoryPath

if args.contains("--help") || args.contains("-h") {
    print("""
    usage: written [path]

      written              Open current directory with sidebar
      written <folder>     Open folder with sidebar
      written <file.txt>   Open file (creates if it doesn't exist)
      written <name>       Create and open name.txt
    """)
    exit(0)
}

// Resolve the argument
let arg: String? = args.count > 1 ? args[1] : nil
let supportedExtensions: Set<String> = ["txt"]

func resolveToAbsolute(_ path: String) -> String {
    let absolute = path.hasPrefix("/") ? path : (cwd as NSString).appendingPathComponent(path)
    return (absolute as NSString).standardizingPath
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

if let arg = arg {
    let resolved = resolveToAbsolute(arg)
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: resolved, isDirectory: &isDir)

    if exists && isDir.boolValue {
        // It's a directory — open with sidebar
        let encoded = resolved.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolved
        let urlString = "written://open?folder=\(encoded)"
        process.arguments = [urlString]
    } else {
        let ext = (resolved as NSString).pathExtension.lowercased()

        // Reject unsupported file extensions
        if !ext.isEmpty && !supportedExtensions.contains(ext) {
            print("That isn't plaintext, sillygoose")
            exit(1)
        }

        var filePath = resolved

        if !exists {
            if ext.isEmpty {
                // No extension on new file — append .txt
                filePath = resolved + ".txt"
            }
            FileManager.default.createFile(atPath: filePath, contents: nil)
        }

        let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filePath
        let urlString = "written://open?file=\(encoded)"
        process.arguments = [urlString]
    }
} else {
    // No args — open sidebar in current directory
    let encoded = cwd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cwd
    let urlString = "written://open?folder=\(encoded)"
    process.arguments = [urlString]
}

try? process.run()
process.waitUntilExit()
