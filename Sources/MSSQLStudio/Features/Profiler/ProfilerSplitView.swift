import AppKit
import SwiftUI

/// A compact initial sidebar without imposing a maximum on subsequent native divider drags.
struct ProfilerSplitView<Sidebar:View,Content:View>:NSViewControllerRepresentable {
  let sidebar:Sidebar
  let content:Content
  init(@ViewBuilder sidebar:()->Sidebar,@ViewBuilder content:()->Content) {self.sidebar=sidebar();self.content=content()}
  func sizeThatFits(_ proposal:ProposedViewSize,nsViewController:Controller,context:Context)->CGSize? {
    CGSize(width:proposal.width ?? 960,height:proposal.height ?? 500)
  }
  func makeNSViewController(context:Context)->Controller {Controller(sidebar:sidebar,content:content)}
  func updateNSViewController(_ controller:Controller,context:Context) {
    controller.sidebar.rootView=sidebar;controller.content.rootView=content
  }
  @MainActor final class Controller:NSViewController,NSSplitViewDelegate {
    let sidebar:NSHostingController<Sidebar>
    let content:NSHostingController<Content>
    private let split=NSSplitView()
    private var placed=false
    init(sidebar:Sidebar,content:Content) {
      self.sidebar=NSHostingController(rootView:sidebar);self.content=NSHostingController(rootView:content)
      self.sidebar.sizingOptions=[];self.content.sizingOptions=[]
      super.init(nibName:nil,bundle:nil)
    }
    required init?(coder:NSCoder) {fatalError()}
    override func loadView() {
      split.isVertical=true;split.dividerStyle = .thin;split.delegate=self
      split.setAccessibilityIdentifier("profilerSplit");view=split
      addChild(sidebar);addChild(content)
      for child in [sidebar.view,content.view] {
        child.translatesAutoresizingMaskIntoConstraints=true
        split.addArrangedSubview(child)
      }
      (sidebar.view as? NSHostingView<Sidebar>)?.sizingOptions=[]
      (content.view as? NSHostingView<Content>)?.sizingOptions=[]
    }
    func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat {260}
    func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat {max(260,splitView.bounds.width-480-splitView.dividerThickness)}
    func splitView(_ splitView:NSSplitView,resizeSubviewsWithOldSize oldSize:NSSize) {
      guard splitView.bounds.width>0 else {return}
      let width=splitView.bounds.width,height=splitView.bounds.height,divider=splitView.dividerThickness
      let previous=placed ? sidebar.view.frame.width:280
      placed=true
      let left=min(max(260,previous),max(260,width-480-divider))
      sidebar.view.frame=NSRect(x:0,y:0,width:left,height:height)
      content.view.frame=NSRect(x:left+divider,y:0,width:max(0,width-left-divider),height:height)
    }
  }
}
