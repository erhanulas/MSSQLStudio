import Foundation

/// SQL Server implements MAX_ROWS using ROWCOUNT. Never apply it to a batch
/// containing writes, EXEC or session-changing SQL: it could limit a mutation.
enum ServerReadLimit {
  static func configure(sql:String,rows:Int,write:(Int)throws->Void,read:()throws->Int)throws->Bool {
    guard TSQL.canRepeatRead(sql) else {return false}
    let maximum=max(1,rows)
    try write(maximum)
    guard try read() == maximum else {throw SQLFailure("ODBC sürücüsü istenen satır okuma sınırını kabul etmedi.")}
    return true
  }
}

/// Each result owns a budget. Reaching it must not fetch an extra row to detect
/// EOF: that row can already trigger more network transfer in a forward cursor.
struct ResultFetchBudget {
  let maximum:Int
  private(set) var count=0
  private(set) var reached=false
  init(rows:Int) {maximum=max(1,rows)}
  mutating func next(fetch:()throws->Bool)throws->Bool {
    guard count < maximum else {reached=true;return false}
    guard try fetch() else {return false}
    count+=1
    return true
  }
}
