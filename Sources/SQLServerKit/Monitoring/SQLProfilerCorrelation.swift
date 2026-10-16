import Foundation

/// Derived links only: raw capture records and export identities remain unchanged.
public enum SQLProfilerCorrelation {
  public struct Relation:Sendable {
    public let source:SQLProfiler.Event
    public let messages:[SQLProfiler.Event]
  }
  private struct Key:Hashable {
    let capture:String
    let connection:UUID
    let session:String
    let activity:UUID
  }
  private struct Call {
    let start:SQLProfiler.Event
    var messages:[SQLProfiler.Event]=[]
  }
  private static func key(_ event:SQLProfiler.Event)->Key? {
    guard let capture=event.captureSession,!capture.isEmpty,!event.session.isEmpty,
      let connection=event.connectionID.flatMap(UUID.init(uuidString:)),
      connection != UUID(uuidString:"00000000-0000-0000-0000-000000000000"),
      let raw=event.activityID,raw.count>37,
      raw.dropFirst(36).first=="-",UInt32(raw.dropFirst(37)) != nil,
      let activity=UUID(uuidString:String(raw.prefix(36))),
      activity != UUID(uuidString:"00000000-0000-0000-0000-000000000000") else {return nil}
    return Key(capture:capture,connection:connection,session:event.session,activity:activity)
  }
  public static func relations(_ events:[SQLProfiler.Event])->[UInt64:Relation] {
    var active:[Key:[Call]]=[:]
    var result:[UInt64:Relation]=[:]
    var previous:[String:UInt64]=[:]
    // Buffer order is server event_sequence within each uniquely named capture.
    for event in events {
      guard let capture=event.captureSession,let sequence=event.sourceSequence else {continue}
      if let last=previous[capture],last == UInt64.max || sequence != last+1 {
        active=active.filter {$0.key.capture != capture}
      }
      previous[capture]=sequence
      guard let key=key(event) else {continue}
      if event.isCallStart {
        active[key]=[Call(start:event)]
        continue
      }
      guard var stack=active[key],var call=stack.popLast(),
        let startSequence=call.start.sourceSequence,startSequence<sequence else {continue}
      if event.kind=="error_reported" {
        call.messages.append(event)
        // An error can be inspected even before completion arrives in a later poll.
        result[event.id]=Relation(source:call.start,messages:[event])
        stack.append(call)
      } else if event.kind==call.start.kind.replacingOccurrences(of:"_starting",with:"_completed") {
        let source=event.sql.isEmpty ? call.start:event
        let relation=Relation(source:source,messages:call.messages)
        result[event.id]=relation
        for message in call.messages {result[message.id]=relation}
      } else {
        // Incomplete/nested mismatches are not evidence of a shared request.
        stack=[]
      }
      active[key]=stack
    }
    return result
  }
}
