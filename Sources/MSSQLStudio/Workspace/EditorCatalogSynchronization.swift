import Foundation

extension StudioState {
  /// Refresh once per database and fan out the immutable snapshot to all open consoles.
  func synchronizeEditorCatalogs(_ server:ConnectedServer) {
    guard server.online,servers.contains(where:{$0 === server}) else {return}
    for doc in documents where doc.server === server {doc.offlinePreviewRequest=UUID()}
    editorCatalogRequests[server.id]=UUID()
    guard editorCatalogTasks[server.id]==nil else {return}
    editorCatalogTasks[server.id]=Task { [weak self,weak server] in
      guard let self,let server else {return}
      defer {editorCatalogTasks[server.id]=nil;editorCatalogRequests[server.id]=nil}
      while let request=editorCatalogRequests[server.id],server.online,servers.contains(where:{$0 === server}) {
        let generation=server.generation,indexRevision=server.catalogIndexRevision
        let databases=Set(documents.filter {$0.server === server}.map(\.database))
        for database in databases.sorted() {
          guard !Task.isCancelled,server.online,server.generation==generation,server.catalogIndexRevision==indexRevision,editorCatalogRequests[server.id]==request else {break}
          guard let source=documents.first(where:{$0.server === server && $0.database==database}) else {continue}
          await source.loadSymbols()
          guard server.online,server.generation==generation,server.catalogIndexRevision==indexRevision,editorCatalogRequests[server.id]==request,servers.contains(where:{$0 === server}) else {break}
          guard source.catalogDatabase==database,let catalog=source.intelligenceCatalog,source.catalogError==nil else {continue}
          for doc in documents where doc !== source && doc.server === server && doc.database==database {
            doc.applyConnectedCatalog(catalog,database:database,generation:generation,verified:source.catalogVerified)
          }
        }
        if editorCatalogRequests[server.id]==request {break}
      }
    }
  }
}
