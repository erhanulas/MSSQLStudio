import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor final class UpdateProgressController:NSWindowController {
  let status=NSTextField(wrappingLabelWithString: "Güncellemeler kontrol ediliyor…")
  let spinner=NSProgressIndicator()
  let done=NSButton(title:"Kapat",target:nil,action:nil)
  init() {
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:440,height:170),styleMask:[.titled],backing:.buffered,defer:false)
    window.title="MSSQL Studio Güncellemesi";window.isReleasedWhenClosed=false
    super.init(window:window)
    spinner.style = .spinning;spinner.startAnimation(nil)
    status.alignment = .center;status.setAccessibilityIdentifier("updateCheckStatus")
    done.target=self;done.action=#selector(closeProgress);done.isEnabled=false
    let stack=NSStackView(views:[spinner,status,done]);stack.orientation = .vertical;stack.spacing=16
    stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView?.addSubview(stack)
    NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:window.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo:window.contentView!.centerYAnchor),stack.widthAnchor.constraint(equalToConstant:392)])
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  func phase(_ text:String) {status.stringValue=text}
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
        }
        Application.updateTerminationApproved=true
        NSApp.terminate(nil)
      } catch {progress.showWindow(nil);progress.finish("Güncelleme kontrolü tamamlanamadı.\n"+error.localizedDescription)}
    }
  }
}

/// Stable native popovers share one viewport and use an anchor in window coordinates.
