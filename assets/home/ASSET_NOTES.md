# Ana sayfa haritası — tasarım sürümü

## Kullanılan son sürüm: v2

- Etkin dosya: `adventure-archipelago-v2.png`; SHA-256 `5571979e17064d58af0f29cd873a51f7febdf0e8b0a1ecb7cc9811f7045574d5`.
- Built-in imagegen, aşağıdaki v1 görselini referans alan style-transfer düzenlemesi; v1 silinmedi. Kaynak dosya: `/Users/fatih/.codex/generated_images/01a15101-2a89-7350-aae5-9885b6ea06a2/exec-e092513e-3c0a-4047-b486-98aec929a2da.png`.
- Daha yuvarlak, sade ve canlı çocuk oyunu estetiği; aynı beş ada/merkez ve pin sırası. Özgün boyut/oran korunarak projeye kopyalandı.
- Nunito fontu yerel ve çevrimdışı paketlendi: `assets/fonts/Nunito.ttf`; SHA-256 `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207`. Kaynak [Google Fonts Nunito](https://github.com/google/fonts/tree/main/ofl/nunito); lisans metni `assets/fonts/Nunito-OFL.txt` uygulama paketine dahil.
- Varsayılan ana başlık 23sp; diğer başlık/etiketler 12–22sp. İşletim sistemi erişilebilirlik metin ölçeği korunur. Üst logo 34dp; eylem içindeki logo 24dp. Büyük marka/başlık yok.
- Kısa giriş fade/slide, seçim ölçeği/renk, haritanın adaya odaklanması, yatay ada kaydırması, 48dp dokunma hedefleri, seçime haptic geri bildirim; reduced motion ayarında animasyon süreleri sıfırdır.

### v2 prompt

```text
Edit target: the supplied vertical five-island map illustration. Use case style-transfer. Keep EXACTLY the same five major island positions, connecting path, and overall vertical composition: forest island with compass flag at bottom-left, harbor second on right, castle third middle-left, geometry garden fourth upper-right, village fifth top-left. Transform the entire rendering into delightful high-end stylized 3D mobile adventure game art for primary-school children ages 6-11. Softer rounder chunky toy-like rock formations, simplified clean beautifully composed miniature trees, friendly plump silhouettes, bright turquoise water, cheerful fresh spring greens, warm coral roofs, cream sunny pathways, little soft clouds at the outer edges. Sophisticated contemporary color harmony, clean tactile clay materials, broad soft lighting and depth, greatly reduce photorealistic detail and tiny visual clutter. The map should feel joyful, playful and immediately readable on a small phone, like a premium lovingly crafted children's game world. Retain all five islands and approximate center positions. No characters or people, no text, no letters or numerals, no UI, no coins or reward stars, no watermarks. Portrait composition with original proportions. The map will be embedded into a pale sky/mint rounded panel in Flutter; image is decorative; all labels are native UI. Background fully opaque.
```

## Önceki v1 — tarihsel tasarım

- Dosya: `adventure-archipelago.png`; tarih: 19.10.2026.
- Araç: built-in `image_gen` / imagegen becerisi; CLI veya ayrı ücretli API kullanılmadı.
- Kaynak: `/Users/fatih/.codex/generated_images/01a15101-2a89-7350-aae5-9885b6ea06a2/exec-32789c01-d457-4111-b30a-c3d22a1985a8.png`; projeye değiştirilmeden kopyalandı.
- Kullanım: `AdventureHome` için temsili beş adalı illüstrasyon. 25 adanın nihai eğitim varlıkları, soru görselleri veya yayın kabulü değildir.
- Görsel metin/puan/ilerleme taşımaz; adlar, sıra, seçim ve erişilebilir etiketler Flutter katmanındadır. Görselin kendisi dekoratiftir; eşdeğer ada/bölüm listesi sunulur.
- Durum: tasarım sürümü, kullanıcı görsel kabulü bekliyor; tamamlandı işareti yok.

## Kullanılan prompt

```text
Use case: stylized-concept. Asset type: production illustration background for a premium, modern Turkish children's mathematics adventure mobile app home map. Generate a vertical 1024x1536 composition, no text, no letters, no numerals, no UI or border. A beautifully art-directed isometric 3D clay-render archipelago of FIVE distinct small lush floating islands linked by a meandering dotted cream stepping-stone trail, on a very pale mint/aqua atmospheric sea background #EAF5EF. Gentle warm morning light, sophisticated forest green, sage, creamy sandstone, coral accents, subtle gold. Each island miniature diorama feels handcrafted and crisp, not shiny plastic: first forest with stone arch and small orange compass flag, second harbor with small lighthouse, third small fairy castle, fourth geometric garden with stone shapes, fifth village with trees. Position island centers at normalized coordinates: first (0.28,0.20), second (0.73,0.35), third (0.30,0.51), fourth (0.72,0.67), fifth (0.35,0.83). Lots of calm negative space between islands to place interactive numbered controls in native Flutter. Three-quarter overhead camera, deep dimensional rock bases, miniature trees, fine quiet ripples, soft diffuse shadows. First island slightly larger and most visually prominent. Edge-to-edge illustrated scenery fading into mint background at all edges. Outstanding polished mobile game illustration quality, inviting for ages 6-11 yet refined contemporary editorial art direction. No people, no coins, no treasure chest, no stars, no text, no logos, no watermark.
```

## Uygulama eşlemesi

Üretilen görselde orman adası altta yer alıyor; bu nedenle Flutter pinleri görseldeki gerçek merkezlere göre alttan üste 1–5 olarak eşlendi. Harita özgün en-boy oranında gösterilir; dikey kaydırma ve ada seçimine otomatik odak vardır. Ekranın altındaki ada seçimi/keşfet eylemi sabittir.

- PNG SHA-256: `261fca1eabf257d93a0568dc2a2bec083cbff4f6953c475ed8a99b00c684c7ce`.
