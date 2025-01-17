// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
//  Created by Sam Deane on 19/02/20.
//  All code (c) 2020 - present day, Elegant Chaos Limited.
// -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

public final class Platform: Identifiable, Sendable {
  public let id: ID
  public let name: String
  public let subPlatforms: [Platform]
  public let xcodeDestination: String?

  public enum ID: String, Codable, CaseInsensitiveRawRepresentable, Sendable {
    case macOS
    case iOS
    case tvOS
    case watchOS
    case catalyst
    case linux
    case xcode
  }

  public static let platforms = [
    Platform(.macOS, name: "macOS"),
    Platform(.iOS, name: "iOS", xcodeDestination: "iPhone 11"),
    Platform(.tvOS, name: "tvOS", xcodeDestination: "Apple TV"),
    Platform(.watchOS, name: "watchOS", xcodeDestination: "Apple Watch Series 5 - 44mm"),
    Platform(.linux, name: "Linux"),
  ]

  public init(
    _ id: ID, name: String, xcodeDestination: String? = nil, subPlatforms: [Platform] = []
  ) {
    self.id = id
    self.name = name
    self.xcodeDestination = xcodeDestination
    self.subPlatforms = subPlatforms
  }

  public var label: String {
    if xcodeDestination == nil {
      return name
    }
    else {
      return "\(name)"
    }
  }

  public func jobName(with compiler: Compiler) -> String {
    if !subPlatforms.isEmpty {
      switch compiler.mac {
        case .xcode(let version, _), .toolchain(let version, _, _):
          return "\(name) (\(compiler.name), Xcode \(version))"
      }
    }

    return "\(name) (\(compiler.name))"
  }

  public func yaml(repo: Repo, compilers: [Compiler], configurations: [Configuration]) -> String {
    let package = repo.name
    let shouldTest = repo.testMode != .build

    var yaml = ""
    var xcodeToolchain: String? = nil
    var xcodeVersion: String? = nil

    for compiler in compilers {
      var job =
        """

            \(id)-\(compiler.id):
                name: \(jobName(with: compiler))
        """

      containerYAML(&job, compiler, &xcodeToolchain, &xcodeVersion)
      commonYAML(&job)

      if let branch = xcodeToolchain, let version = xcodeVersion {
        selectToolchainYAML(&job, branch, version)
      }
      else if !subPlatforms.isEmpty, let version = xcodeVersion {
        selectXcodeYAML(&job, version)
      }
      else {
        selectSwiftYAML(&job, compiler: compiler)
      }

      if subPlatforms.isEmpty {
        job.append(
          runSwiftYAML(
            configurations: configurations, test: shouldTest,
            customToolchain: xcodeToolchain != nil, compiler: compiler))
      }
      else {
        job.append(xcodebuildCommonYAML())
        for platform in subPlatforms {
          job.append(
            platform.runXcodebuildYAML(
              configurations: configurations, package: package, test: shouldTest, compiler: compiler
            ))
        }
      }

      if repo.uploadLogs {
        uploadYAML(&job)
      }

      if repo.postSlackNotification {
        job.append(notifyYAML(compiler: compiler))
      }

      yaml.append("\(job)\n\n")
    }

    return yaml
  }

  fileprivate func selectSwiftYAML(
    _ yaml: inout String, compiler: Compiler
  ) {
    yaml.append(
      """

              - name: Select Swift
                uses: swift-actions/setup-swift@v2
                with:
                  swift-version: "\(compiler.short)"
      """)
  }

  fileprivate func runSwiftYAML(
    configurations: [Configuration], test: Bool, customToolchain: Bool, compiler: Compiler
  ) -> String {
    var yaml = """

              - name: Check Swift Version
                run: swift --version
      """

    let pathFix = customToolchain ? "export PATH=\"swift-latest:$PATH\"; " : ""
    if test {
      for config in configurations {
        let isRelease = config == .release
        var enableDiscovery: [Compiler.ID] = [.swift52, .swift53, .swift54, .swift55]
        if !isRelease { enableDiscovery.append(.swift51) }
        let buildForTestingFlag = isRelease ? " --enable-testing" : ""
        let discoveryFlag = enableDiscovery.contains(compiler.id) ? " --enable-test-discovery" : ""
        yaml.append(
          """

                  - name: Build (\(config))
                    run: \(pathFix)swift build --build-tests --configuration \(config)\(buildForTestingFlag)
                  - name: Test (\(config))
                    run: \(pathFix)swift test --skip-build --configuration \(config)\(discoveryFlag)
          """
        )
      }
    }
    else {
      for config in configurations {
        yaml.append(
          """

                  - name: Build (\(config))
                    run: \(pathFix)swift build -c \(config)
          """
        )
      }
    }

    return yaml
  }

  fileprivate func xcodebuildCommonYAML() -> String {
    var yaml = ""
    yaml.append(
      """

              - name: XC Pretty
                run: sudo gem install xcpretty-travis-formatter
      """
    )
    return yaml
  }

