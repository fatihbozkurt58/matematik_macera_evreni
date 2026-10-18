import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'student_profile.dart';

/// Read-only curriculum catalog. Game access remains a server-side decision.
class AdventureIsland {
  const AdventureIsland(this.id, this.name, this.lessons);
  final String id;
  final String name;
  final List<String> lessons;
}

List<AdventureIsland> islandsForGrade(int grade) => switch (grade) {
  1 => const [
    AdventureIsland('g1_numbers', 'Sayılar Ormanı', [
      '20’ye kadar çokluk',
      'Karşılaştırma ve sıra',
      'Ritmik sayma ve örüntü',
    ]),
    AdventureIsland('g1_quantities', 'Ölçme Köyü', [
      'Uzunlukları karşılaştırma',
      'Aynı birimle ölçme',
      'Paralarımızı tanıma',
    ]),
    AdventureIsland('g1_operations', 'İşlem Vadisi', [
      'Birleştirme',
      'Ayırma',
      'Eşitlik ve ters ilişki',
    ]),
    AdventureIsland('g1_geometry', 'Şekiller Bahçesi', [
      'Konum ve yön',
      'Eş nesneleri bulma',
      'Şekilleri sınıflandırma',
    ]),
    AdventureIsland('g1_data', 'Veri Çayırı', [
      'Küçük verileri okuma',
      'Sıklıkları karşılaştırma',
      'Veriden karar verme',
    ]),
  ],
  2 => const [
    AdventureIsland('g2_numbers', 'Sayılar Şehri', [
      '100’e kadar sayılar',
      'Sayıları karşılaştırma',
      'Artışlı örüntü',
    ]),
    AdventureIsland('g2_quantities', 'Ölçme Pazarı', [
      'Bütün, yarım ve çeyrek',
      'Saat okuma',
      'Uzunlukları karşılaştırma',
    ]),
    AdventureIsland('g2_operations', 'İşlem Kalesi', [
      'Toplama ve çıkarma',
      'Eş gruplama',
      'Adil paylaşım',
    ]),
    AdventureIsland('g2_geometry', 'Geometri Parkı', [
      'Cisimlerin özellikleri',
      'Konum ve yön',
      'Şekillerin özellikleri',
    ]),
    AdventureIsland('g2_data', 'Veri İstasyonu', [
      'Verileri okuma',
      'Sıklıkları karşılaştırma',
      'Veriden karar verme',
    ]),
  ],
  3 => const [
    AdventureIsland('g3_numbers', 'Büyük Sayılar Vadisi', [
      '1000’e kadar sayılar',
      'Sayıları karşılaştırma',
      'Artışlı örüntü',
    ]),
    AdventureIsland('g3_quantities', 'Kesir ve Ölçme Limanı', [
      'Kesirde pay ve payda',
      'Analog saat',
      'Metre ve santimetre',
    ]),
    AdventureIsland('g3_operations', 'İşlemler Krallığı', [
      'Toplama ve çıkarma',
      'Eş gruplama',
      'Eşit paylaşım',
    ]),
    AdventureIsland('g3_geometry', 'Geometri Atölyesi', [
      'Cisimler ve yüzler',
      'Çokgenler',
      'Düşey simetri',
    ]),
    AdventureIsland('g3_data', 'Veri Köyü', [
      'Tablo ve grafik okuma',
      'Sıklıkları karşılaştırma',
      'Veriden karar verme',
    ]),
  ],
  4 => const [
    AdventureIsland('g4_numbers', 'Doğal Sayılar Ülkesi', [
      'Çok basamaklı sayılar',
      'Sayıları sıralama',
      'Sabit artışlı örüntü',
    ]),
    AdventureIsland('g4_operations', 'Dört İşlem Adası', [
      'Toplama',
      'Çarpma',
      'Bölme',
    ]),
    AdventureIsland('g4_fractions', 'Kesir Krallığı', [
      'Kesir modelleri',
      'Denk kesirler ve sıralama',
      'Eş paydalı işlemler',
    ]),
    AdventureIsland('g4_measurement', 'Ölçme Laboratuvarı', [
      'Metre ve santimetre',
      'Saat ve süre',
      'Karenin çevresi',
    ]),
    AdventureIsland('g4_geometry_data', 'Geometri ve Veri Kalesi', [
      'Kenar ve köşe',
      'Düşey simetri',
      'Sütun grafikleri',
    ]),
  ],
  5 => const [
    AdventureIsland('g5_geometry', 'Geometrik Şekiller Üssü', [
      'Doğru ve ışın',
      'Açı ölçme',
      'Çokgenler',
    ]),
    AdventureIsland('g5_numbers', 'Sayılar Akademisi', [
      'Çok basamaklı sayılar',
      'Doğal sayılarla işlem',
      'Kesrin gösterimleri',
    ]),
    AdventureIsland('g5_quantities', 'Geometrik Nicelikler Lab.', [
      'Çevre ve kenar',
      'Alan ve birim',
      'Kesirleri karşılaştırma',
    ]),
    AdventureIsland('g5_algebra', 'Cebirsel Düşünme Üssü', [
      'Eşitlik ilişkisi',
      'Örüntü kuralı',
      'Aritmetik algoritmalar',
    ]),
    AdventureIsland('g5_data_probability', 'Veri ve Olasılık Merkezi', [
      'Soru ve veri planı',
      'Veri yorumlarını sınama',
      'Olasılık spektrumu',
    ]),
  ],
  _ => throw ArgumentError.value(grade, 'grade'),
};

