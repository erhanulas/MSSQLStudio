import AppKit
import Testing
import SQLServerKit
@testable import MSSQLStudio

@MainActor struct ObjectExplorerTests {
  @Test func procedureFunctionAndTriggerIconsHaveDistinctSemanticsAndParentOwnership() throws {
    let server=ConnectedServer(profile:ServerProfile(),password:"");server.online=false
    func node(_ f:Folder,_ detail:String="")->TreeNode {TreeNode("Example",kind:.object(f),server:server,item:.init(id:1,name:"Example",schema:"dbo",detail:detail))}
    let procedure=node(.procedures),function=node(.functions)
    let enabled=node(.triggers,"SQL_TRIGGER, Enabled"),disabled=node(.triggers,"SQL_TRIGGER, Disabled")
    #expect(procedure.icon != function.icon)
    #expect(enabled.icon != disabled.icon)
    #expect(disabled.displayTitle.contains("Disabled"))
    #expect(enabled.displayTitle.contains("Enabled"))
    for n in [procedure,function,enabled,disabled] {#expect(NSImage(systemSymbolName:n.icon,accessibilityDescription:nil) != nil)}
    let table=node(.tables),folder=TreeNode("Triggers",kind:.folder(.triggers),server:server,item:table.item)
    table.children=[folder];folder.children=[enabled,disabled]
    #expect(enabled.ownerObject === table)
    #expect(disabled.parent === folder)
    let properties=ObjectManagementUIFixture.catalog("SELECT t.parent_class_desc FROM sys.triggers t WHERE t.object_id=1006;")
    #expect(properties.results.first?.values.first?[0] == "TR_CustomersAudit")
    #expect(properties.results.first?.values.first?[1] == "Disabled")
  }
}
