import Foundation

public enum SQLTextDiff {
  public struct Line: Sendable, Equatable {
    public let oldNumber: Int?
    public let newNumber: Int?
    public let old: String?
    public let new: String?
    /// Nil retains the exact diff policy. Semantic ranges refer to the original
    /// physical line, so presentation and copying never need formatted SQL.
    public let oldChanges: [NSRange]?
    public let newChanges: [NSRange]?
    public let oldSourceRange: NSRange?
    public let newSourceRange: NSRange?
    public let oldLineEnding: String?
    public let newLineEnding: String?
    public var oldChanged: Bool {oldChanges.map {!$0.isEmpty} ?? (old != nil && old != new)}
    public var newChanged: Bool {newChanges.map {!$0.isEmpty} ?? (new != nil && old != new)}
    public var changed: Bool {oldChanged || newChanged}
    init(oldNumber:Int?,newNumber:Int?,old:String?,new:String?,oldChanges:[NSRange]?=nil,newChanges:[NSRange]?=nil,oldSourceRange:NSRange?=nil,newSourceRange:NSRange?=nil,oldLineEnding:String?=nil,newLineEnding:String?=nil) {
      self.oldNumber=oldNumber;self.newNumber=newNumber;self.old=old;self.new=new
      self.oldChanges=oldChanges;self.newChanges=newChanges;self.oldSourceRange=oldSourceRange;self.newSourceRange=newSourceRange
      self.oldLineEnding=oldLineEnding;self.newLineEnding=newLineEnding
    }
  }
  public struct Comparison: Sendable, Equatable {
    public let lines: [Line]
    public let added: Int
    public let removed: Int
    public let simplified: Bool
  }
  /// Exact line diff for ordinary modules; large unrelated replacements use a bounded linear fallback.
  public static func compare(_ original: String, _ edited: String) -> Comparison {
    let a=original.components(separatedBy:"\n"),b=edited.components(separatedBy:"\n")
    var prefix=0,suffix=0
    while prefix < min(a.count,b.count),a[prefix] == b[prefix] {prefix+=1}
    while suffix < min(a.count,b.count)-prefix,a[a.count-1-suffix] == b[b.count-1-suffix] {suffix+=1}
    let ae=a.count-suffix,be=b.count-suffix
    let large=(ae-prefix)>4000 || (be-prefix)>4000 || (ae-prefix)*(be-prefix)>2_000_000
    var removals=Set<Int>(),insertions=Set<Int>()
    if large {
      removals=Set(prefix..<ae);insertions=Set(prefix..<be)
    } else {
      let difference=Array(b[prefix..<be]).difference(from:Array(a[prefix..<ae]))
      for change in difference {
        switch change {
        case .remove(let offset,_,_):removals.insert(prefix+offset)
        case .insert(let offset,_,_):insertions.insert(prefix+offset)
        }
      }
    }
    var i=0,j=0,lines:[Line]=[]
    while i<a.count || j<b.count {
      let remove=i<a.count && removals.contains(i),insert=j<b.count && insertions.contains(j)
      if remove || insert {
        lines.append(Line(oldNumber:remove ? i+1:nil,newNumber:insert ? j+1:nil,old:remove ? a[i]:nil,new:insert ? b[j]:nil))
        if remove {i+=1};if insert {j+=1}
      } else {
        lines.append(Line(oldNumber:i<a.count ? i+1:nil,newNumber:j<b.count ? j+1:nil,old:i<a.count ? a[i]:nil,new:j<b.count ? b[j]:nil));i+=1;j+=1
      }
    }
    return Comparison(lines:lines,added:insertions.count,removed:removals.count,simplified:large)
  }

