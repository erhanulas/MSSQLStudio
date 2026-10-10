# Kalıcı kişisel imza ve Keychain

## Mevcut kimlik

- Bundle ID: `local.mssqlstudio.app`; Keychain hizmeti: `local.mssqlstudio.servers`.
- Sertifika SHA-1: `adce16b1a3567d8c5fe2ed261e89493611cb7b9d`.
- Designated requirement: `identifier "local.mssqlstudio.app" and certificate leaf = H"adce16b1a3567d8c5fe2ed261e89493611cb7b9d"`.
- Yapılandırma: `Sources/SQLServerKit/Resources/SigningIdentity.json`. Burada yalnızca herkese açık kimlik vardır. SHA-1 burada sertifika kimliği pinidir; ZIP bütünlüğü SHA-256 ile kontrol edilir.

Her ikilinin içerik özeti/CDHash değeri derlemede değişebilir. Keychain sürekliliği için sabit kalan belirleyici kod gereksinimidir. Eski ad-hoc derlemeler bu sabit sertifika kimliğini kullanmıyordu. Eski kayıtların izinleri kendiliğinden yeni kimliğe dönüşmez. Güncel Xcode debug derlemesi de ad-hoc olduğundan yayın kimliğinin yerine kullanılmamalıdır.

## Dağıtım ve özel anahtar

`scripts/build-app.sh` önce derler, sonra `scripts/signing.py` ile sabit kimlikle imzalar. Sertifika yoksa yayın başarısız olur; ad-hoc yedek imza yoktur. ZIP'ten çıkarılan uygulamanın imzası tekrar doğrulanır. Güncelleyici HTTPS, ZIP SHA-256, bundle ID, yeni sürüm ve aynı sertifika/DR kontrolünden sonra uygulamayı hazırlar. PKG yalnızca uygulamayı yerleştirir; Keychain, Preferences ve Application Support taşınmaz veya silinmez.

GitHub Actions aynı PKCS#12 kimliğini `MSSQL_SIGNING_P12` ve `MSSQL_SIGNING_PASSWORD` Actions secrets üzerinden kullanır. `scripts/ci-signing.py` dosyayı geçici dizinde 0600 izinle oluşturur, geçici CI Keychain'e aktarır ve dosyayı kaldırır; iş sonunda Keychain de kaldırılır. Özel anahtarı kaynak kontrolüne, artifact'e, log'a veya uygulama paketine koymayın. Aynı kimliğin şifreli çevrimdışı yedeğini güvenli parola kasasında tutun. Sertifika/anahtarı her sürümde yeniden üretmeyin. Yerel inceleme sırasında yayın özel anahtarı bu Mac'in kullanılabilir imza kimlikleri arasında bulunmadı; mevcut CI secrets yeniden oluşturulmadı veya dışarı çıkarılmadı.

Sertifikanın mevcut geçerliliği 9 Ekim 2026–6 Ekim 2036 UTC. Anahtar kaybı veya sertifika değişimi ayrı bir kontrollü geçiş gerektirir; aynı sertifika gibi davranacağı varsayılamaz. Repo erişimini ve workflow değişikliklerini korumak özel anahtarı korumanın bir parçasıdır.

## Mevcut kayıtları düzeltme

Ayarlar → Keychain izinlerini yenile, yayın sertifikasını doğrulayan uygulamadan çalışır. macOS eski erişim listesini değiştirmek için sistem parolası/onayı isteyebilir. İşlem kayıt değerlerini okumaz, dışarı aktarmaz veya silmez; aynı service/account üzerindeki erişimi yeniler. Önceki izin girdilerini otomatik sıfırlamaz. Normal parola güncellemeleri ACL'yi yeniden yazmaz. “Tüm uygulamalara izin ver”, genel partition-list değişikliği, Keychain sıfırlama veya Gatekeeper kapatma kullanılmaz. CI'deki partition-list ayarı yalnızca geçici imzalama özel anahtarına aittir; kullanıcının bağlantı kayıtlarına uygulanmaz.

## Doğrulama sınırları

`signing-audit.yml` elle çalıştırılabilir: iki farklı derleme aynı sertifikayla imzalanır; gerçek ServerVault koduyla yalnızca geçici test Keychain'inde sentetik kayıt oluşturulur/güncellenir. İkinci derleme ve farklı dosya yolu, kullanıcı etkileşimi kapalıyken kaydı okuyabilmelidir. Ad-hoc ikili okuma/izin yenileme yetkisi kazanamaz. Ayrıca v0.2.42 ve v0.2.43 resmi ZIP imzaları pinlenen kimlikle doğrulanır. Bu workflow yayın oluşturmaz.

ACL değiştirme, macOS sahiplik onayı gerektirebilir ve başsız CI'de başarı diye raporlanmaz. Gerçek kullanıcı kaydının sistem onayıyla yenilenmesi ayrı yerel kontroldür. Bu testler gerçek kullanıcı oturumunun tam uygulama güncellemesi/restart akışıyla veya tüm macOS sürümleriyle eşdeğer değildir. Kilitli Keychain ve başka güvenlik politikaları parola isteyebilir.

Yerel sertifika Apple Developer ID / notarization değildir. `codesign` doğrulaması ile Gatekeeper değerlendirmesi farklıdır; 10 Ekim 2026 incelemesinde v0.2.43 ZIP uygulaması `spctl --assess --type execute` tarafından reddedildi. Bu sonucu aşmak için güvenlik ayarları değiştirilmedi. İnternetten ilk kurulumun sistem güvenlik onayları, Keychain sürekliliğinden ayrı değerlendirilmelidir.

Apple kaynakları: [Kod kimliği ve güncellemeler](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Kişisel sertifikalar ve designated requirement](https://developer.apple.com/library/archive/technotes/tn2206/), [SecAccessCreate](https://developer.apple.com/documentation/security/secaccesscreate(_:_:_:)), [kSecAttrAccess](https://developer.apple.com/documentation/security/ksecattraccess).
