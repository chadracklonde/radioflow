import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Chemin de l'emblème détouré (voir tools/make_brand_assets.py).
const emblemAsset = 'assets/branding/logo_emblem.png';

/// Fond de la tuile : celui du logo d'origine, pour que l'emblème reste lisible dans les deux thèmes.
const _tileColor = Color(0xFF1A1D23);

/// Emblème de Radio Flow sur sa tuile sombre, comme l'icône de l'application.
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: _tileColor,
          borderRadius: BorderRadius.circular(
            size * 0.2237,
          ), // même arrondi que l'icône
        ),
        child: Image.asset(
          emblemAsset,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          // Si l'image manquait, l'interface reste utilisable.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Mot-symbole « RADIO FLOW » : RADIO dans la couleur du texte, FLOW en dégradé orange vers bleu.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.fontSize = 30});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Teintes du logo, ajustées pour rester lisibles (contraste) sur fond sombre comme sur fond clair.
    final stops = dark
        ? const [Color(0xFFFF8A1F), Color(0xFF1E90FF), Color(0xFF60A5FA)]
        : const [Color(0xFFC2410C), Color(0xFF1D4ED8), Color(0xFF1E40AF)];
    final base = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      height: 1.1,
    );

    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'RADIO',
            style: base.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: Space.sm),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) =>
                LinearGradient(colors: stops).createShader(bounds),
            child: Text(
              'FLOW',
              style: base.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo complet : emblème au-dessus du mot-symbole. Un seul libellé pour les lecteurs d'écran.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.emblemSize = 112, this.wordmarkSize = 30});

  final double emblemSize;
  final double wordmarkSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Radio Flow',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandEmblem(size: emblemSize),
          const SizedBox(height: Space.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: BrandWordmark(fontSize: wordmarkSize),
          ),
        ],
      ),
    );
  }
}
