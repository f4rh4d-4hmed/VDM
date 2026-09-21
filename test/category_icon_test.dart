import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virus_download_manager/core/enums.dart';
import 'package:virus_download_manager/ui/widgets/category_icon.dart';

void main() {
  group('CategoryIcon Widget Tests', () {
    testWidgets('renders SvgPicture for DownloadCategory.programs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategoryIcon(
              DownloadCategory.programs,
              size: 24,
              color: Colors.red,
            ),
          ),
        ),
      );

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);

      final svgWidget = tester.widget<SvgPicture>(svgFinder);
      expect(svgWidget.width, 24);
      expect(svgWidget.height, 24);
      expect(
        svgWidget.colorFilter,
        const ColorFilter.mode(Colors.red, BlendMode.srcIn),
      );
    });

    testWidgets('dynamically inherits ambient IconTheme for programs category', (tester) async {
      const themeColor = Color(0xFF1976D2);
      const themeSize = 32.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IconTheme(
              data: IconThemeData(
                color: themeColor,
                size: themeSize,
              ),
              child: CategoryIcon(DownloadCategory.programs),
            ),
          ),
        ),
      );

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);

      final svgWidget = tester.widget<SvgPicture>(svgFinder);
      expect(svgWidget.width, themeSize);
      expect(svgWidget.height, themeSize);
      expect(
        svgWidget.colorFilter,
        const ColorFilter.mode(themeColor, BlendMode.srcIn),
      );
    });

    testWidgets('renders Material Icon for other categories', (tester) async {
      const nonProgramCategories = [
        DownloadCategory.documents,
        DownloadCategory.images,
        DownloadCategory.videos,
        DownloadCategory.audio,
        DownloadCategory.compressed,
        DownloadCategory.other,
      ];

      for (final cat in nonProgramCategories) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CategoryIcon(
                cat,
                size: 20,
                color: Colors.blue,
              ),
            ),
          ),
        );

        expect(find.byType(Icon), findsOneWidget);
        expect(find.byType(SvgPicture), findsNothing);
      }
    });

    testWidgets('falls back to theme colorScheme.onSurface when IconTheme has no color', (tester) async {
      await tester.pumpWidget(
        Theme(
          data: ThemeData.light(),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: CategoryIcon(DownloadCategory.programs),
          ),
        ),
      );

      final svgFinder = find.byType(SvgPicture);
      expect(svgFinder, findsOneWidget);

      final svgWidget = tester.widget<SvgPicture>(svgFinder);
      expect(svgWidget.colorFilter, isNotNull);
    });
  });
}
