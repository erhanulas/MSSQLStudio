import AppKit
import SQLServerKit
import SwiftUI

extension WorkbenchController {
  func showAgentHistory(_ node:TreeNode) {
    presentAgent(AgentHistoryPanel(server:node.server,job:node.objectFolder == .jobs ? node.item?.name:nil),title:"SQL Server Agent · History",width:1380,height:820,minWidth:960,minHeight:640,identity:"agent.history|\(node.server.id)|\(node.objectFolder == .jobs ? "job:"+(node.item?.name ?? "") : "all")")
  }
  func showAgentProperties(_ node:TreeNode) {
    guard let item=node.item else {return}
    presentAgent(AgentPropertiesPanel(server:node.server,name:item.name,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Job Properties · "+item.name)
    },history:{[weak self] in self?.showAgentHistory(node)}),title:"Job Properties · "+item.name,width:1220,height:800,minWidth:1000,minHeight:680,identity:"agent.properties|\(node.server.id)|\(item.name)")
  }
  func showAgentAction(_ node:TreeNode,action:SQLAgent.Action) {
    guard let item=node.item else {return}
    presentAgent(AgentActionPanel(server:node.server,name:item.name,action:action,open:{ [weak self] sql in
      self?.stageAgentSQL(sql,server:node.server,title:"Agent · "+action.rawValue+" · "+item.name)
    }),title:"SQL Server Agent · "+action.rawValue,width:740,height:520)
  }
  func showAgentActivity(_ node:TreeNode) {
    let server=node.server
    func jobNode(_ job:SQLAgent.Job)->TreeNode {TreeNode(job.name,kind:.object(.jobs),server:server,item:CatalogItem(name:job.name))}
    presentAgent(AgentActivityPanel(server:server,history:{[weak self] name in
      if let name {self?.showAgentHistory(TreeNode(name,kind:.object(.jobs),server:server,item:CatalogItem(name:name)))} else {self?.showAgentHistory(node)}
    },properties:{[weak self] job in self?.showAgentProperties(jobNode(job))},action:{[weak self] job,action in self?.showAgentAction(jobNode(job),action:action)}),title:"SQL Server Agent · Job Activity",width:1400,height:800,minWidth:1060,minHeight:640)
  }
  func showAgentSchedule(_ node:TreeNode) {
    guard let item=node.item else {return}
    weak var panelWindow:NSWindow?
    panelWindow=presentAgent(AgentSchedulePanel(server:node.server,item:item,close:{panelWindow?.close()},open:{[weak self] sql in self?.stageAgentSQL(sql,server:node.server,title:"Schedule · "+item.name)}),title:"Schedule Properties · "+item.name,width:820,height:760)
  }
  @discardableResult private func presentAgent<V:View>(_ root:V,title:String,width:CGFloat,height:CGFloat,minWidth:CGFloat=620,minHeight:CGFloat=480,identity:String?=nil)->NSWindow {
    let frame=(view.window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:width/0.94,height:height/0.94)
    let width=min(width,frame.width*0.94),height=min(height,frame.height*0.94)
    return present(root,title:title,width:width,height:height,minWidth:min(minWidth,width),minHeight:min(minHeight,height),identity:identity)
  }
  private func stageAgentSQL(_ sql:String,server:ConnectedServer,title:String) {
    let doc=state.newQuery(server:server,database:"msdb",text:sql,title:title)
    view.window?.makeKeyAndOrderFront(nil)
    doc.managedObjectApplied={ [weak doc] in
      guard let doc,doc.lastExecutedSQL == sql else {return}
      NotificationCenter.default.post(name:.init("studioAgentChanged"),object:server)
    }
  }
}

