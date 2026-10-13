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

  /// SQL module display policy. External SQL whitespace, line-comment trailing
  /// padding and comment line-ending style are ignored; protected text remains exact.
  /// Original physical rows remain available.
  /// The exact policy above remains the default for migration reviews.
  public static func compareIgnoringSQLWhitespace(_ original:String,_ edited:String)->Comparison {
    let oldTokens=SQLWhitespaceComparison.tokens(in:original),newTokens=SQLWhitespaceComparison.tokens(in:edited)
    var semantic=changedOffsets(oldTokens.map {Data($0.text.utf8)},newTokens.map {Data($0.text.utf8)})
    if semantic.removed.isEmpty,!semantic.added.isEmpty {
      let candidate=localizePureChanges(newTokens,sql:edited,changed:semantic.added)
      if retainedTokens(newTokens,excluding:candidate,equal:oldTokens) {semantic.added=candidate}
    } else if semantic.added.isEmpty,!semantic.removed.isEmpty {
      let candidate=localizePureChanges(oldTokens,sql:original,changed:semantic.removed)
      if retainedTokens(oldTokens,excluding:candidate,equal:newTokens) {semantic.removed=candidate}
    }
    let a=physicalLines(original,tokens:oldTokens,changed:semantic.removed)
    let b=physicalLines(edited,tokens:newTokens,changed:semantic.added)
    let anchors=matchedTokenLines(oldTokens,newTokens,oldLines:a,newLines:b,removed:semantic.removed,added:semantic.added)
    let alignment=changedOffsets(a.map {Data($0.key.utf8)},b.map {Data($0.key.utf8)},preferredAnchors:anchors.isEmpty ? nil:anchors)
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
  private static func changedOffsets<Element:Hashable>(_ a:[Element],_ b:[Element],preferredAnchors:[(Int,Int)]?=nil)->(removed:Set<Int>,added:Set<Int>,simplified:Bool) {
    var prefix=0,suffix=0
    while prefix<min(a.count,b.count),a[prefix]==b[prefix] {prefix+=1}
    while suffix<min(a.count,b.count)-prefix,a[a.count-1-suffix]==b[b.count-1-suffix] {suffix+=1}
    let ae=a.count-suffix,be=b.count-suffix
    let large=ae-prefix>4000 || be-prefix>4000 || (ae-prefix)*(be-prefix)>2_000_000
    let anchors=preferredAnchors.map {$0.filter {$0.0>=prefix && $0.0<ae && $0.1>=prefix && $0.1<be}} ?? (large ? uniqueAnchors(a,b,old:prefix..<ae,new:prefix..<be):[])
    var removed=Set<Int>(),added=Set<Int>(),simplified=false,work=2_000_000,oldStart=prefix,newStart=prefix
    for (oldEnd,newEnd) in anchors+[(ae,be)] {
      var x=oldStart,y=newStart,xe=oldEnd,ye=newEnd
      while x<xe,y<ye,a[x]==b[y] {x+=1;y+=1}
      while x<xe,y<ye,a[xe-1]==b[ye-1] {xe-=1;ye-=1}
      if x==xe {added.formUnion(y..<ye)}
      else if y==ye {removed.formUnion(x..<xe)}
      else if let offsets=isolatedSubstitutions(a,b,old:x..<xe,new:y..<ye) {
        removed.formUnion(offsets.map {x+$0});added.formUnion(offsets.map {y+$0})
      }
      else if let changes=boundedMyers(a,b,old:x..<xe,new:y..<ye,work:&work) {
        removed.formUnion(changes.removed);added.formUnion(changes.added)
      } else {
        // Only an unresolved fragment is simplified. Stable anchors and common
        // prefixes/suffixes remain unchanged even for a very large module.
        removed.formUnion(x..<xe);added.formUnion(y..<ye);simplified=true
      }
      oldStart=oldEnd+1;newStart=newEnd+1
    }
    return (removed,added,simplified)
  }
  /// Repeated rows admit many equal-cost LCS paths. Exact matching neighbors
  /// make a few isolated substitutions stay beside their original source row.
  private static func isolatedSubstitutions<Element:Equatable>(_ a:[Element],_ b:[Element],old:Range<Int>,new:Range<Int>)->[Int]? {
    guard old.count==new.count else {return nil}
    var offsets:[Int]=[]
    for offset in 0..<old.count where a[old.lowerBound+offset] != b[new.lowerBound+offset] {
      guard offsets.count<64,offsets.last.map({$0+1<offset}) ?? true else {return nil}
      offsets.append(offset)
    }
    return offsets.count*5<=old.count || old.count==1 ? offsets:nil
  }
  private static func tokenLines(_ tokens:[SQLWhitespaceComparison.Token],lines:[PhysicalLine])->[Int] {
    var line=0
    return tokens.map {token in
      while line+1<lines.count,lines[line+1].range.location<=token.range.location {line+=1}
      return line
    }
  }
  /// A greedy prefix can match SELECT from an inserted statement and mark
  /// SELECT on the following unchanged row instead. Rotating equal boundary
  /// tokens retains the exact edit cost and reaches the first changed row's
  /// start without adding a newly affected physical row.
  private static func localizePureChanges(_ tokens:[SQLWhitespaceComparison.Token],sql:String,changed:Set<Int>)->Set<Int> {
    let locations=tokenLines(tokens,lines:physicalLines(sql,tokens:tokens,changed:[]))
    let offsets=changed.sorted()
    var result=changed,index=0
    while index<offsets.count {
      var start=offsets[index],end=start+1
      index+=1
      while index<offsets.count,offsets[index]==end {end+=1;index+=1}
      while start>0,!result.contains(start-1),locations[start-1]==locations[start],tokens[start-1].text.utf8.elementsEqual(tokens[end-1].text.utf8) {
        result.insert(start-1);result.remove(end-1);start-=1;end-=1
      }
    }
    return result
  }
  private static func retainedTokens(_ tokens:[SQLWhitespaceComparison.Token],excluding:Set<Int>,equal other:[SQLWhitespaceComparison.Token])->Bool {
    guard tokens.count-excluding.count==other.count else {return false}
    var index=0
    for token in tokens.indices where !excluding.contains(token) {
      guard tokens[token].text.utf8.elementsEqual(other[index].text.utf8) else {return false}
      index+=1
    }
    return true
  }
  /// A reflowed expression may occupy one source row and several target rows.
  /// Matched token weight chooses a monotonic one-to-one physical-row pairing;
  /// extra rows remain visible and copying always follows original SQL ranges.
  private static func matchedTokenLines(_ old:[SQLWhitespaceComparison.Token],_ new:[SQLWhitespaceComparison.Token],oldLines:[PhysicalLine],newLines:[PhysicalLine],removed:Set<Int>,added:Set<Int>)->[(Int,Int)] {
    let oldLocations=tokenLines(old,lines:oldLines),newLocations=tokenLines(new,lines:newLines)
    var candidates:[(old:Int,new:Int,weight:Int)]=[],i=0,j=0
    while i<old.count,j<new.count {
      if removed.contains(i) {i+=1;continue};if added.contains(j) {j+=1;continue}
      guard old[i].text.utf8.elementsEqual(new[j].text.utf8) else {return []}
      let a=oldLocations[i],b=newLocations[j],weight=max(1,old[i].range.length)
      if let last=candidates.last,last.old==a,last.new==b {candidates[candidates.count-1].weight+=weight}
      else {candidates.append((a,b,weight))}
      i+=1;j+=1
    }
    var scores=Array(repeating:0,count:candidates.count),previous=Array(repeating:-1,count:candidates.count)
    var tree=Array(repeating:-1,count:newLines.count+1),group=0
    while group<candidates.count {
      var end=group+1
      while end<candidates.count,candidates[end].old==candidates[group].old {end+=1}
      for index in group..<end {
        var position=candidates[index].new,best = -1
        while position>0 {
          let candidate=tree[position]
          if candidate>=0,best<0 || scores[candidate]>scores[best] {best=candidate}
          position-=position & -position
        }
        previous[index]=best;scores[index]=candidates[index].weight+(best>=0 ? scores[best]:0)
      }
      for index in group..<end {
        var position=candidates[index].new+1
        while position<tree.count {
          if tree[position]<0 || scores[index]>scores[tree[position]] {tree[position]=index}
          position+=position & -position
        }
      }
      group=end
    }
    guard var index=scores.indices.max(by:{scores[$0]<scores[$1]}) else {return []}
    var result:[(Int,Int)]=[]
    while index>=0 {result.append((candidates[index].old,candidates[index].new));index=previous[index]}
    return result.reversed()
  }
  /// Patience anchors use exact unique tokens/lines and an increasing target
  /// subsequence; no fingerprint collision can declare different SQL equal.
  private static func uniqueAnchors<Element:Hashable>(_ a:[Element],_ b:[Element],old:Range<Int>,new:Range<Int>)->[(Int,Int)] {
    var oldIndexes:[Element:Int]=[:],newIndexes:[Element:Int]=[:]
    for index in old {oldIndexes[a[index]]=oldIndexes[a[index]] == nil ? index:-1}
    for index in new {newIndexes[b[index]]=newIndexes[b[index]] == nil ? index:-1}
    let candidates=old.compactMap {index -> (Int,Int)? in
      guard oldIndexes[a[index]]==index,let target=newIndexes[a[index]],target>=0 else {return nil}
      return (index,target)
    }
    var tails:[Int]=[],previous=Array(repeating:-1,count:candidates.count)
    for index in candidates.indices {
      var low=0,high=tails.count
      while low<high {let middle=(low+high)/2;if candidates[tails[middle]].1<candidates[index].1 {low=middle+1} else {high=middle}}
      if low>0 {previous[index]=tails[low-1]}
      if low==tails.count {tails.append(index)} else {tails[low]=index}
    }
    guard var index=tails.last else {return []}
    var result:[(Int,Int)]=[]
    while index>=0 {result.append(candidates[index]);index=previous[index]}
    return result.reversed()
  }
  /// A small edit distance stays cheap even when SQL has thousands of repeated
  /// rows and therefore no unique anchors. Trace space is bounded by 256 × 515;
  /// comparison work is shared across the unmatched fragments in this diff.
  private static func boundedMyers<Element:Equatable>(_ a:[Element],_ b:[Element],old:Range<Int>,new:Range<Int>,work:inout Int)->(removed:Set<Int>,added:Set<Int>)? {
    let n=old.count,m=new.count,maximumDistance=min(256,n+m),origin=maximumDistance+1
    var frontier=Array(repeating:0,count:2*maximumDistance+3),trace:[[Int]]=[]
    for distance in 0...maximumDistance {
      for diagonal in stride(from:-distance,through:distance,by:2) {
        work-=1;guard work>=0 else {return nil}
        let slot=origin+diagonal
        var x=diagonal == -distance || (diagonal != distance && frontier[slot-1]<frontier[slot+1]) ? frontier[slot+1]:frontier[slot-1]+1
        var y=x-diagonal
        while x<n,y<m,a[old.lowerBound+x]==b[new.lowerBound+y] {
          work-=1;guard work>=0 else {return nil};x+=1;y+=1
        }
        frontier[slot]=x
        if x>=n,y>=m {
          var removed=Set<Int>(),added=Set<Int>()
          if distance>0 {
            for step in stride(from:distance,through:1,by:-1) {
              let prior=trace[step-1],current=x-y,position=origin+current
              let priorDiagonal=current == -step || (current != step && prior[position-1]<prior[position+1]) ? current+1:current-1
              let priorX=prior[origin+priorDiagonal],priorY=priorX-priorDiagonal
              while x>priorX,y>priorY {x-=1;y-=1}
              if x==priorX {y-=1;added.insert(new.lowerBound+y)}
              else {x-=1;removed.insert(old.lowerBound+x)}
            }
          }
          return (removed,added)
        }
      }
      trace.append(frontier)
    }
    return nil
  }
}
