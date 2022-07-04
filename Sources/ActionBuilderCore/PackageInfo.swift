// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//  Created by Sam Deane on 04/07/22.
//  All code (c) 2022 - present day, Elegant Chaos Limited.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

import Foundation
import Runner

/// Some minimal Swift Package Manager package information.
struct PackageInfo: Codable {
    let toolsVersion: ToolsVersion
    let platforms: [PlatformInfo]
    
    init(from url: URL) throws {
        let spm = Runner(command: "swift", cwd: url)
        let output = try spm.sync(arguments: ["package", "dump-package"])
        guard output.status == 0 else {
            throw SettingsError.parsingFailed
        }
        
        guard let jsonData = output.stdout.data(using: .utf8) else {
            throw SettingsError.corruptData
        }
        
        let decoder = JSONDecoder()
        self = try decoder.decode(PackageInfo.self, from: jsonData)
    }
    
    struct ToolsVersion: Codable {
        let _version: String
    }
    
    struct PlatformInfo: Codable {
        let platformName: String
        let version: String
    }
}