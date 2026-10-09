import Foundation

public enum SQLTextDiff {
  public struct Line: Sendable, Equatable {
    public let oldNumber: Int?
    public let newNumber: Int?
    public let old: String?
    public let new: String?
    public var changed: Bool {old != new}
  }
  public struct Comparison: Sendable {
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
}
