import 'package:down_any_media/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the downloader UI', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DownAnyMediaApp());
    await tester.pump(const Duration(milliseconds: 300));

    // Post-redesign home screen: URL field on top, disclaimer moved to the
    // About dialog, engine/folder settings collapsed into an expander, and the
    // Cancel button only appears while a download is running.
    expect(find.text('DownAnyMedia'), findsOneWidget);
    expect(find.text('Engine & download settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('urlInput')), findsOneWidget);
    expect(find.byKey(const ValueKey('pasteButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('downloadButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('cancelButton')), findsNothing);
    expect(find.text('Download History'), findsOneWidget);
  });
}
