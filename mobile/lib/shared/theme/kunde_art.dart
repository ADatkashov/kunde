import 'package:flutter/material.dart';

/// Bundled Fluent Emoji illustrations (Microsoft, MIT). No network requests.
class KundeIllustration extends StatelessWidget {
  const KundeIllustration(this.name, {this.size = 48, super.key});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Image.asset('assets/illustrations/$name.png',
            width: size, height: size, fit: BoxFit.contain),
      );
}

String? illustrationForEmoji(String emoji) => switch (emoji) {
      '🍔' => 'burger',
      '🍕' => 'pizza',
      '☕' => 'coffee',
      '🍜' || '🥗' || '🍲' || '🥘' || '🍣' => 'food',
      '🛒' || '🥦' || '🥬' || '🥕' || '🍎' || '🥑' => 'grocery',
      _ => null,
    };

/// Original vector artwork: the snowy mountain silhouette of the Almaty header.
class AlmatyMountains extends CustomPainter {
  const AlmatyMountains();

  @override
  void paint(Canvas canvas, Size size) {
    final far = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * .8)
      ..lineTo(size.width * .24, size.height * .36)
      ..lineTo(size.width * .34, size.height * .55)
      ..lineTo(size.width * .55, size.height * .12)
      ..lineTo(size.width * .7, size.height * .45)
      ..lineTo(size.width * .83, size.height * .22)
      ..lineTo(size.width, size.height * .54)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFBDDCED));
    final snow = Path()
      ..moveTo(size.width * .4, size.height * .43)
      ..lineTo(size.width * .55, size.height * .12)
      ..lineTo(size.width * .67, size.height * .39)
      ..lineTo(size.width * .56, size.height * .30)
      ..lineTo(size.width * .51, size.height * .39)
      ..lineTo(size.width * .49, size.height * .32)
      ..close();
    canvas.drawPath(snow, Paint()..color = Colors.white);
    final near = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width * .25, size.height * .51, size.width * .45,
          size.height * .8)
      ..quadraticBezierTo(
          size.width * .72, size.height * .38, size.width, size.height * .75)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFFA8D6C1));
  }

  @override
  bool shouldRepaint(AlmatyMountains oldDelegate) => false;
}

/// Original geometric K mark, drawn at device resolution.
class KundeLogoPainter extends CustomPainter {
  const KundeLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF62DA8D), Color(0xFF00875A), Color(0xFF005436)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width * .27, size.height),
            Radius.circular(size.width * .12)),
        paint);
    final top = Path()
      ..moveTo(size.width * .32, size.height * .45)
      ..lineTo(size.width * .68, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * .60, size.height * .49)
      ..close();
    final bottom = Path()
      ..moveTo(size.width * .32, size.height * .55)
      ..lineTo(size.width * .60, size.height * .51)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * .68, size.height)
      ..close();
    canvas.drawPath(top, paint);
    canvas.drawPath(bottom, paint);
  }

  @override
  bool shouldRepaint(KundeLogoPainter oldDelegate) => false;
}
