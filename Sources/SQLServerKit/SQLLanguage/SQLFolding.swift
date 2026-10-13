import Foundation

/// Conservative structural outlining. Strings, comments, CASE and BEGIN TRAN cannot close a code block.
public enum SQLFolding {
  public struct Region: Equatable, Sendable {
    public let header: NSRange
    public let hidden: NSRange
  }
  public static func regions(_ source: String) -> [Region] {
    let text = source as NSString
    guard text.length <= 250_000 else { return [] }
    let tokens = TSQL.lex(source).filter { $0.kind != .space && $0.kind != .comment && $0.kind != .string }
    let tokensByLine=Dictionary(grouping:tokens,by:{text.lineRange(for:$0.range).location})
    var stack: [(String, NSRange)] = [], result: [Region] = []
    for (index, token) in tokens.enumerated() {
      let word = token.text.uppercased()
      if token.kind != .keyword && token.kind != .word { continue }
      if word == "CASE" { stack.append(("CASE", token.range)) }
      if word == "BEGIN" {
        let next = index+1 < tokens.count ? tokens[index+1].text.uppercased() : ""
        if ["TRAN", "TRANSACTION", "DISTRIBUTED", "DIALOG", "CONVERSATION"].contains(next) { continue }
        stack.append(("BEGIN", token.range))
      }
      if word == "END", let opener = stack.popLast(), opener.0 == "BEGIN" {
        var header = text.lineRange(for: opener.1)
        // Keep the condition/ELSE visible as the fold header when BEGIN is on the next line.
        if header.location > 0 {
          let previous=text.lineRange(for:NSRange(location:header.location-1,length:0))
          let words=tokensByLine[previous.location] ?? []
          if let first=words.first,["IF","ELSE"].contains(first.text.uppercased()),!words.contains(where:{$0.text == ";" || $0.text.uppercased() == "END"}) {header=previous}
        }
        let closing = text.lineRange(for: token.range)
        var start = NSMaxRange(header), end = NSMaxRange(closing)
        while start > header.location && [10,13].contains(text.character(at:start-1)) { start -= 1 }
        while end > closing.location && [10,13].contains(text.character(at:end-1)) { end -= 1 }
        if closing.location > header.location, end > start {
          result.append(Region(header:header,hidden:NSRange(location:start,length:end-start)))
        }
      }
      if word == "GO" { stack.removeAll() }
    }
    return result.sorted { $0.hidden.location < $1.hidden.location }
  }
  public struct Projection: Sendable {
    public let source: String
    public let text: String
    public let regions: [Region]
    public init(source: String, collapsed: [Region]) {
      self.source=source
      let original = source as NSString
      var chosen: [Region] = [], end = 0
      for region in collapsed.sorted(by: { $0.hidden.location < $1.hidden.location }) {
        guard region.hidden.location >= end, NSMaxRange(region.hidden) <= original.length else { continue }
        chosen.append(region); end = NSMaxRange(region.hidden)
      }
      regions = chosen
      var value = "", cursor = 0
      for region in chosen {
        value += original.substring(with:NSRange(location:cursor,length:region.hidden.location-cursor)) + " …"
        cursor = NSMaxRange(region.hidden)
      }
      text = value + original.substring(from:cursor)
    }
    public func sourceOffset(_ offset: Int, end: Bool = false) -> Int {
      var delta = 0
      for region in regions {
        let start = region.hidden.location-delta
        if offset < start { break }
        if offset <= start+2 { return end || offset == start+2 ? NSMaxRange(region.hidden) : region.hidden.location }
        delta += region.hidden.length-2
      }
      return offset+delta
    }
    public func displayOffset(_ offset: Int) -> Int {
      var delta = 0
      for region in regions {
        if offset < region.hidden.location { break }
        if offset < NSMaxRange(region.hidden) { return region.hidden.location-delta }
        delta += region.hidden.length-2
      }
      return offset-delta
    }
    public func sourceRange(_ range: NSRange) -> NSRange {
      let start = sourceOffset(range.location)
      let finish = range.length == 0 ? start : sourceOffset(NSMaxRange(range),end:true)
      return NSRange(location:start,length:max(0,finish-start))
    }
  }
}
