Mevcut özellik seti sağlam bir temel. Aşağıdaki öneriler bu temelin üstüne kuruluyor ve "otomatik silme yok, son karar kullanıcıda" ilkesini koruyor.

## 1. Yayından önce gerekenler

| Özellik | Neden gerekli |
|---|---|
| **"Sistem Verisi / kaybolan alan" açıklayıcısı** | macOS kullanıcılarının en büyük derdi bu. Disk 900 GB dolu görünür ama taramada 700 GB çıkar. Aradaki fark çoğunlukla Time Machine'in yerel yedekleri (`tmutil listlocalsnapshots`), silinebilir alan ve takas (swap) dosyalarıdır. "Görünmeyen 48 GB: 31 GB yerel Time Machine yedekleri, 12 GB silinebilir alan…" diye açıklamak rakiplerin çoğunda yok. Bu bilgiler salt-okunur komutlarla okunabiliyor. |
| **Taramayı kaydetme ve geçmiş** | Şu an her açılışta sıfırdan tarıyor. Taramayı kaydetmek üç şeyi birden açar: anında açılış, "geçen haftadan beri ne büyüdü" karşılaştırması ve MCP'nin yeniden taramadan cevap vermesi. Yol haritasında zaten var; diğer birçok özellik buna dayanıyor. |
| **Çoklu seçim ve toplu inceleme** | 40 önbellek klasörünü tek tek kuyruğa eklemek yorucu. Hem listede hem grafikte çoklu seçim gerekiyor. |
| **İmzalı sürüm, otomatik güncelleme, Homebrew** | İndirilebilir, Apple onaylı (notarize) bir DMG; Sparkle ile güncelleme; `brew install --cask lucid-disk`. Bunlar olmadan kullanıcı uygulamayı kendisi derlemek zorunda kalıyor. |

## 2. "WOW" etkisi yaratacaklar

**1. "Diskin 23 gün içinde dolacak" tahmini.** Kaydedilmiş taramalardan büyüme hızını hesaplar ve "En hızlı büyüyen: `~/Library/Caches/com.docker`, haftada +6 GB" gibi bir bilgi verir. Grafiğe "büyüme modu" eklenir: büyüyen dilimler kırmızıya döner. Gerçekten bilgi veren ve ekran görüntüsü paylaşılası bir özellik.

**2. Doğal dille arama: "bir yıldır açmadığım büyük videolar".** Model yalnızca bir filtre üretir (`tür: video, boyut > 1 GB, son erişim > 365 gün`). Filtreyi uygulama kendisi çalıştırır. Model dosya içeriğini görmez ve hiçbir şeye karar vermez; bu yüzden mevcut güvenlik yaklaşımına birebir uyuyor. Ollama ile tamamen yerel çalışabilir.

**3. Asistanın önerisi, uygulamada onay.** Bu, MCP'yi rakiplerden gerçekten ayıracak özellik. Claude Code'a "diskimi temizle" dersin; asistan MCP üzerinden inceler ve öğeleri Lucid Disk'in inceleme kuyruğuna önerir. Kuyruk uygulamada açılır, onayı sen verirsin. MCP yine hiçbir şeyi silmez; yalnızca öneri gönderir. Hikâye de güçlü: "AI önerir, sen onaylarsın."

**4. "Hızlı kazançlar" paneli.** Bilinen, genelde güvenle temizlenebilen şeyleri tek ekranda gösterir:
- 90 gündür dokunulmamış projelerdeki `node_modules` klasörleri
- Kullanılmayan Xcode simülatörleri
- Docker imajları
- Homebrew, npm ve pip önbellekleri
- Eski iPhone yedekleri

Her satır riskini ve sahibi olan aracın komutunu gösterir (örneğin `xcrun simctl delete unavailable`, `brew cleanup`). Uygulama komutu kendisi çalıştırmaz; kullanıcı ya kopyalar ya da tek tıkla onaylayarak çalıştırır. Bu yazılımcılar için büyük bir çekim noktası.

**5. iCloud dosyalarının yerel kopyasını kaldırma.** iCloud'da duran ama Mac'te de yer kaplayan dosyaları bulur ve yerel kopyayı kaldırır (`evictUbiquitousItem`). Dosya silinmez, iCloud'da kalır ve istenince tekrar iner. Güvenli, geri alınabilir ve çok yer açabilen bir işlem.

**6. Grafik renk modları.** Şu an renkler klasör sırasına göre. Buna iki mod eklenebilir: **yaşa göre** (eski veriler soğuk mavi, yeniler sıcak turuncu) ve **türe göre** (video, arşiv, kod…). Aynı disk bambaşka bir hikâye anlatır.

**7. Kopya dosya bulucu.** Önce boyuta, sonra dosyanın bir kısmının parmak izine, en son tam parmak izine bakar. APFS klonlarını ayrı tutar ve "bu iki dosya zaten disk bloklarını paylaşıyor, silmek yer açmaz" diye dürüstçe söyler. Bu dürüstlük vurgusu Lucid Disk'e özgü olur.

**8. Menü çubuğu ve bildirimler.** Menü çubuğunda boş alanı gösteren küçük bir gösterge. Alan %10'un altına düştüğünde "Son 7 günde +18 GB, çoğu Downloads'ta" gibi bir bildirim.

## 3. Sonra yapılabilecekler
- **Shortcuts / Siri:** "Diskimde ne kadar yer kaldı?", "Downloads'u tara" gibi kısayol eylemleri.
- **Disk raporu:** PDF veya Markdown olarak dışa aktarma; ekip veya destek talebi için.
- **Yeni MCP araçları:** `find_duplicates`, `explain_growth`, `find_old_files`; kaydedilmiş tarama geldikten sonra kolayca eklenir.
- **Birim karşılaştırma:** Harici disk ile ana diski yan yana gösterme.

## Önerim
Sıra şöyle olmalı: **kaydedilmiş tarama → büyüme tahmini → asistandan kuyruğa öneri.**

İlki temel, diğer ikisi en güçlü iki WOW özelliği. Üçü birlikte Lucid Disk'i "disk haritası"ndan "diskinin zaman içindeki hikâyesini anlatan ve AI ile birlikte karar veren araç"a taşır. "Sistem Verisi" açıklayıcısı da hızlı yapılabilen ve çok ses getirecek bir iş; araya kolayca girebilir.

Hangisiyle başlamamı istersin? İstersen bu listeyi paylaşılabilir bir yol haritası sayfasına da çevirebilirim.