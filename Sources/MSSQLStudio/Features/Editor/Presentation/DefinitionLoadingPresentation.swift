import AppKit

/// Feature-owned native presentation; QueryDocument remains the loading/task owner.
@MainActor final class DefinitionLoadingPresentation {
  private let definitionStatus=NSTextField(wrappingLabelWithString:"")
  private let definitionOverlay=NSStackView()
  private var definitionLoadingCard:StudioLoadingCard?
  init(in pane:NSView,relativeTo anchor:NSView) {
    definitionStatus.setAccessibilityIdentifier("definitionStatus")
    definitionStatus.alignment = .center
    definitionOverlay.orientation = .vertical;definitionOverlay.spacing=12
    definitionOverlay.addArrangedSubview(definitionStatus)
    let preferredDefinitionWidth=definitionOverlay.widthAnchor.constraint(equalToConstant:360)
    preferredDefinitionWidth.priority = .defaultHigh;preferredDefinitionWidth.isActive=true
    definitionOverlay.translatesAutoresizingMaskIntoConstraints=false
    pane.addSubview(definitionOverlay)
    NSLayoutConstraint.activate([
      definitionOverlay.centerXAnchor.constraint(equalTo:anchor.centerXAnchor),
      definitionOverlay.centerYAnchor.constraint(equalTo:anchor.centerYAnchor),
      definitionOverlay.widthAnchor.constraint(lessThanOrEqualTo:pane.widthAnchor,multiplier:0.8),
    ])
  }
  func update(_ document:QueryDocument) {
    let pending=document.definitionLoading || document.definitionError != nil
    definitionOverlay.isHidden = !pending
    if document.definitionLoading {
      if definitionLoadingCard==nil {
        definitionStatus.removeFromSuperview()
        let object=document.definitionSymbol.map {$0.schema+"."+$0.name} ?? document.title
        let context=document.server.profile.name+" · "+document.database+" · "+object
        let card=StudioLoadingCard(title:"Nesne tanımı açılıyor",context:context)
        card.phase.setAccessibilityIdentifier("definitionStatus")
        definitionLoadingCard=card;definitionOverlay.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo:definitionOverlay.widthAnchor).isActive=true
      }
      definitionLoadingCard?.updatePhase("Nesne tanımı yükleniyor…")
    } else {
      definitionLoadingCard?.progress.stopAnimation(nil)
      definitionLoadingCard?.removeFromSuperview();definitionLoadingCard=nil
      if definitionStatus.superview==nil {definitionOverlay.addArrangedSubview(definitionStatus)}
      definitionStatus.stringValue=document.definitionError ?? ""
      definitionStatus.textColor=StudioTheme.danger
    }
  }
}
