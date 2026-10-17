import Testing
@testable import MSSQLStudio

@MainActor struct ResultColumnSearchTests {
  @Test func typoMatchesKeepExactHitsFirstAndOriginalColumnIdentity() {
    let columns=[ResultColumnChoice(id:8,name:"TOPLAMA_ID",type:"int",hidden:true),.init(id:2,name:"TOPLLAMA_ID",type:"varchar",hidden:false),.init(id:15,name:"STOK_KODU",type:"varchar",hidden:false)]
    #expect(ResultColumnNavigation.matches(columns,search:"topllama_id").map(\.id)==[2,8])
    #expect(ResultColumnNavigation.matches(columns,search:"toplama_id").map(\.id)==[8,2])
    for query in ["topama_id","toplqma_id","tolpama_id","topllama"] {
      #expect(ResultColumnNavigation.matches(columns,search:query).contains {$0.id==8 && $0.hidden})
    }
    #expect(ResultColumnNavigation.matches(columns,search:"tolllama_ix").isEmpty)
    #expect(ResultColumnNavigation.matches(columns,search:"top").map(\.id)==[8,2])
    #expect(ResultColumnNavigation.matches(columns,search:"tpo").isEmpty)
    #expect(ResultColumnNavigation.matches(columns,search:"  ").map(\.id)==[8,2,15])
    let found=ResultColumnNavigation.matches(columns,search:"topllama_id")
    #expect(ResultColumnNavigation.next(found,selected:2,step:1)==8)
  }
  @Test func turkishCaseAndAccentsArePreservedAsSearchEquivalents() {
    let columns=[ResultColumnChoice(id:1,name:"SİPARİŞ_ID",type:"int",hidden:false)]
    #expect(ResultColumnNavigation.matches(columns,search:"siparis_id").map(\.id)==[1])
    #expect(ResultColumnNavigation.matches(columns,search:"sipp a").isEmpty)
    #expect(ResultColumnNavigation.matches(columns,search:String(repeating:"x",count:1000)).isEmpty)
  }
}
