import AppKit

/// Opening is serialized per Explorer connection; capture remains explicitly started later.
@MainActor final class MonitoringToolLauncher {
  enum Tool {
    case profiler,activity
    var title:String {self == .profiler ? "SQL Profiler":"Activity Monitor"}
  }
  private let tool:Tool
  private weak var owner:WorkbenchController?
  private var tasks:[UUID:Task<Void,Never>]=[:]
  private(set) var loadingCards:[UUID:StudioLoadingCard]=[:]
  var opening:Bool {!tasks.isEmpty}
  init(owner:WorkbenchController,tool:Tool) {self.owner=owner;self.tool=tool}
  deinit {for task in tasks.values {task.cancel()}}
  func cancel() {for task in tasks.values {task.cancel()};for card in loadingCards.values {card.removeFromSuperview()};loadingCards=[:]}
  func open(_ server:ConnectedServer) {
    guard tasks[server.id]==nil,!server.updatingProfile,let owner else {return}
    let card=StudioLoadingCard(title:tool.title+" açılıyor",context:server.profile.name)
    card.translatesAutoresizingMaskIntoConstraints=false;owner.view.addSubview(card);loadingCards[server.id]=card
    NSLayoutConstraint.activate([card.centerXAnchor.constraint(equalTo:owner.view.centerXAnchor),card.centerYAnchor.constraint(equalTo:owner.view.centerYAnchor),card.widthAnchor.constraint(equalToConstant:360),card.heightAnchor.constraint(greaterThanOrEqualToConstant:136)])
    card.updatePhase("Explorer bağlantısı kontrol ediliyor…")
    owner.view.layoutSubtreeIfNeeded()
    owner.status.stringValue=tool.title+" için Explorer bağlantısı kontrol ediliyor…"
    tasks[server.id]=Task { [weak self,weak owner,weak server] in
      guard let self,let owner,let server else {return}
      defer {tasks.removeValue(forKey:server.id);loadingCards.removeValue(forKey:server.id)?.removeFromSuperview();owner.updateControls()}
      let alreadyConnecting=server.reconnecting
      if alreadyConnecting {
        card.updatePhase("Devam eden Explorer bağlantısı bekleniyor…")
        let deadline=ContinuousClock.now.advanced(by:.seconds(20))
        while server.reconnecting,ContinuousClock.now<deadline {
          do {try await Task.sleep(for:.milliseconds(50))} catch {return}
        }
      } else {
        if server.online {await server.checkExplorerHealth()}
        guard !Task.isCancelled,owner.state.servers.contains(where:{$0 === server}),!server.updatingProfile else {return}
        if !server.online {card.updatePhase("SQL Server bağlantısı kuruluyor…");await owner.state.reconnectExplorer(server)}
      }
      guard !Task.isCancelled,owner.state.servers.contains(where:{$0 === server}),!server.updatingProfile else {return}
      guard server.online,!server.reconnecting else {
        owner.state.showError(tool.title+" açılamadı. Explorer bağlantısı kurulamadı.\n"+(server.startupError ?? "Bağlantı işlemi tamamlanmadı; yeniden deneyin."));return
      }
      card.updatePhase("Bağlantı hazır. Arayüz hazırlanıyor…")
      owner.state.changed?()
      switch tool {
      case .profiler:owner.presentProfiler(server)
      case .activity:owner.presentPerformanceMonitor(server)
      }
    }
  }
}
