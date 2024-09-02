import ChaosTesting
import Foundation
import Testing

@testable import ActionBuilderCore

@Test
func testParsingPackageMacPlatform() async throws {
  let examplePackage = Bundle.module.url(forResource: "Example-mac", withExtension: "package")!
  let repo = try await Repo(forPackage: examplePackage)
  #expect(repo.enabledCompilers.map { $0.id } == [.swift56, .latestRelease])
  #expect(repo.enabledPlatforms.map { $0.id } == [.linux, .macOS])
}

@Test
func testParsingPackageMultiPlatform() async throws {
  let examplePackage = Bundle.module.url(forResource: "Example-multi", withExtension: "package")!
  let repo = try await Repo(forPackage: examplePackage)
  #expect(repo.compilers == [.swift56, .swiftLatest])
  #expect(repo.platforms == [.iOS, .linux, .macOS, .tvOS])
}

@Test
func testParsingPackageConfigFile() async throws {
  let examplePackage = Bundle.module.url(forResource: "Example-config", withExtension: "package")!
  let repo = try await Repo(forPackage: examplePackage)
  #expect(repo.name == "ConfigTestPackage")
  #expect(repo.owner == "ConfigTestOwner")
  #expect(repo.compilers == [.swift55, .swiftNightly])
  #expect(repo.platforms == [.macOS, .linux])
  #expect(repo.testMode == .test)
  #expect(!repo.header)
  #expect(!repo.uploadLogs)
  #expect(!repo.postSlackNotification)
  #expect(!repo.firstlast)
}

@Test
func testYAMLmacOSSwift56() async {
  let expected = """
      # --------------------------------------------------------------------------------
      # This workflow was automatically generated by Test Generator 1.2.3 (456).
      # (see https://test.com for more details)
      # --------------------------------------------------------------------------------

      name: Tests

      on: [push, pull_request]

      jobs:

          macOS-swift56:
              name: macOS (Swift 5.6)
              runs-on: macos-12
              steps:
              - name: Checkout
                uses: actions/checkout@v1
              - name: Make Logs Directory
                run: mkdir logs
              - name: Xcode Version
                run: |
                  ls -d /Applications/Xcode*
                  sudo xcode-select -s /Applications/Xcode_13.4.1.app
                  xcodebuild -version
                  swift --version
              - name: Swift Version
                run: swift --version
              - name: Test (release)
                run: swift test --configuration release -Xswiftc -enable-testing
              - name: Upload Logs
                uses: actions/upload-artifact@v1
                if: always()
                with:
                  name: logs
                  path: logs
    """

  let generator = Generator(
    name: "Test Generator", version: "1.2.3 (456)", link: "https://test.com")
  let repo = Repo(name: "testRepo", owner: "testOwner", platforms: [.macOS], compilers: [.swift56])

  let source = generator.workflow(for: repo)
  #expect(source.removingIndentation == expected.removingIndentation)
}

@Test
func testYAMLiOSSwift56() {
  let expected = """
      # --------------------------------------------------------------------------------
      # This workflow was automatically generated by Test Generator 1.2.3 (456).
      # (see https://test.com for more details)
      # --------------------------------------------------------------------------------

      name: Tests

      on: [push, pull_request]

      jobs:

          xcode-swift56:
              name: iOS (Swift 5.6, Xcode 13.4.1)
              runs-on: macos-12
              steps:
              - name: Checkout
                uses: actions/checkout@v1
              - name: Make Logs Directory
                run: mkdir logs
              - name: Xcode Version
                run: |
                  ls -d /Applications/Xcode*
                  sudo xcode-select -s /Applications/Xcode_13.4.1.app
                  xcodebuild -version
                  swift --version
              - name: XC Pretty
                run: sudo gem install xcpretty-travis-formatter
              - name: Detect Workspace & Scheme (iOS)
                run: |
                  WORKSPACE="testRepo.xcworkspace"
                  if [[ ! -e "$WORKSPACE" ]]
                  then
                  WORKSPACE="."
                  GOTPACKAGE=$(xcodebuild -workspace . -list | (grep testRepo-Package || true))
                  if [[ $GOTPACKAGE != "" ]]
                  then
                  SCHEME="testRepo-Package"
                  else
                  SCHEME="testRepo"
                  fi
                  else
                  SCHEME="testRepo-iOS"
                  fi
                  echo "set -o pipefail; export PATH='swift-latest:$PATH'; WORKSPACE='$WORKSPACE'; SCHEME='$SCHEME'" > setup.sh
              - name: Test (iOS Release)
                run: |
                  source "setup.sh"
                  echo "Testing workspace $WORKSPACE scheme $SCHEME."
                  xcodebuild test -workspace "$WORKSPACE" -scheme "$SCHEME" -destination "name=iPhone 11" -configuration Release CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ENABLE_TESTABILITY=YES | tee logs/xcodebuild-iOS-test-release.log | xcpretty
              - name: Upload Logs
                uses: actions/upload-artifact@v1
                if: always()
                with:
                  name: logs
                  path: logs
    """

  let generator = Generator(
    name: "Test Generator", version: "1.2.3 (456)", link: "https://test.com")
  let repo = Repo(name: "testRepo", owner: "testOwner", platforms: [.iOS], compilers: [.swift56])

  let source = generator.workflow(for: repo).trimmingCharacters(in: .whitespacesAndNewlines)

  #expect(source.removingIndentation == expected.removingIndentation)
}

extension String {
  /// Removes leading and trailing whitespace from each line in a string,
  /// and removes empty lines.
  var removingIndentation: String {
    let lines = self.components(separatedBy: .newlines)
    let trimmed =
      lines
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { $0.isEmpty == false }

    return trimmed.joined(separator: "\n")
  }
}
