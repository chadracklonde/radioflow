import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:radio_flow/app.dart';
import 'package:radio_flow/core/theme/app_theme.dart';
import 'package:radio_flow/features/auth/data/auth_repository.dart';
import 'package:radio_flow/shared/widgets/brand_mark.dart';

import 'widget_test.dart' as wt;

void main() {
  testWidgets('l’emblème est embarqué : PNG 384 px avec transparence', (
    tester,
  ) async {
    final data = await rootBundle.load(emblemAsset);
    expect(data.lengthInBytes, greaterThan(20 * 1024));
    final image = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    });
    expect(image!.width, 384);
    expect(image.height, 384);
    // Coin supérieur gauche : transparent (le détourage a bien retiré le fond d'origine).
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    expect(bytes.getUint8(3), 0, reason: 'alpha du pixel (0,0)');
    var opaque = 0;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 200) opaque++;
    }
    expect(
      opaque,
      greaterThan(384 * 384 * 0.04),
      reason: 'le tracé doit être visible',
    );
    expect(
      opaque,
      lessThan(384 * 384 * 0.35),
      reason: 'le fond ne doit pas être opaque',
    );
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets(
      'logo complet lisible en thème ${brightness.name}, un seul libellé accessible',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.dark
                : AppTheme.light,
            home: const Scaffold(body: Center(child: BrandLogo())),
          ),
        );
        await tester.pump();
        expect(find.text('RADIO'), findsOneWidget);
        expect(find.text('FLOW'), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        // Les lecteurs d'écran entendent « Radio Flow » une seule fois, pas « RADIO » puis « FLOW ».
        expect(find.bySemanticsLabel('Radio Flow'), findsOneWidget);
        expect(find.bySemanticsLabel('RADIO'), findsNothing);
        semantics.dispose();
      },
    );
  }

  testWidgets('le logo ne déborde pas à 2x la taille de texte sur 320 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: BrandLogo())),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('connexion : le logo est affiché', (tester) async {
    await initializeDateFormatting('fr');
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(wt.FakeAuth())],
        child: const RadioFlowApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
