import AppKit
import CoreText
import SQLServerKit
import SwiftUI

@MainActor private final class UpdateDetailsView:NSView {
  override var isFlipped:Bool {true}
}

@MainActor final class UpdateProgressController:NSWindowController {
  enum Stage:Int {case checking,downloading,verifying}
  let status=NSTextField(wrappingLabelWithString:"Yeni sürüm bilgisi alınıyor…")
  let spinner=NSProgressIndicator()
  let progressBar=NSProgressIndicator()
  let transfer=NSTextField(labelWithString:"Güvenli bağlantı kuruluyor")
  let percentage=NSTextField(labelWithString:"")
  let heading=NSTextField(labelWithString:"Güncellemeler kontrol ediliyor")
  let version=NSTextField(labelWithString:"")
  let icon=NSImageView()
  let done=NSButton(title:"Kapat",target:nil,action:nil)
  private var stage=Stage.checking
  private var finished=false
  private let steps=["Kontrol","İndirme","Doğrulama"].map {NSTextField(labelWithString:$0)}
  init() {
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:520,height:340),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.title="MSSQL Studio Güncellemesi";window.isReleasedWhenClosed=false
    window.contentMinSize=NSSize(width:440,height:320)
    super.init(window:window)
    let body=window.contentView!
    StudioTheme.surface(body,card:true)
    icon.image=NSImage(systemSymbolName:"arrow.down.app",accessibilityDescription:nil)
    icon.contentTintColor=StudioTheme.accent
    icon.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:32),icon.heightAnchor.constraint(equalToConstant:32)])
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold);heading.textColor=StudioTheme.text
    version.stringValue="MSSQL Studio · Yüklü sürüm "+(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—")
    version.font=StudioTheme.uiFont;version.textColor=StudioTheme.muted
    let titles=NSStackView(views:[heading,version]);titles.orientation = .vertical;titles.alignment = .leading;titles.spacing=4
    spinner.style = .spinning;spinner.controlSize = .small;spinner.startAnimation(nil)
    let header=NSStackView(views:[icon,titles,NSView(),spinner]);header.spacing=12
    let stages=NSStackView(views:steps);stages.distribution = .fillEqually;stages.spacing=8
    for (index,label) in steps.enumerated() {
      label.stringValue="\(index+1)  \(label.stringValue)";label.font=StudioTheme.uiFont
      label.setAccessibilityIdentifier("updateStage_\(index)")
    }
    progressBar.style = .bar;progressBar.isIndeterminate=true;progressBar.minValue=0;progressBar.maxValue=1;progressBar.startAnimation(nil)
    progressBar.setAccessibilityIdentifier("updateDownloadProgress")
    transfer.font=StudioTheme.uiFont;transfer.textColor=StudioTheme.muted
    percentage.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium);percentage.textColor=StudioTheme.text
    let counters=NSStackView(views:[transfer,NSView(),percentage]);counters.spacing=8
    status.alignment = .left;status.font=StudioTheme.uiFont;status.textColor=StudioTheme.text;status.isSelectable=true
    status.setAccessibilityIdentifier("updateCheckStatus")
    done.target=self;done.action=#selector(closeProgress);done.isEnabled=false;done.bezelStyle = .rounded
    done.image=NSImage(systemSymbolName:"xmark",accessibilityDescription:nil);done.imagePosition = .imageLeading
    let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay;scroll.drawsBackground=false
    let document=UpdateDetailsView();scroll.documentView=document
    document.translatesAutoresizingMaskIntoConstraints=false;status.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(status)
    NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),status.leadingAnchor.constraint(equalTo:document.leadingAnchor),status.trailingAnchor.constraint(equalTo:document.trailingAnchor),status.topAnchor.constraint(equalTo:document.topAnchor),status.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
    let actions=NSStackView(views:[NSView(),done])
    let stack=NSStackView(views:[header,stages,progressBar,counters,scroll,actions]);stack.orientation = .vertical;stack.spacing=12
    stack.translatesAutoresizingMaskIntoConstraints=false;body.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-16),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:60)])
    for row in [header,stages,counters,scroll,actions] {row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    progressBar.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
    phase("Yeni sürüm bilgisi alınıyor…")
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  func phase(_ text:String,stage:Stage = .checking) {
    guard !finished else {return}
    self.stage=stage
    status.stringValue=text
    heading.stringValue=stage == .checking ? "Güncellemeler kontrol ediliyor":stage == .downloading ? "Yeni sürüm indiriliyor":"Paket doğrulanıyor"
    transfer.stringValue=stage == .checking ? "Güvenli bağlantı kuruluyor":stage == .downloading ? "İndirme başlatılıyor":"Paket bütünlüğü ve imza denetleniyor"
    percentage.stringValue=""
    progressBar.isIndeterminate=true;progressBar.startAnimation(nil)
    for (index,label) in steps.enumerated() {label.textColor=index==stage.rawValue ? StudioTheme.accent:StudioTheme.muted}
    window?.contentView?.layoutSubtreeIfNeeded()
    status.enclosingScrollView?.documentView?.scroll(.zero)
  }
  func beginDownload(version:String) {
    phase("MSSQL Studio \(version) güncelleme paketi indiriliyor.",stage:.downloading)
    self.version.stringValue += "  →  "+version
  }
  func updateTransfer(_ value:UpdateDownloadProgress) {
    guard !finished,stage == .downloading else {return}
    let received=ByteCountFormatter.string(fromByteCount:value.receivedBytes,countStyle:.file)
    transfer.stringValue=received+(value.expectedBytes.map {" / "+ByteCountFormatter.string(fromByteCount:$0,countStyle:.file)} ?? " indirildi")
    if let fraction=value.fraction {
      progressBar.stopAnimation(nil);progressBar.isIndeterminate=false;progressBar.doubleValue=fraction
      percentage.stringValue="%\(Int(fraction*100))"
    } else {
      progressBar.isIndeterminate=true;progressBar.startAnimation(nil);percentage.stringValue=""
    }
  }
  func finish(_ text:String,failed:Bool=false) {
    guard !finished else {return}
    status.stringValue=text;finished=true
    heading.stringValue=failed ? "Güncelleme tamamlanamadı":"Güncelleme kontrolü tamamlandı"
    icon.image=NSImage(systemSymbolName:failed ? "exclamationmark.circle":"checkmark.circle",accessibilityDescription:nil)
    icon.contentTintColor=failed ? StudioTheme.warning:StudioTheme.success
    transfer.stringValue=failed ? "Ayrıntıları aşağıdan inceleyebilirsiniz":"MSSQL Studio"
    progressBar.stopAnimation(nil);progressBar.isHidden=true;percentage.stringValue=""
    spinner.stopAnimation(nil);spinner.isHidden=true;done.isEnabled=true;window?.styleMask.insert(.closable);done.keyEquivalent="\r"
    window?.contentView?.layoutSubtreeIfNeeded();status.enclosingScrollView?.documentView?.scroll(.zero)
  }
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
        progress.beginDownload(version:release.version)
        let package = try await updater.downloadInstaller(release) {value in
          Task { @MainActor in progress.updateTransfer(value) }
        }
        defer {try? FileManager.default.removeItem(at:package)}
        progress.phase("Güncelleme paketi doğrulanıyor…",stage:.verifying)
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
      } catch {progress.showWindow(nil);progress.finish("Güncelleme kontrolü tamamlanamadı.\n"+error.localizedDescription,failed:true)}
    }
  }
}

/// Stable native popovers share one viewport and use an anchor in window coordinates.
