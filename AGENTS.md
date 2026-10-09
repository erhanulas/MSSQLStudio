# MSSQL Studio geliştirme kuralları

- Bu proje önceki NativeSQL'den bağımsızdır. Eski projeyi değiştirmeyin veya kodunu kopyalamayın.
- Swift 6 concurrency kontrolünü koruyun. AppKit/SwiftUI main actor'da, blocking ODBC worker queue'da kalmalı.
- Her sorgu sekmesi kendi bağlantısını kullanır. Metadata UI sorgusunun transaction'ını veya database context'ini değiştirmemeli.
- TextKit 2'yi koruyun; `layoutManager` erişimiyle TextKit 1'e geçmeyin. Native scroll/find/undo/completion davranışını test edin.
- SQL identifier/literal escaping merkezi helper'lardan geçer. Password, API key ve gerçek kullanıcı sonuçlarını kaynak/test fixture/log içine yazmayın.
- Script tasarım ekranları SQL'i önce editöre aktarır. Şablon/AI önerisini otomatik çalıştırmayın. Bilinmeyen eklenti kodu yüklemeyin.
- Büyük sonuçları sınırlayın, partial durumunu ve SQL diagnostics'ini görünür tutun. İptal transaction rollback değildir.
- Canlı testler yalnızca adı belirtilen localhost test ortamında, izole nesneler ve rollback ile yapılır. Mevcut kullanıcı verisine yazmayın.
- Uygulama ve test build'lerini `/tmp` altında üretin. Çıktıya signed .app yerine ZIP koyun; imzayı ZIP çıkarıldıktan sonra da doğrulayın.
- İlgili değişikliklerde core testleri ve native UI smoke testleri çalıştırın. Kerberos/AI/Agent gibi dış koşulları doğrulanmış gibi raporlamayın.
- `README.md` ve `TEST-REPORT.md` çalışan kapsamı ve eksikleri doğru anlatmalı. UI'da ileri modüller için sahte düğme/başarı durumu eklemeyin.
