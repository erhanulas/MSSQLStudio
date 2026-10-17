import AppKit
import QuartzCore

/// A short, layer-only celebration that never takes pointer or keyboard focus.
@MainActor final class StudioConfetti:NSView {
  private var dismissal:DispatchWorkItem?
  static func show(in host:NSView,reduceMotion:Bool=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
    for previous in host.subviews.compactMap({$0 as? StudioConfetti}) {previous.removeFromSuperview()}
    let burst=StudioConfetti(frame:.zero)
    burst.translatesAutoresizingMaskIntoConstraints=false
    host.addSubview(burst)
    NSLayoutConstraint.activate([
      burst.centerXAnchor.constraint(equalTo:host.centerXAnchor),burst.centerYAnchor.constraint(equalTo:host.centerYAnchor),
      burst.widthAnchor.constraint(equalToConstant:240),burst.heightAnchor.constraint(equalToConstant:200)
    ])
    host.layoutSubtreeIfNeeded()
    burst.animate(reduceMotion:reduceMotion)
  }
  override init(frame:NSRect) {super.init(frame:frame);wantsLayer=true;setAccessibilityElement(false)}
  required init?(coder:NSCoder) {fatalError()}
  override func hitTest(_ point:NSPoint)->NSView? {nil}
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window==nil {dismissal?.cancel();dismissal=nil;layer?.sublayers?.forEach {$0.removeAllAnimations()}}
  }
  private func animate(reduceMotion:Bool) {
    let colors=[StudioTheme.accent,StudioTheme.success,StudioTheme.warning]
    let center=CGPoint(x:bounds.midX,y:bounds.midY)
    if reduceMotion {
      let icon=NSImageView(frame:NSRect(x:center.x-12,y:center.y-12,width:24,height:24))
      icon.image=NSImage(systemSymbolName:"checkmark.circle.fill",accessibilityDescription:nil)
      icon.contentTintColor=StudioTheme.success;addSubview(icon)
    } else {
      CATransaction.begin();CATransaction.setDisableActions(true)
      for index in 0..<32 {
        let particle=CALayer()
        particle.bounds=CGRect(x:0,y:0,width:index.isMultiple(of:3) ? 5:4,height:8)
        particle.cornerRadius=1;particle.position=center;particle.opacity=0
        particle.backgroundColor=colors[index % colors.count].cgColor;layer?.addSublayer(particle)
        let angle=Double(index)*2.399963229728653
        let radius=CGFloat(60+(index*17)%48)
        let dx=CGFloat(cos(angle))*radius,dy=CGFloat(sin(angle))*radius
        let path=CGMutablePath();path.move(to:center)
        path.addQuadCurve(to:CGPoint(x:center.x+dx,y:center.y+dy-30),control:CGPoint(x:center.x+dx*0.6,y:center.y+dy+35))
        let flight=CAKeyframeAnimation(keyPath:"position");flight.path=path
        flight.timingFunction=CAMediaTimingFunction(name:.easeOut)
        let spin=CABasicAnimation(keyPath:"transform.rotation.z");spin.fromValue=angle;spin.toValue=angle+Double.pi*2
        let fade=CAKeyframeAnimation(keyPath:"opacity");fade.values=[0,1,1,0];fade.keyTimes=[0,0.08,0.55,1]
        for animation in [flight,spin,fade] {animation.duration=0.85}
        let group=CAAnimationGroup();group.animations=[flight,spin,fade];group.duration=0.85
        particle.add(group,forKey:"celebration")
      }
      CATransaction.commit()
    }
    let work=DispatchWorkItem {[weak self] in self?.removeFromSuperview()}
    dismissal=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.9,execute:work)
  }
}