  fileprivate func runXcodebuildYAML(
    configurations: [Configuration], package: String, test: Bool, compiler: Compiler
  ) -> String {
    var yaml = ""
    let destinationName = xcodeDestination ?? ""
    let destination = destinationName.isEmpty ? "" : "-destination \"name=\(destinationName)\""
    yaml.append(
      """

              - name: Detect Workspace & Scheme (\(name))
                run: |
                  WORKSPACE="\(package).xcworkspace"
                  if [[ ! -e "$WORKSPACE" ]]
                  then
                  WORKSPACE="."
                  GOTPACKAGE=$(xcodebuild -workspace . -list | (grep \(package)-Package || true))
                  if [[ $GOTPACKAGE != "" ]]
                  then
                  SCHEME="\(package)-Package"
                  else
                  SCHEME="\(package)"
                  fi
                  else
                  SCHEME="\(package)-\(name)"
                  fi
                  echo "set -o pipefail; export PATH='swift-latest:$PATH'; WORKSPACE='$WORKSPACE'; SCHEME='$SCHEME'" > setup.sh
      """
    )

    if test && compiler.supportsTesting(on: id) {
      for config in configurations {
        let extraArgs = config == .release ? "ENABLE_TESTABILITY=YES" : ""
        yaml.append(
          """

                  - name: Test (\(name) \(config.name))
                    run: |
                      source "setup.sh"
                      echo "Testing workspace $WORKSPACE scheme $SCHEME."
                      xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME" \(destination) -configuration \(config.xcodeID) CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \(extraArgs) | tee logs/xcodebuild-\(id)-test-\(config).log | xcpretty
          """
        )
      }
    }
    else {
      for config in configurations {
        let extraArgs = config == .release ? "ENABLE_TESTABILITY=YES" : ""
        yaml.append(
          """

                  - name: Build (\(name) \(config))
                    run: |
                      source "setup.sh"
                      echo "Building workspace $WORKSPACE scheme $SCHEME."
                      xcodebuild clean build -workspace "$WORKSPACE" -scheme "$SCHEME" \(destination) -configuration \(config.xcodeID) CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \(extraArgs) | tee logs/xcodebuild-\(id)-build-\(config).log | xcpretty
          """
        )
      }
    }

    return yaml
  }

  fileprivate func uploadYAML(_ yaml: inout String) {
    yaml.append(
      """

              - name: Upload Logs
                uses: actions/upload-artifact@v4
                if: always()
                with:
                  name: logs
                  path: logs
      """
    )
  }

  fileprivate func notifyYAML(compiler: Compiler) -> String {
    var yaml = ""
    yaml.append(
      """

              - name: Slack Notification
                uses: elegantchaos/slatify@master
                if: always()
                with:
                  type: ${{ job.status }}
                  job_name: '\(name) (\(compiler.name))'
                  mention_if: 'failure'
                  url: ${{ secrets.SLACK_WEBHOOK }}
      """
    )
    return yaml
  }

  fileprivate func selectToolchainYAML(_ yaml: inout String, _ branch: String, _ version: String) {
    let download =
      """
                  branch="\(branch)"
                  wget --quiet https://download.swift.org/$branch/xcode/latest-build.yml
                  grep "download:" < latest-build.yml > filtered.yml
                  sed -e 's/-osx.pkg//g' filtered.yml > stripped.yml
                  sed -e 's/:[^:\\/\\/]/YML="/g;s/$/"/g;s/ *=/=/g' stripped.yml > snapshot.sh
                  source snapshot.sh
                  echo "Installing Toolchain: $downloadYML"
                  wget --quiet https://swift.org/builds/$branch/xcode/$downloadYML/$downloadYML-osx.pkg
                  sudo installer -pkg $downloadYML-osx.pkg -target /
                  ln -s "/Library/Developer/Toolchains/$downloadYML.xctoolchain/usr/bin" swift-latest
      """

    yaml.append(
      """

              - name: Install Toolchain
                run: |
      \(download)
                  ls -d /Applications/Xcode*
                  sudo xcode-select -s /Applications/Xcode_\(version).app
                  swift --version
              - name: Xcode Version
                run: |
                  xcodebuild -version
                  xcrun swift --version
      """
    )
  }

  fileprivate func selectXcodeYAML(_ yaml: inout String, _ version: String) {
    yaml.append(
      """

              - name: Select Xcode Version
                run: |
                  ls -d /Applications/Xcode*
                  sudo xcode-select -s /Applications/Xcode_\(version).app
                  xcodebuild -version
                  swift --version
      """
    )
  }

  fileprivate func containerYAML(
    _ yaml: inout String, _ compiler: Compiler, _ xcodeToolchain: inout String?,
    _ xcodeVersion: inout String?
  ) {
    switch id {
      case .linux:
        yaml.append(
          """

                  runs-on: ubuntu-22.04
          """
        )

      default:
        let macosImage: String
        switch compiler.mac {
          case .xcode(let version, let image):
            xcodeVersion = version
            macosImage = image

          case .toolchain(let version, let branch, let image):
            xcodeVersion = version
            xcodeToolchain = branch
            macosImage = image
            yaml.append(
              """

                      env:
                          TOOLCHAINS: swift
              """
            )
        }

        yaml.append(
          """

                  runs-on: \(macosImage)
          """
        )

    }
  }

  fileprivate func commonYAML(_ yaml: inout String) {
    yaml.append(
      """

              steps:
              - name: Checkout
                uses: actions/checkout@v4
              - name: Make Logs Directory
                run: mkdir logs
      """
    )
  }

}
