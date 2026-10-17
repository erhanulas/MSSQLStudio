import Foundation

public struct TableDataType:Equatable,Sendable {
  public enum Parameters:Sendable {case none,length,precision,scale,float}
  public let name:String
  public let defaultSQL:String
  public let parameters:Parameters
  public init(name:String,defaultSQL:String,parameters:Parameters = .none) {self.name=name;self.defaultSQL=defaultSQL;self.parameters=parameters}
  public static let builtins:[Self]=[
    .init(name:"bigint",defaultSQL:"bigint"),.init(name:"binary",defaultSQL:"binary(50)",parameters:.length),
    .init(name:"bit",defaultSQL:"bit"),.init(name:"char",defaultSQL:"char(50)",parameters:.length),
    .init(name:"date",defaultSQL:"date"),.init(name:"datetime",defaultSQL:"datetime"),
    .init(name:"datetime2",defaultSQL:"datetime2(7)",parameters:.scale),.init(name:"datetimeoffset",defaultSQL:"datetimeoffset(7)",parameters:.scale),
    .init(name:"decimal",defaultSQL:"decimal(18,2)",parameters:.precision),.init(name:"float",defaultSQL:"float(53)",parameters:.float),
    .init(name:"int",defaultSQL:"int"),.init(name:"money",defaultSQL:"money"),
    .init(name:"nchar",defaultSQL:"nchar(10)",parameters:.length),.init(name:"numeric",defaultSQL:"numeric(18,2)",parameters:.precision),
    .init(name:"nvarchar",defaultSQL:"nvarchar(100)",parameters:.length),.init(name:"real",defaultSQL:"real"),
    .init(name:"rowversion",defaultSQL:"rowversion"),.init(name:"smalldatetime",defaultSQL:"smalldatetime"),
    .init(name:"smallint",defaultSQL:"smallint"),.init(name:"smallmoney",defaultSQL:"smallmoney"),
    .init(name:"sql_variant",defaultSQL:"sql_variant"),.init(name:"time",defaultSQL:"time(7)",parameters:.scale),
    .init(name:"tinyint",defaultSQL:"tinyint"),.init(name:"uniqueidentifier",defaultSQL:"uniqueidentifier"),
    .init(name:"varbinary",defaultSQL:"varbinary(100)",parameters:.length),.init(name:"varchar",defaultSQL:"varchar(100)",parameters:.length),
    .init(name:"xml",defaultSQL:"xml"),.init(name:"text",defaultSQL:"text"),.init(name:"ntext",defaultSQL:"ntext"),
    .init(name:"image",defaultSQL:"image"),.init(name:"sysname",defaultSQL:"sysname"),
    .init(name:"geography",defaultSQL:"geography"),.init(name:"geometry",defaultSQL:"geometry"),.init(name:"hierarchyid",defaultSQL:"hierarchyid")
  ].sorted {$0.name<$1.name}
  public static let query="SELECT SCHEMA_NAME(schema_id),name FROM sys.types WHERE is_user_defined=1 AND is_table_type=0 AND is_assembly_type=0 ORDER BY SCHEMA_NAME(schema_id),name;"
  public static func decode(_ result:Execution) throws -> [Self] {
    guard !result.partial,!result.stoppedEarly,result.failure==nil,result.results.count==1,!result.results[0].truncated else {throw SQLFailure("Kullanıcı veri tipleri tam okunamadı.")}
    return try result.results[0].values.map {row in
      guard row.count==2,let schema=row[0],let name=row[1],!schema.isEmpty,!name.isEmpty else {throw SQLFailure("Veri tipi metadata geçersiz.")}
      let qualified=SQL.identifier(schema)+"."+SQL.identifier(name)
      return Self(name:qualified,defaultSQL:qualified)
    }
  }
  public static func baseName(_ type:String)->String {type.hasPrefix("[") ? type:type.split(separator:"(",maxSplits:1).first.map(String.init) ?? type}
}
