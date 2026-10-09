// translateServerMessage: the backend's error `detail` strings, in the app's
// language. Fixed messages are looked up whole (lowercased, as ApiClient hands
// them over); ones with a name or number in them are matched by pattern; and an
// unknown message must come back untouched rather than blank or mangled.
import 'package:flutter_test/flutter_test.dart';
import 'package:teamira/services/locale_service.dart';
import 'package:teamira/services/server_messages.dart';

void main() {
  tearDown(() => LocaleService.contentPrefersRussian = false);

  group('English interface', () {
    setUp(() => LocaleService.contentPrefersRussian = false);

    test('a Russian server message is translated', () {
      expect(translateServerMessage('просмотр уже закончился'), 'the viewing has already ended');
      expect(translateServerMessage('промокод не найден'), 'promo code not found');
    });

    test('a message already in English is left alone', () {
      expect(translateServerMessage('username already taken'), 'username already taken');
    });

    test('patterns carry the number or name through', () {
      expect(translateServerMessage('слишком длинно — не больше 200 символов'),
          'too long — no more than 200 characters');
      expect(translateServerMessage('сейчас читает вслух маша'), 'маша is reading aloud right now');
    });

    test('an unknown message comes back untouched', () {
      expect(translateServerMessage('что-то совсем новое'), 'что-то совсем новое');
      expect(translateServerMessage(''), '');
    });
  });

  group('Russian interface', () {
    setUp(() => LocaleService.contentPrefersRussian = true);

    test('an English server message is translated', () {
      expect(translateServerMessage('username already taken'), 'это имя пользователя уже занято');
      expect(translateServerMessage('invalid username or password'), 'неверное имя пользователя или пароль');
    });

    test('a message already in Russian is left alone', () {
      expect(translateServerMessage('комната не найдена'), 'комната не найдена');
    });

    test('patterns carry the name through', () {
      expect(translateServerMessage('anna is already in your circle'), 'anna уже в вашем круге');
      expect(translateServerMessage('pin at most 3 badges'), 'можно закрепить не больше 3 значков');
    });

    test('an unknown message comes back untouched', () {
      expect(translateServerMessage('something brand new'), 'something brand new');
    });
  });
}
