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
  let progressBar=StudioTransferProgressView(frame:.zero)
  let notesHost=NSHostingView(rootView:UpdateReleaseNotesView(notes:[],error:""))
  private(set) var offeredNotes:[ReleaseNote]=[]
  private(set) var notesError=""
  let transfer=NSTextField(labelWithString:"Güvenli bağlantı kuruluyor")
  let percentage=NSTextField(labelWithString:"")
  let heading=NSTextField(labelWithString:"Güncellemeler kontrol ediliyor")
  let version=NSTextField(labelWithString:"")
  let icon=NSImageView()
  let done=NSButton(title:"Kapat",target:nil,action:nil)
  let download=StudioPrimaryActionButton(title:"Son Sürümü İndir",target:nil,action:nil)
  private var downloadWidth:NSLayoutConstraint?
  private var downloadAction:(()->Void)?
  var hasOffer:Bool {downloadAction != nil}
  private let stages=NSStackView()
  private let notesHeading=NSTextField(labelWithString:"Güncelleme durumu")
  private var stage=Stage.checking
  private var finished=false
  private let steps=["Kontrol","İndirme","Doğrulama"].map {NSTextField(labelWithString:$0)}
  init() {
    let window=StudioPanelWindow(contentRect:NSRect(x:0,y:0,width:580,height:440),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
    window.title="MSSQL Studio Güncellemesi";window.isReleasedWhenClosed=false
    window.contentMinSize=NSSize(width:440,height:320)
    window.framePersistenceRole="updates"
    super.init(window:window)
    let body=window.contentView!
    StudioTheme.surface(body)
    icon.image=NSImage(systemSymbolName:"arrow.down.app",accessibilityDescription:nil)
    icon.contentTintColor=StudioTheme.accent
    icon.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant:32),icon.heightAnchor.constraint(equalToConstant:32)])
    heading.font = .systemFont(ofSize:StudioMetrics.headingFont,weight:.semibold);heading.textColor=StudioTheme.text
    version.stringValue="MSSQL Studio · Yüklü sürüm "+(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—")
    version.font=StudioTheme.uiFont;version.textColor=StudioTheme.muted
    let titles=NSStackView(views:[heading,version]);titles.orientation = .vertical;titles.alignment = .leading;titles.spacing=4
    spinner.style = .spinning;spinner.controlSize = .small;spinner.startAnimation(nil)
    let iconTile=NSView();StudioTheme.statusSurface(iconTile);iconTile.layer?.cornerRadius=StudioMetrics.cardRadius
    iconTile.addSubview(icon);iconTile.translatesAutoresizingMaskIntoConstraints=false
    NSLayoutConstraint.activate([iconTile.widthAnchor.constraint(equalToConstant:48),iconTile.heightAnchor.constraint(equalToConstant:48),icon.centerXAnchor.constraint(equalTo:iconTile.centerXAnchor),icon.centerYAnchor.constraint(equalTo:iconTile.centerYAnchor)])
    let header=NSStackView(views:[iconTile,titles,NSView(),spinner]);header.spacing=12
    stages.distribution = .fillEqually;stages.spacing=8
    for label in steps {
      let tile=NSView();StudioTheme.surface(tile,card:true)
      label.translatesAutoresizingMaskIntoConstraints=false;tile.addSubview(label)
      NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:tile.leadingAnchor,constant:8),label.trailingAnchor.constraint(equalTo:tile.trailingAnchor,constant:-8),label.centerYAnchor.constraint(equalTo:tile.centerYAnchor),tile.heightAnchor.constraint(equalToConstant:28)])
      stages.addArrangedSubview(tile)
    }
    for (index,label) in steps.enumerated() {
      label.stringValue="\(index+1)  \(label.stringValue)";label.font=StudioTheme.uiFont
      label.setAccessibilityIdentifier("updateStage_\(index)")
    }
    progressBar.isIndeterminate=true;progressBar.startAnimation(nil)
    progressBar.heightAnchor.constraint(equalToConstant:8).isActive=true
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
    download.target=self;download.action=#selector(downloadSelected);download.bezelStyle = .rounded
    download.image=NSImage(systemSymbolName:"arrow.down.circle",accessibilityDescription:nil);download.imagePosition = .imageLeading
    download.isHidden=true;download.setAccessibilityIdentifier("updateDownloadLatest")
    download.font = .systemFont(ofSize:StudioMetrics.bodyFont,weight:.medium)
    download.refreshStyle()
    download.translatesAutoresizingMaskIntoConstraints=false;done.translatesAutoresizingMaskIntoConstraints=false
    downloadWidth=download.widthAnchor.constraint(greaterThanOrEqualToConstant:180)
    NSLayoutConstraint.activate([download.heightAnchor.constraint(equalToConstant:30),done.heightAnchor.constraint(equalToConstant:30),downloadWidth!])
    let actions=NSStackView(views:[NSView(),done,download]);actions.spacing=8
    notesHeading.font = .systemFont(ofSize:StudioMetrics.bodyFont,weight:.semibold);notesHeading.textColor=StudioTheme.text
    let details=NSView();StudioTheme.surface(details,card:true)
    notesHost.isHidden=true;notesHost.sizingOptions=[]
    notesHost.heightAnchor.constraint(greaterThanOrEqualToConstant:60).isActive=true
    let detailsStack=NSStackView(views:[notesHeading,scroll,notesHost]);detailsStack.orientation = .vertical;detailsStack.spacing=8
    detailsStack.translatesAutoresizingMaskIntoConstraints=false;details.addSubview(detailsStack)
    NSLayoutConstraint.activate([detailsStack.leadingAnchor.constraint(equalTo:details.leadingAnchor,constant:12),detailsStack.trailingAnchor.constraint(equalTo:details.trailingAnchor,constant:-12),detailsStack.topAnchor.constraint(equalTo:details.topAnchor,constant:12),detailsStack.bottomAnchor.constraint(equalTo:details.bottomAnchor,constant:-12),scroll.widthAnchor.constraint(equalTo:detailsStack.widthAnchor),notesHeading.widthAnchor.constraint(equalTo:detailsStack.widthAnchor),notesHost.widthAnchor.constraint(equalTo:detailsStack.widthAnchor)])
    let stack=NSStackView(views:[header,stages,progressBar,counters,details,actions]);stack.orientation = .vertical;stack.spacing=12
    stack.translatesAutoresizingMaskIntoConstraints=false;body.addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:body.leadingAnchor,constant:16),stack.trailingAnchor.constraint(equalTo:body.trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:body.topAnchor,constant:16),stack.bottomAnchor.constraint(equalTo:body.bottomAnchor,constant:-16),scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:60)])
    for row in [header,stages,counters,details,actions] {row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true}
    progressBar.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
    phase("Yeni sürüm bilgisi alınıyor…")
    window.center()
  }
  required init?(coder:NSCoder) {fatalError()}
  func phase(_ text:String,stage:Stage = .checking) {
    guard !finished else {return}
    self.stage=stage
    window?.contentMinSize=NSSize(width:440,height:440)
    if let window,let body=window.contentView,body.bounds.height<440 {window.setContentSize(NSSize(width:max(440,body.bounds.width),height:440))}
    stages.isHidden=false;notesHeading.stringValue="Güncelleme durumu"
    notesHost.isHidden=true;status.enclosingScrollView?.isHidden=false
    status.stringValue=text
    if stage != .checking, !offeredNotes.isEmpty || !notesError.isEmpty {
      notesHost.isHidden=false;status.enclosingScrollView?.isHidden=true
      notesHeading.stringValue="Bu güncellemedeki yenilikler"
    }
    heading.stringValue=stage == .checking ? "Güncellemeler kontrol ediliyor":stage == .downloading ? "Yeni sürüm indiriliyor":"Paket doğrulanıyor"
    transfer.stringValue=stage == .checking ? "Güvenli bağlantı kuruluyor":stage == .downloading ? "İndirme başlatılıyor":"Paket bütünlüğü ve imza denetleniyor"
    percentage.stringValue=""
    progressBar.isIndeterminate=true;progressBar.startAnimation(nil)
    for (index,label) in steps.enumerated() {label.textColor=index==stage.rawValue ? StudioTheme.accent:StudioTheme.muted;label.font = .systemFont(ofSize:StudioMetrics.bodyFont,weight:index==stage.rawValue ? .semibold:.regular);label.stringValue=(index<stage.rawValue ? "✓":"\(index+1)")+"  "+["Kontrol","İndirme","Doğrulama"][index]}
    window?.contentView?.layoutSubtreeIfNeeded()
    status.enclosingScrollView?.documentView?.scroll(.zero)
  }
  func beginDownload(version:String) {
    downloadAction=nil;download.isHidden=true;done.isEnabled=false;done.keyEquivalent=""
    window?.styleMask.remove(.closable);spinner.isHidden=false;spinner.startAnimation(nil)
    progressBar.isHidden=false
    phase("MSSQL Studio \(version) güncelleme paketi indiriliyor.",stage:.downloading)
    if !self.version.stringValue.hasSuffix(" → "+version) {self.version.stringValue += " → "+version}
  }
  func offer(version latest:String,current:String,notes:[ReleaseNote],notesError:String="",download action:@escaping ()->Void) {
    guard !finished else {return}
    window?.contentMinSize=NSSize(width:440,height:320)
    heading.stringValue="Yeni sürüm hazır"
    stages.isHidden=true;notesHeading.stringValue="Bu güncellemedeki yenilikler"
    icon.image=NSImage(systemSymbolName:"sparkles",accessibilityDescription:nil)
    version.stringValue="Yüklü "+current+" → "+latest
    transfer.stringValue="Yenilikleri inceleyin, ardından son sürümü indirin."
    progressBar.stopAnimation(nil);progressBar.isHidden=true;percentage.stringValue=""
    spinner.stopAnimation(nil);spinner.isHidden=true
    done.isEnabled=true;done.keyEquivalent="";window?.styleMask.insert(.closable)
    download.title="\(latest) Sürümünü İndir";download.isHidden=false;download.isEnabled=true;download.keyEquivalent="\r"
    downloadWidth?.constant=(download.title as NSString).size(withAttributes:[.font:download.font!]).width+44
    downloadAction=action
    offeredNotes=notes;self.notesError=notesError
    notesHost.rootView=UpdateReleaseNotesView(notes:notes,error:notesError)
    status.enclosingScrollView?.isHidden=true;notesHost.isHidden=false
    if let window,window.contentView!.bounds.height<480 {
      window.setContentSize(NSSize(width:max(560,window.contentView!.bounds.width),height:480))
    }
    window?.contentView?.layoutSubtreeIfNeeded();status.enclosingScrollView?.documentView?.scroll(.zero)
  }
  @objc private func downloadSelected() {
    guard let action=downloadAction else {return}
    downloadAction=nil;download.isEnabled=false;action()
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
    window?.contentMinSize=NSSize(width:440,height:320)
    downloadAction=nil;download.isHidden=true
    notesHost.isHidden=true;status.enclosingScrollView?.isHidden=false
    status.stringValue=text;finished=true
    stages.isHidden=true;notesHeading.stringValue=failed ? "Hata ayrıntıları":"Durum"
    heading.stringValue=failed ? "Güncelleme tamamlanamadı":"Güncelleme kontrolü tamamlandı"
    icon.image=NSImage(systemSymbolName:failed ? "exclamationmark.circle":"checkmark.circle",accessibilityDescription:nil)
    icon.contentTintColor=failed ? StudioTheme.warning:StudioTheme.success
    transfer.stringValue=failed ? "Ayrıntıları aşağıdan inceleyebilirsiniz":"MSSQL Studio"
    progressBar.stopAnimation(nil);progressBar.isHidden=true;percentage.stringValue=""
    spinner.stopAnimation(nil);spinner.isHidden=true;done.isEnabled=true;window?.styleMask.insert(.closable);done.keyEquivalent="\r"
    window?.contentView?.layoutSubtreeIfNeeded();status.enclosingScrollView?.documentView?.scroll(.zero)
  }
  @objc private func closeProgress() {downloadAction=nil;close()}
}

