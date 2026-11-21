import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Inert, isolated APK target. Never imports provider or scheduling startup.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  const fixture = BasicMessageChannel<Object?>(
    'app.wardpulse/widget_publication_fixture',
    StandardMessageCodec(),
  );
  const publication = MethodChannel('app.wardpulse/widget_publication');
  fixture.setMessageHandler((message) async {
    final request = Map<Object?, Object?>.from(message! as Map);
    final saved = await publication.invokeMethod<bool>(
      'publish',
      request['publication'],
    );
    if (saved != true) {
      throw StateError('Fixture publication failed.');
    }
    return <String, Object?>{'id': request['id'], 'saved': saved};
  });
  if (!args.contains('headless')) {
    runApp(const SizedBox.shrink());
  }
}
