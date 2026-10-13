# Lucid Disk — agent guide

This is the **open-source Community edition** (Apache 2.0) of an open-core product. A private Pro edition depends on this repository; see [EDITIONS.md](EDITIONS.md).

## Architecture

- `Sources/LucidDiskCore` — the whole app as a library: scanner, safety rules, AI providers, UI, saved scans, space breakdown, and the extension points (`Extensions/LucidDiskExtensions.swift`).
- `Sources/LucidDisk` — the thin Community `@main` app: `LucidDiskMainScene()` with nothing installed.
- `mcp/` — the read-only Python MCP server. Its risk rules mirror `DeletionSafety.swift`; both test suites read `Tests/Fixtures/deletion-safety.json`.

## Never

- Add paid-edition code, licensing, or "is Pro" switches here. Pro features live only in the private repository.
- Move an existing Community feature behind a paywall or weaken it.
- Delete permanently, or move anything to the Trash outside the review queue → confirmation → `DeletionSafety.validateBeforeTrash` flow. Saved scans must never trash.
- Let AI output or an extension change a safety verdict. Models only fill "probable purpose".
- Add write, move, or delete tools to the MCP server.

## When you change things

- A new hook another edition needs: add a small public extension point in `LucidDiskCore` with a test and document it in `EDITIONS.md`.
- Every new user-facing string needs an English and Turkish entry in `Sources/LucidDiskCore/Resources/Localizable.xcstrings`.
- Safety rules: change Swift and Python together and extend the shared fixture.
- Data handling (what is stored or sent): update `PRIVACY.md`.

## Checks

```bash
swift test
uv run --project mcp --with pytest pytest mcp/tests
Tools/review_ui.sh -AppleLanguages '(en)'   # UI changes, on an idle desktop
./build_app.sh                              # packaging
```

## Releases

Follow [docs/releasing.md](docs/releasing.md): bump `APP_VERSION`/`APP_BUILD` in `build_app.sh`, merge to `main`, build a signed candidate, then tag `vX.Y.Z` on that exact commit. Never sign with `--deep`, never replace a published asset. The Pro edition pins the core to these tags.

Architecture and conventions: [docs/architecture.md](docs/architecture.md), [docs/development.md](docs/development.md), [docs/safety.md](docs/safety.md).

<!-- project-managment:managed:start project=cd70d5c6-6fbf-416f-a347-8595d1b75148 -->

# Project Managment — proje köprüsü

Proje adı: Lucid Disk
Proje kimliği: cd70d5c6-6fbf-416f-a347-8595d1b75148
Proje çalışma alanı: http://127.0.0.1:3210/projects/cd70d5c6-6fbf-416f-a347-8595d1b75148
GitHub deposu: https://github.com/serkan-uslu/lucid-disk
Depo rolü: Ana depo
GitHub Projects panosu: https://github.com/users/serkan-uslu/projects/12
Yönetilen yapı sürümü: 16

Bu blok Project Managment tarafından yönetilir ve eşitlenir; içini düzenleme. Depoya özel talimatları bloğun dışına yaz. Proje tanımı, kararlar ve geliştirme geçmişi bu dosyada değil, Project Managment veritabanındadır.

## Her oturumda

1. Depoda AGENTS.md veya CLAUDE.md commit edilmemişse ve değişiklik yalnızca Project Managment bloğundaysa, işe başlamadan yalnızca bu iki dosyayı ayrı bir commit olarak al: git commit -m "Refresh Project Managment agent bridge" -- AGENTS.md CLAUDE.md. Bloğun dışında da değişiklik varsa dokunma ve kullanıcıya sor. Gönderme.
2. MCP ile get_project (projectId: cd70d5c6-6fbf-416f-a347-8595d1b75148) ve get_structure oku: kapsam, mevcut odak, kararlar, son günlük kayıtları ve ortak kurallar. get_structure içinde includeInAgents: true olan bölümler bağlayıcı çalışma kurallarıdır; diğerlerine gerektiğinde başvur.
3. list_tasks ile panonun kayıtlı halini oku. Güncel durum gerekiyorsa sync_project çağır ve yeniden oku.
4. Kullanıcının her geliştirme isteğini panoda bir göreve bağla. Aynı işi kapsayan görev yoksa get_structure içindeki taskRules kurallarına göre create_task ile aç; açıklamada şu bölümler olsun: Amaç, Kapsam, Kabul kriterleri, Doğrulama, Bağımlılıklar; kabul kriterleri zorunludur. İşe başlarken görevi panonun devam eden durumuna al. Görev açmak ve durumunu güncellemek için kalıcı yetkin var; yalnızca soru soran veya bilgi isteyen mesajlar için görev açma. Pano bağlı değilse görev açmadan bunu bildir.
5. Kayıtlı kapsamda kal ve ilerleme bildirmeden önce gerçek depoyu incele.
6. Anlamlı bir işten sonra append_development_log veya record_progress ile gerçekte yapılanı, çalıştırılan kontrolleri ve sonraki adımı yaz. Önemli kararlar için record_decision, mevcut odak için update_project_focus kullan. Kayıtları Türkçe yaz.
7. Görevi yalnızca kabul ölçütleri doğrulanınca Done yap; commit, push veya merge tek başına kanıt değildir. Sırları ve özel notları görevlere, commit'lere veya uzak depolara koyma.
8. Kullanıcı projects klasöründeki mevcut bir projeyi Project Managment'a almanı isterse get_structure içindeki "Mevcut Projeyi Project Managment'a Alma" bölümünü izle. Mevcut bir projede yeni çalışma alanı oluşturan provizyon adımını kullanma.

## Project Managment bağlantısı

Project Managment http://127.0.0.1:3210 adresinde çalışır durumda olmalıdır. Bu proje için kapsamlı MCP sunucusunun adı `project_management_cd70d5c66fbf416fa3478595d1b75148`; genel sunucu `project_management` adını taşır ve her çağrıda `projectId: cd70d5c6-6fbf-416f-a347-8595d1b75148` ister. MCP araçları görünmüyorsa bunu kullanıcıya bildir; kurulum http://127.0.0.1:3210/settings sayfasında anlatılır. Masaüstü uygulamalarının ayar dosyalarını kendin düzenleme.

MCP kullanılamıyorsa yalnızca bu bilgisayardaki yerel API'yi kullan: GET http://127.0.0.1:3210/api/projects/cd70d5c6-6fbf-416f-a347-8595d1b75148, GET http://127.0.0.1:3210/api/structure?projectId=cd70d5c6-6fbf-416f-a347-8595d1b75148 ve gerektiğinde GET http://127.0.0.1:3210/api/projects/cd70d5c6-6fbf-416f-a347-8595d1b75148/board. İsteklere X-Structure-Client: codex başlığını ekle; bu başlık ve MCP istemci adı doğrulanmış kimlik değildir. Yazma isteklerinde Content-Type: application/json, Origin: http://127.0.0.1:3210, son okunan version ve işlem için benzersiz idempotencyKey gönder. Başarısız isteği başarılı gibi bildirme.
<!-- project-managment:managed:end -->
