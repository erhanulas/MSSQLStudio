import Foundation

/// One source replacement keeps selected-line commenting atomic in native undo.
public enum SQLComments {
  public struct Edit:Sendable {
    public let range:NSRange
    public let replacement:String
    public let selection:NSRange
  }
  private static func selectedLines(_ source:NSString,_ selection:NSRange)->NSRange? {
    guard selection.location != NSNotFound,selection.location <= source.length,selection.length <= source.length-selection.location else {return nil}
    var range=selection
    if range.length > 0 {range.length-=1}
    return source.lineRange(for:range)
  }
  private static func lines(_ source:NSString,_ range:NSRange)->[(text:String,ending:String)] {
    var result:[(String,String)]=[],index=range.location
    while index < NSMaxRange(range) {
      var start=0,end=0,contents=0
      source.getLineStart(&start,end:&end,contentsEnd:&contents,for:NSRange(location:index,length:0))
      result.append((source.substring(with:NSRange(location:start,length:contents-start)),source.substring(with:NSRange(location:contents,length:end-contents))))
      index=end
    }
    return result
  }
  public static func isCommented(_ source:String,selection:NSRange)->Bool {
    let text=source as NSString
    guard let range=selectedLines(text,selection) else {return false}
    let nonempty=lines(text,range).map(\.text).filter {!$0.trimmingCharacters(in:.whitespaces).isEmpty}
    return !nonempty.isEmpty && nonempty.allSatisfy {$0.drop(while:{$0 == " " || $0 == "\t"}).hasPrefix("--")}
  }
  public static func edit(_ source:String,selection:NSRange,uncomment:Bool=false)->Edit? {
    let text=source as NSString
    guard let range=selectedLines(text,selection) else {return nil}
    let remove=uncomment || isCommented(source,selection:selection)
    let replacement=lines(text,range).map {line in
      let indent=String(line.text.prefix(while:{$0 == " " || $0 == "\t"}))
      let code=String(line.text.dropFirst(indent.count))
      guard !code.isEmpty else {return line.text+line.ending}
      if remove {
        guard code.hasPrefix("--") else {return line.text+line.ending}
        var rest=String(code.dropFirst(2));if rest.hasPrefix(" ") {rest.removeFirst()}
        return indent+rest+line.ending
      }
      return indent+"-- "+code+line.ending
    }.joined()
    guard replacement != text.substring(with:range) else {return nil}
    return Edit(range:range,replacement:replacement,selection:NSRange(location:range.location,length:(replacement as NSString).length))
  }
}