  /// View-only display policy. External SQL whitespace, line-comment trailing
  /// padding and comment line-ending style are ignored; protected text remains exact.
  /// Original physical rows remain available.
  /// The exact policy above remains the default for migration reviews.
  public static func compareIgnoringSQLWhitespace(_ original:String,_ edited:String)->Comparison {
    let oldTokens=SQLWhitespaceComparison.tokens(in:original),newTokens=SQLWhitespaceComparison.tokens(in:edited)
    let semantic=changedOffsets(oldTokens.map {Data($0.text.utf8)},newTokens.map {Data($0.text.utf8)})
    let a=physicalLines(original,tokens:oldTokens,changed:semantic.removed)
    let b=physicalLines(edited,tokens:newTokens,changed:semantic.added)
    let alignment=changedOffsets(a.map {Data($0.key.utf8)},b.map {Data($0.key.utf8)})
    var i=0,j=0,lines:[Line]=[]
    while i<a.count || j<b.count {
      let remove=i<a.count && alignment.removed.contains(i),insert=j<b.count && alignment.added.contains(j)
      let oldIndex=remove || (!remove && !insert && i<a.count) ? i:nil
      let newIndex=insert || (!remove && !insert && j<b.count) ? j:nil
      let old=oldIndex.map {a[$0]},new=newIndex.map {b[$0]}
      lines.append(Line(oldNumber:oldIndex.map {$0+1},newNumber:newIndex.map {$0+1},old:old?.value,new:new?.value,
        oldChanges:old?.changes ?? [],newChanges:new?.changes ?? [],oldSourceRange:old?.range,newSourceRange:new?.range,
        oldLineEnding:old?.ending,newLineEnding:new?.ending))
      if oldIndex != nil {i+=1};if newIndex != nil {j+=1}
    }
    return Comparison(lines:lines,added:b.filter {!$0.changes.isEmpty}.count,removed:a.filter {!$0.changes.isEmpty}.count,simplified:semantic.simplified || alignment.simplified)
  }
  private struct PhysicalLine {
    let value:String
    let range:NSRange
    let ending:String
    var key=""
    var changes:[NSRange]=[]
  }
  private static func physicalLines(_ sql:String,tokens:[SQLWhitespaceComparison.Token],changed:Set<Int>)->[PhysicalLine] {
    let text=sql as NSString,units=Array(sql.utf16)
    var lines:[PhysicalLine]=[],start=0,index=0
    while index<units.count {
      if units[index]==10 || units[index]==13 {
        let end=index
        index += units[index]==13 && index+1<units.count && units[index+1]==10 ? 2:1
        let range=NSRange(location:start,length:end-start)
        lines.append(PhysicalLine(value:text.substring(with:range),range:range,ending:text.substring(with:NSRange(location:end,length:index-end))))
        start=index
      } else {index+=1}
    }
    let final=NSRange(location:start,length:units.count-start)
    lines.append(PhysicalLine(value:text.substring(with:final),range:final,ending:""))
    var firstLine=0
    for (tokenIndex,token) in tokens.enumerated() {
      while firstLine+1<lines.count,lines[firstLine+1].range.location<=token.range.location {firstLine+=1}
      var lineIndex=firstLine
      repeat {
        let line=lines[lineIndex],end=NSMaxRange(line.range)+line.ending.utf16.count
        let intersection=NSIntersectionRange(token.range,line.range)
        let ownsTerminator=token.range.location<end && NSMaxRange(token.range)>NSMaxRange(line.range)
        let zeroAtEnd=token.range.length==0 && token.range.location==NSMaxRange(line.range)
        if intersection.length>0 || ownsTerminator || zeroAtEnd {
          // Full tokens use the shared lexical key (including safe comment
          // trailing-space trimming); multiline protected fragments stay exact.
          let piece:String
          if token.range.location>=line.range.location && NSMaxRange(token.range)<=NSMaxRange(line.range) {piece=token.text}
          else if intersection.length>0 {piece=text.substring(with:intersection)+(ownsTerminator ? line.ending:"")}
          else {piece=token.text}
          lines[lineIndex].key += "\(piece.utf16.count):"+piece
          if changed.contains(tokenIndex) {
            lines[lineIndex].changes.append(NSRange(location:max(0,intersection.location-line.range.location),length:intersection.length))
          }
        }
        lineIndex+=1
      } while lineIndex<lines.count && lines[lineIndex].range.location<NSMaxRange(token.range)
    }
    return lines
  }
  private static func changedOffsets<Element:Equatable>(_ a:[Element],_ b:[Element])->(removed:Set<Int>,added:Set<Int>,simplified:Bool) {
    var prefix=0,suffix=0
    while prefix<min(a.count,b.count),a[prefix]==b[prefix] {prefix+=1}
    while suffix<min(a.count,b.count)-prefix,a[a.count-1-suffix]==b[b.count-1-suffix] {suffix+=1}
    let ae=a.count-suffix,be=b.count-suffix
    let large=ae-prefix>4000 || be-prefix>4000 || (ae-prefix)*(be-prefix)>2_000_000
    if large {return (Set(prefix..<ae),Set(prefix..<be),true)}
    var removed=Set<Int>(),added=Set<Int>()
    for change in Array(b[prefix..<be]).difference(from:Array(a[prefix..<ae])) {
      switch change {
      case .remove(let offset,_,_):removed.insert(prefix+offset)
      case .insert(let offset,_,_):added.insert(prefix+offset)
      }
    }
    return (removed,added,false)
  }
}
