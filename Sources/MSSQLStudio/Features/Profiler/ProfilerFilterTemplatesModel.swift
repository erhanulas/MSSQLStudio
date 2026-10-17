import Foundation
import Combine
import SQLServerKit

/// One shared workspace owner keeps all server windows on the same global template list.
@MainActor final class ProfilerFilterTemplatesModel:ObservableObject {
  @Published private(set) var templates:[ProfilerFilterTemplate]=[]
  @Published private(set) var busy=false
  @Published private(set) var error=""
  private var loaded=false
  private let store:ProfilerFilterTemplateStore?
  init(store:ProfilerFilterTemplateStore?=nil) {self.store=store}
  var ready:Bool {loaded && store != nil}
  func load() async {
    guard !busy,!loaded else {return}
    busy=true;defer {busy=false}
    do {templates=try await store?.load() ?? [];loaded=true;error=""}
    catch {self.error=error.localizedDescription}
  }
  @discardableResult func save(_ value:ProfilerFilterTemplate) async -> Bool {
    guard !busy,loaded,let store else {return false}
    busy=true;defer {busy=false}
    do {templates=try await store.save(value);error="";return true}
    catch {self.error=error.localizedDescription;return false}
  }
  func remove(_ id:UUID) async {
    guard !busy,loaded,let store else {return}
    busy=true;defer {busy=false}
    do {templates=try await store.remove(id);error=""}
    catch {self.error=error.localizedDescription}
  }
}
