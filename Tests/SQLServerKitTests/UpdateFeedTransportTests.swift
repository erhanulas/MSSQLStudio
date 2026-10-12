import Foundation
import Testing
@testable import SQLServerKit

private actor FeedFixture {
  var requests:[URLRequest]=[]
  var codes:[Int]
  let data:Data
  var firstNetworkFailure:URLError.Code?
  init(_ codes:[Int]=[200],data:Data=Data(#"{"version":"0.2.81","downloadURL":"https://example.invalid/app.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8),network:URLError.Code?=nil) {self.codes=codes;self.data=data;firstNetworkFailure=network}
  func fetch(_ request:URLRequest) throws -> (Data,URLResponse) {
    requests.append(request)
    if let code=firstNetworkFailure {firstNetworkFailure=nil;throw URLError(code)}
    let code=codes.count>1 ? codes.removeFirst():codes[0]
    return (data,HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":"application/octet-stream"])!)
  }
}
struct UpdateFeedTransportTests {
  let feed=URL(string:"https://github.com/example/studio/releases/latest/download/update.json")!
  @Test func assetNegotiationRetryAndFreshRedirects() async throws {
    let fixture=FeedFixture([500,503,200]),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
    #expect(try await updater.check(feed:feed,currentVersion:"0")?.version == "0.2.81")
    let requests=await fixture.requests
    #expect(requests.count == 3 && Set(requests.compactMap(\.url)).count == 3)
    for request in requests {
      #expect(request.value(forHTTPHeaderField:"Accept") == "application/octet-stream")
      #expect(request.value(forHTTPHeaderField:"Cache-Control") == "no-cache")
      #expect(request.value(forHTTPHeaderField:"Authorization") == nil && request.timeoutInterval == 10)
      #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }
  }
  @Test func permanentErrorsDoNotRetryAndReportActualStatus() async throws {
    for code in [401,403,404] {
      let fixture=FeedFixture([code]),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
      do {_ = try await updater.check(feed:feed,currentVersion:"0");Issue.record("HTTP error accepted")}
      catch {#expect(error.localizedDescription.contains("HTTP \(code)"));#expect(!error.localizedDescription.contains("herkese açık"))}
      #expect(await fixture.requests.count == 1)
    }
    let fixture=FeedFixture([429]),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
    do {_ = try await updater.check(feed:feed,currentVersion:"0");Issue.record("429 accepted")}
    catch {#expect(error.localizedDescription.contains("HTTP 429"))}
    #expect(await fixture.requests.count == 3)
  }
  @Test func malformedOversizedAndInsecureManifestsFailClosed() async throws {
    for data in [Data("<html>Error</html>".utf8),Data(repeating:32,count:65536),Data(#"{"version":"0.2.81","downloadURL":"http://example.invalid/app.zip","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8)] {
      let fixture=FeedFixture(data:data),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
      await #expect(throws:SQLFailure.self) {try await updater.check(feed:feed,currentVersion:"0")}
      #expect(await fixture.requests.count == 1)
    }
    let fixture=FeedFixture(),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
    await #expect(throws:SQLFailure.self) {try await updater.check(feed:URL(string:"http://example.invalid/update.json")!,currentVersion:"0")}
    #expect(await fixture.requests.isEmpty)
    let insecure=ApplicationUpdate(manifestTransport:{_ in
      (Data("{}".utf8),HTTPURLResponse(url:URL(string:"http://example.invalid/redirect")!,statusCode:200,httpVersion:nil,headerFields:nil)!)
    })
    await #expect(throws:SQLFailure.self) {try await insecure.check(feed:feed,currentVersion:"0")}

  }
  @Test func transientNetworkRetriesButCancellationDoesNot() async throws {
    let fixture=FeedFixture(network:.timedOut),updater=ApplicationUpdate(manifestTransport:{try await fixture.fetch($0)})
    #expect(try await updater.check(feed:feed,currentVersion:"0.2.81") == nil)
    #expect(await fixture.requests.count == 2)
    let cancelled=FeedFixture(network:.cancelled),other=ApplicationUpdate(manifestTransport:{try await cancelled.fetch($0)})
    do {_ = try await other.check(feed:feed,currentVersion:"0");Issue.record("Cancellation ignored")}
    catch {#expect((error as? URLError)?.code == .cancelled)}
    #expect(await cancelled.requests.count == 1)
  }
}
