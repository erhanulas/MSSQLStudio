import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor private final class UpdateDetailsView:NSView {
  override var isFlipped:Bool {true}
}

@MainActor final class UpdateProgressController:NSWindowController {
  let status=NSTextField(wrappingLabelWithString: "Güncellemeler kontrol ediliyor…")
  let spinner=NSProgressIndicator()
  let done=NSButton(title:"Kapat",target:nil,action:nil)
  init() {
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:440,height:220),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.title="MSSQL Studio Güncellemesi";window.isReleasedWhenClosed=false
    window.contentMinSize=NSSize(width:380,height:180)
    super.init(window:window)
    let body=window.contentView!
    StudioTheme.surface(body,card:true)
    spinner.style = .spinning;spinner.controlSize = .small;spinner.startAnimation(nil)
    status.alignment = .left;status.font=StudioTheme.uiFont;status.textColor=StudioTheme.text;status.isSelectable=true
    status.setAccessibilityIdentifier("updateCheckStatus")
    done.target=self;done.action=#selector(closeProgress);done.isEnabled=false;done.bezelStyle = .rounded
    let heading=NSTextField(labelWithString:"Uygulama güncellemesi")
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold);heading.textColor=StudioTheme.text
    let header=NSStackView(views:[spinner,heading,NSView()]);header.spacing=8
    let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.drawsBackground=false
    let document=UpdateDetailsView();scroll.documentView=document
    document.translatesAutoresizingMaskIntoConstraints=false;status.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(status)
    NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),status.leadingAnchor.constraint(equalTo:document.leadingAnchor),status.trailingAnchor.constraint(equalTo:document.trailingAnchor),status.topAnchor.constraint(equalTo:document.topAnchor),status.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
    let actions=NSStackView(views:[NSView(),done])
    let stack=NSStackView(views:[header,scroll,actions]);stack.orientation = .vertical;stack.spacing=12
    stack.translatesAutoresizingMaskIntoConstraints=false;body.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-16),header.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:60),actions.widthAnchor.constraint(equalTo:stack.widthAnchor)])
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  func phase(_ text:String) {
    status.stringValue=text
    window?.contentView?.layoutSubtreeIfNeeded()
    status.enclosingScrollView?.documentView?.scroll(.zero)
  }
  func finish(_ text:String) {phase(text);spinner.stopAnimation(nil);spinner.isHidden=true;done.isEnabled=true;window?.styleMask.insert(.closable);done.keyEquivalent="\r"}
  @objc private func closeProgress() {close()}
}

extension WorkbenchController {
  @objc func installUpdate() {
    guard !updateInProgress else {updateProgress?.showWindow(nil);return}
    let feed:URL
    do {
      if let source=UserDefaults.standard.string(forKey:"githubUpdateRepository"),!source.isEmpty {
        feed=try GitHubUpdateSource.feed(source)
      } else if let address=Bundle.main.object(forInfoDictionaryKey:"MSSQLUpdateFeedURL") as? String,
        let url=URL(string:address),url.scheme == "https" {feed=url}
      else {throw SQLFailure("GitHub yayın deposu henüz tanımlanmadı. Ayarlar → GitHub güncellemeleri alanına kullanıcı/depo adresini girin.")}
    }catch {state.showError(error.localizedDescription);return}
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    updateProgress?.close()
    let progress=UpdateProgressController();updateProgress=progress
    updateInProgress=true;progress.showWindow(nil)
    Task {
      defer {updateInProgress=false}
      let updater = ApplicationUpdate()
      do {
        guard let release = try await updater.check(feed:feed,currentVersion:version) else {
          progress.finish("MSSQL Studio güncel. Yeni bir sürüm bulunamadı.");return
        }
        progress.phase("MSSQL Studio \(release.version) indiriliyor…")
        let package = try await updater.downloadInstaller(release)
        defer {try? FileManager.default.removeItem(at:package)}
        progress.phase("Güncelleme paketi doğrulanıyor…")
        let prepared = try await updater.prepareInstaller(package:package,expectedVersion:release.version,currentVersion:version)
        var installerOpened=false
        defer {if !installerOpened {try? FileManager.default.removeItem(at:prepared.directory)}}
        progress.close()
        let alert=StudioAlert();alert.messageText="MSSQL Studio \(prepared.version) kuruluma hazır"
        alert.informativeText="macOS Kurulum penceresinde kurulumu tamamlayın. Yeniden açmayı seçerseniz yeni sürüm doğrulandıktan sonra uygulama otomatik açılır; kurulum iptal edilirse açılmaz. Kayıtlı bağlantılarınız korunur."
        alert.addButton(withTitle:"Güncelle ve Yeniden Aç")
        alert.addButton(withTitle:"Güncelle ve Kapat")
        alert.addButton(withTitle:"Vazgeç")
        let response=alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn,state.canQuit() else {return}
        _ = try await NSWorkspace.shared.open([prepared.package],withApplicationAt:URL(fileURLWithPath:"/System/Library/CoreServices/Installer.app"),configuration:NSWorkspace.OpenConfiguration())
        installerOpened=true
        UserDefaults.standard.set(prepared.version,forKey:"pendingInstallerVersion")
        if response == .alertFirstButtonReturn {
          guard let executable=Bundle.main.executableURL else {throw SQLFailure("Yeniden açma bileşeni bulunamadı.")}
          let watcher=Process();watcher.executableURL=executable
          watcher.arguments=["--reopen-after-update",prepared.version,String(ProcessInfo.processInfo.processIdentifier)]
          watcher.standardInput=FileHandle.nullDevice;watcher.standardOutput=FileHandle.nullDevice;watcher.standardError=FileHandle.nullDevice
          try watcher.run()
          Application.updateWatcher=watcher
        }
        Application.updateTerminationApproved=true
        NSApp.terminate(nil)
      } catch {progress.showWindow(nil);progress.finish("Güncelleme kontrolü tamamlanamadı.\n"+error.localizedDescription)}
    }
  }
}

/// Stable native popovers share one viewport and use an anchor in window coordinates.