class AdventureHome extends StatefulWidget {
  const AdventureHome({
    super.key,
    required this.profile,
    required this.onLogout,
    this.busy = false,
    this.error,
  });
  final StudentProfile profile;
  final Future<void> Function() onLogout;
  final bool busy;
  final String? error;

  @override
  State<AdventureHome> createState() => _AdventureHomeState();
}

class _AdventureHomeState extends State<AdventureHome> {
  static const ink = Color(0xFF203E4A);
  static const forest = Color(0xFF17785E);
  int selected = 0;
  bool listMode = false;
  final mapController = ScrollController();
  List<AdventureIsland> get islands => islandsForGrade(widget.profile.grade);

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }

  void selectIsland(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      selected = index;
      listMode = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !mapController.hasClients) return;
      const ys = [.79, .60, .43, .27, .13];
      final position = mapController.position;
      final extent = position.maxScrollExtent;
      final total = extent + position.viewportDimension;
      final top = (total * ys[index] - position.viewportDimension / 2).clamp(
        0.0,
        extent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        mapController.jumpTo(extent - top);
      } else {
        mapController.animateTo(
          extent - top,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void openRoute() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7FAF5),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .72,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Text(
                  'Adalarını keşfet',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: islands.length,
                  itemBuilder: (context, index) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    leading: Text(
                      '0${index + 1}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: forest,
                      ),
                    ),
                    title: Text(
                      islands[index].name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    trailing: Icon(
                      selected == index
                          ? Icons.check_circle_rounded
                          : Icons.chevron_right_rounded,
                      color: forest,
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      selectIsland(index);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AdventureHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.profile.grade != widget.profile.grade) {
      selected = 0;
    }
  }

  void openAccount() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7FAF5),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Kaşifim',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.profile.nickname,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${widget.profile.grade}. sınıf',
                style: const TextStyle(fontSize: 16, color: Color(0xFF526E61)),
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: widget.busy
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        widget.onLogout();
                      },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Çıkış yap'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openIsland(int index) {
    setState(() => selected = index);
    final island = islands[index];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7FAF5),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ADA ${index + 1} · ${widget.profile.grade}. SINIF',
                style: const TextStyle(
                  color: forest,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                island.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < island.lessons.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE4EDE2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: forest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            island.lessons[i],
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Haritaya dön'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F3),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFFE4ECE1)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10174234),
                    blurRadius: 20,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: duration,
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE5AB),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          '${selected + 1}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: Column(
                            key: ValueKey(selected),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                islands[selected].name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                '3 bölüm',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF658077),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => openIsland(selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: forest,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.asset(
                              'assets/branding/app-icon-master.png',
                              width: 24,
                              height: 24,
                              excludeFromSemantics: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Flexible(
                            child: Text(
                              'Adayı keşfet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded, size: 19),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/branding/app-icon-master.png',
                            width: 34,
                            height: 34,
                            excludeFromSemantics: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Merhaba, ${widget.profile.nickname}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ink,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Kaşifim',
                          onPressed: widget.busy ? null : openAccount,
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFFFE7C9),
                            foregroundColor: const Color(0xFF876032),
                            minimumSize: const Size(48, 48),
                          ),
                          icon: const Icon(Icons.face_rounded, size: 26),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            const Text(
                              'Haydi keşfe!',
                              style: TextStyle(
                                fontSize: 23,
                                height: 1.2,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE1EFE1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${widget.profile.grade}. sınıf',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: forest,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: openRoute,
                              icon: const Icon(Icons.route_rounded, size: 18),
                              label: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Keşif rotan',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.expand_more_rounded, size: 18),
                                ],
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: forest,
                                backgroundColor: Colors.white,
                                side: const BorderSide(
                                  color: Color(0xFFDDE9DE),
                                ),
                                minimumSize: const Size(48, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() => listMode = !listMode);
                              },
                              icon: Icon(
                                listMode
                                    ? Icons.map_outlined
                                    : Icons.format_list_bulleted_rounded,
                                size: 19,
                              ),
                              label: Text(
                                listMode ? 'Harita görünümü' : 'Liste görünümü',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: forest,
                                minimumSize: const Size(48, 48),
                              ),
                            ),
                          ],
                        ),
                        if (widget.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              widget.error!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFFAE2626),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  sliver: SliverToBoxAdapter(
                    child: listMode ? _islandList() : _mapCanvas(reduced),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _islandList() => Column(
    key: const ValueKey('island-list'),
    children: [
      for (var i = 0; i < islands.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Material(
            color: selected == i ? const Color(0xFFE3F1E5) : Colors.white,
            borderRadius: BorderRadius.circular(23),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(23),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == i
                      ? const Color(0xFFFFDF91)
                      : const Color(0xFFF0F5ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
              ),
              title: Text(
                islands[i].name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              subtitle: const Text(
                '3 bölüm',
                style: TextStyle(fontSize: 12, color: Color(0xFF658077)),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: forest),
              onTap: () => openIsland(i),
            ),
          ),
        ),
    ],
  );

  Widget _mapCanvas(bool reduced) => LayoutBuilder(
    key: const ValueKey('adventure-map-viewport'),
    builder: (context, constraints) {
      final height = constraints.maxWidth * 1.5;
      const positions = [
        Offset(.32, .79),
        Offset(.74, .60),
        Offset(.30, .43),
        Offset(.74, .27),
        Offset(.32, .13),
      ];
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            height: math.min(430.0, constraints.maxWidth * 1.08),
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final speed = details.primaryVelocity ?? 0;
                      if (speed.abs() < 150) return;
                      final next = (selected + (speed < 0 ? 1 : -1)).clamp(
                        0,
                        islands.length - 1,
                      );
                      if (next != selected) selectIsland(next);
                    },
                    child: SingleChildScrollView(
                      controller: mapController,
                      reverse: true,
                      physics: const BouncingScrollPhysics(),
                      child: SizedBox(
                        height: height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ExcludeSemantics(
                                child: Image.asset(
                                  'assets/home/adventure-archipelago-v2.png',
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                            for (var i = 0; i < positions.length; i++)
                              Positioned(
                                left:
                                    constraints.maxWidth * positions[i].dx - 27,
                                top: height * positions[i].dy - 27,
                                child: Semantics(
                                  label: '${i + 1}. ada, ${islands[i].name}',
                                  button: true,
                                  selected: selected == i,
                                  child: ExcludeSemantics(
                                    child: Tooltip(
                                      message: islands[i].name,
                                      child: AnimatedScale(
                                        scale: selected == i ? 1.08 : 1,
                                        duration: reduced
                                            ? Duration.zero
                                            : const Duration(milliseconds: 260),
                                        curve: Curves.easeOutBack,
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                            onTap: () => selectIsland(i),
                                            child: AnimatedContainer(
                                              duration: reduced
                                                  ? Duration.zero
                                                  : const Duration(
                                                      milliseconds: 220,
                                                    ),
                                              width: 54,
                                              height: 54,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: selected == i
                                                    ? const Color(0xFFFFDE88)
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                                border: Border.all(
                                                  color: selected == i
                                                      ? const Color(0xFFFFF0BC)
                                                      : const Color(0xFFF0F8EE),
                                                  width: 3,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                        (selected == i
                                                                ? const Color(
                                                                    0xFFB88930,
                                                                  )
                                                                : const Color(
                                                                    0xFF6E9A83,
                                                                  ))
                                                            .withValues(
                                                              alpha: .30,
                                                            ),
                                                    blurRadius: 0,
                                                    offset: const Offset(0, 5),
                                                  ),
                                                  const BoxShadow(
                                                    color: Color(0x15174234),
                                                    blurRadius: 16,
                                                    offset: Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: Text(
                                                '${i + 1}',
                                                style: const TextStyle(
                                                  fontSize: 21,
                                                  fontWeight: FontWeight.w900,
                                                  color: ink,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Önceki ada',
                        onPressed: selected == 0
                            ? null
                            : () => selectIsland(selected - 1),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: forest,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 22),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Sonraki ada',
                        onPressed: selected == islands.length - 1
                            ? null
                            : () => selectIsland(selected + 1),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: forest,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
