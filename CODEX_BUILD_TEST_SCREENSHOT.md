# Codex: Derle, test et ve ekran görüntüsünü göster

Bu depoda manuel GitHub Actions akışı: `.github/workflows/capture-screenshots.yml` (GitHub Actions görünen adı: **Build Test Screenshot**).

## Codex komutu

> Derle, test et ve ekran görüntüsünü göster. Önce değişiklikleri commit/push yap. Ardından **Build Test Screenshot** iş akışını `main` dalında `platform=android` ile başlat (iOS istersem `ios`, ikisini istersem `both`). `flutter analyze` ve `flutter test` sonuçlarını, derleme sonucunu ve simülatör ekran görüntüsünü kontrol et. Hata varsa ilgili adımın logunu incele ve hatayı raporla. Başarılıysa `android-login` veya `ios-login` artifact içindeki PNG'yi göster. Çalıştırma veya artifact indirme yetkin yoksa bunu açıkça söyle; başarılı olduğunu varsayma.

## İş akışı

1. `workflow_dispatch` ile isteğe bağlı tetikleme. Varsayılan platform Android.
2. Ubuntu üzerinde `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`.
3. Kontroller başarılıysa Android ve/veya iOS için `lib/screenshot_main.dart` giriş noktasıyla gerçek uygulama derlemesi.
4. Gerçek Android emülatörü / iPhone simülatöründe başlatma, PNG ekran görüntüsü.
5. GitHub Actions run sayfasındaki **Artifacts** bölümünden `android-login` / `ios-login` ZIP indirme.

## Önemli sınırlar

- Ekran görüntüsü üretimi için test giriş noktası `lib/screenshot_main.dart` kullanılır; bu giriş noktası Firebase yerine sahte oturum/profil sağlayıcıları kullanır. Üretim giriş noktası `lib/main.dart` ile birebir aynı çalışma yolu değildir.
- Mevcut ekran görüntüsü akışı **giriş ekranını** yakalar. Diğer ekranlar için ayrı senaryo/gezinti otomasyonu gerekir.
- `flutter analyze` ve `flutter test` tüm depoda çalışır. Bu akışta screenshot derlemesi uygulamanın bütün üretim özelliklerini test etmez.
- GitHub-hosted runner her çalıştırmada sıfırdan başlar; Flutter önbelleği olsa da emülatör ve derleme kalıcı değildir.
- GitHub Actions'ın kendisi PNG'yi Codex sohbetine otomatik göndermez. Codex'in workflow dispatch, run okuma, artifact indirme ve görsel gösterme yetkileri ayrıca doğrulanmalıdır.
- Başlatma/sonuç alma yetkisi yoksa Actions arayüzünden manuel tetikle ve run bağlantısını paylaş.
- Bu iş akışı PR birleştirilip `main` dalında görünmeden ana daldan çalıştırılamaz.

## Bağlantı

https://github.com/fatihbozkurt58/matematik-macera-evreni/actions/workflows/capture-screenshots.yml