extension WorkbenchController {
  @objc func installUpdate() {
    if updateProgress?.hasOffer==true,updateProgress?.window?.isVisible==true {updateProgress?.showWindow(nil);return}
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
        progress.phase("MSSQL Studio "+release.version+" bulundu. Sürüm notları alınıyor…")
        var notes:[ReleaseNote]=[],notesError=""
        do {notes=try await updater.releaseNotes(feed:feed,release:release,currentVersion:version)}
        catch {try Task.checkCancellation();notesError=error.localizedDescription}
        progress.offer(version:release.version,current:version,notes:notes,notesError:notesError) { [weak self=self,weak progress=progress] in
          guard let self,let progress,!self.updateInProgress else {return}
          self.updateInProgress=true
          progress.beginDownload(version:release.version)
          Task {await self.downloadUpdate(release,updater:updater,progress:progress,currentVersion:version)}
        }
      } catch {progress.finish("Güncelleme kontrolü tamamlanamadı.\n"+error.localizedDescription,failed:true)}
    }
  }
  private func downloadUpdate(_ release:ApplicationUpdate.Release,updater:ApplicationUpdate,progress:UpdateProgressController,currentVersion version:String) async {
    defer {updateInProgress=false}
    do {
        let package = try await updater.downloadInstaller(release) {value in
          Task { @MainActor in progress.updateTransfer(value) }
        }
        defer {try? FileManager.default.removeItem(at:package)}
        progress.phase("Güncelleme paketi doğrulanıyor…",stage:.verifying)
        let prepared = try await updater.prepareInstaller(package:package,expectedVersion:release.version,currentVersion:version)
        var installerOpened=false
        defer {if !installerOpened {try? FileManager.default.removeItem(at:prepared.directory)}}
        progress.close()
        let alert=StudioAlert(role:"updateInstallationConfirmation");alert.messageText="MSSQL Studio \(prepared.version) kuruluma hazır"
        alert.informativeText="macOS Kurulum penceresinde kurulumu tamamlayın. Yeniden açmayı seçerseniz yeni sürüm doğrulandıktan sonra uygulama otomatik açılır; kurulum iptal edilirse açılmaz. Kayıtlı bağlantılarınız korunur."
        alert.addButton(withTitle:"Güncelle ve Yeniden Aç")
        alert.addButton(withTitle:"Güncelle ve Kapat")
        alert.addButton(withTitle:"Vazgeç")
        let response=alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn,state.canQuit(preservingWorkspace:true) else {return}
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
    } catch {progress.showWindow(nil);progress.finish("Güncelleme indirilemedi veya hazırlanamadı.\n"+error.localizedDescription,failed:true)}
  }
}

/// Stable native popovers share one viewport and use an anchor in window coordinates.
