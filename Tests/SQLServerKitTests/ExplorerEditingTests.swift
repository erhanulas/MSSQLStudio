import Foundation
import Testing
@testable import SQLServerKit
struct ExplorerEditingTests {
  @Test func ddlRefreshTargetsIgnoreStringsAndComments() {
    let targets = ModuleEditing.changedObjects("-- DROP TABLE wrong\nALTER PROCEDURE [dbo].[one] AS SELECT N'CREATE TABLE wrong';")
    #expect(targets.count == 1)
    #expect(targets.first?.name == "dbo.one")
    #expect(targets.first?.folder == .procedures)
  }
  @Test func boundedSearchEscapesLiteralAndRestrictsType() {
    let sql = Catalog.searchObjects("a'%_", operation: 0, folder: .procedures)
    #expect(sql.contains("TOP (501)"))
    #expect(sql.contains("N'a''%_'"))
    #expect(sql.contains("'P','PC'"))
    #expect(sql.contains("CHARINDEX"))
    #expect(!sql.contains(" LIKE "))
    #expect(Catalog.searchObjects("dbo.Test", operation: 1, folder: .tables).contains("o.name="))
    #expect(Catalog.searchObjects("Test", operation: 4, folder: nil).contains(")=0"))
  }
  @Test func alterPreservesCommentsBodyAndExistingAlter() {
    let source = "-- CREATE fake\nCREATE OR ALTER PROCEDURE [dbo].[test] AS SELECT N'CREATE';"
    let result = ModuleEditing.alter(source)
    #expect(result == "-- CREATE fake\nALTER PROCEDURE [dbo].[test] AS SELECT N'CREATE';")
    #expect(ModuleEditing.alter(result) == result)
    #expect(ModuleEditing.difference(original: source, edited: result) == "Değişiklik yok.")
    #expect(ModuleEditing.difference(original: source, edited: result + "\nSELECT 2;").contains("+ SELECT 2;"))
  }
}
