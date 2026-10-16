import AppKit
import QuartzCore

/// Real byte progress with smooth layer transitions; unknown totals never invent a percentage.
@MainActor final class StudioTransferProgressView:NSView {
  var doubleValue:Double=0 {didSet {doubleValue=min(1,max(0,doubleValue));needsLayout=true;setAccessibilityValue(isIndeterminate ? nil:doubleValue)}}
  var isIndeterminate=true {didSet {needsLayout=true;setAccessibilityValue(isIndeterminate ? nil:doubleValue)}}
  private let track=CALayer()
  private let fill=CAGradientLayer()
  private var running=false
  override var isHidden:Bool {didSet {needsLayout=true;if isHidden {fill.removeAllAnimations()}}}
  override var intrinsicContentSize:NSSize {NSSize(width:NSView.noIntrinsicMetric,height:8)}
  override init(frame:NSRect) {
    super.init(frame:frame);wantsLayer=true;layer?.addSublayer(track);track.addSublayer(fill);track.masksToBounds=true
    setAccessibilityElement(true);setAccessibilityRole(.progressIndicator);setAccessibilityLabel("İndirme ilerlemesi")
  }
  required init?(coder:NSCoder) {fatalError()}
  func startAnimation(_ sender:Any?) {running=true;needsLayout=true}
  func stopAnimation(_ sender:Any?) {running=false;fill.removeAllAnimations();needsLayout=true}
  override func viewDidMoveToWindow() {super.viewDidMoveToWindow();needsLayout=true;if window==nil {fill.removeAllAnimations()}}
  override func viewDidChangeEffectiveAppearance() {super.viewDidChangeEffectiveAppearance();needsLayout=true}
  override func layout() {
    super.layout()
    let reduced=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let previous=fill.presentation()?.frame ?? fill.frame
    let resized=track.bounds.size != bounds.size
    CATransaction.begin();CATransaction.setDisableActions(true)
    track.frame=bounds;track.cornerRadius=bounds.height/2;fill.cornerRadius=bounds.height/2
    effectiveAppearance.performAsCurrentDrawingAppearance {
      track.backgroundColor=StudioTheme.accent.withAlphaComponent(0.10).cgColor
      fill.colors=[StudioTheme.accent.cgColor,(StudioTheme.accent.blended(withFraction:0.25,of:StudioTheme.success) ?? StudioTheme.accent).cgColor]
    }
    fill.startPoint=CGPoint(x:0,y:0.5);fill.endPoint=CGPoint(x:1,y:0.5)
    let width=isIndeterminate ? max(24,bounds.width*0.22):bounds.width*doubleValue
    fill.frame=CGRect(x:isIndeterminate ? (bounds.width-width)/2:0,y:0,width:width,height:bounds.height)
    CATransaction.commit()
    if isIndeterminate {
      fill.removeAnimation(forKey:"width");fill.removeAnimation(forKey:"position")
      if resized {fill.removeAnimation(forKey:"transfer")}
      if running,!isHidden,window != nil,!reduced {
        if fill.animation(forKey:"transfer") == nil {
          let motion=CABasicAnimation(keyPath:"position.x");motion.fromValue = -width/2;motion.toValue=bounds.width+width/2
          motion.duration=1.5;motion.repeatCount = .infinity;fill.add(motion,forKey:"transfer")
        }
      } else {fill.removeAllAnimations()}
    } else {
      fill.removeAnimation(forKey:"transfer")
      if !reduced,!isHidden,window != nil,previous.width != width {
        let transition=CABasicAnimation(keyPath:"bounds.size.width");transition.fromValue=previous.width;transition.toValue=width;transition.duration=0.18
        let position=CABasicAnimation(keyPath:"position.x");position.fromValue=previous.midX;position.toValue=width/2;position.duration=0.18
        fill.add(transition,forKey:"width");fill.add(position,forKey:"position")
      }
    }
  }
}
