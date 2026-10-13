import Foundation
import Testing
@testable import SQLServerKit

struct ODBCDriverSetupTests {
  @Test func officialPlanIsScopedAndNeverElevatesOrInstallsHomebrew() {
    for major in [4,5,6,7] {
      let commands=ODBCDriverSetup.installationCommands(homebrewMajor:major)
      #expect(commands.first?.arguments == ["tap","microsoft/mssql-release","https://github.com/Microsoft/homebrew-mssql-release"])
      #expect(commands.last?.arguments == ["install","microsoft/mssql-release/msodbcsql18"])
      #expect(commands.contains {$0.arguments.first == "trust"} == (major >= 6))
      #expect(commands.allSatisfy {!$0.arguments.contains("sudo") && !$0.arguments.contains("update") && !$0.arguments.contains("mssql-tools18")})
    }
  }
  @Test func processOutputAndErrorsAreReportedWithoutRunningInstaller() async throws {
    let output=try await ODBCDriverSetup.run("/usr/bin/printf",arguments:["%s","synthetic progress"])
    #expect(output == "synthetic progress")
    await #expect(throws:SQLFailure.self) {try await ODBCDriverSetup.run("/usr/bin/false",arguments:[])}
  }
}
