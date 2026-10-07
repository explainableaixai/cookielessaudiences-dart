# cookielessaudiences for Dart and Flutter

Ask for the audience behind a web page and get it back as a Dart map. The service never uses cookies or personal data; it reads the page and answers from fixed vocabularies.

Runs on the Dart VM, in server apps and in Flutter backends. Do not ship your key inside a mobile app.

## pubspec

```yaml
dependencies:
  cookielessaudiences: ^1.0.0
```

```bash
dart pub get
```

## Example

```dart
import 'package:cookielessaudiences/cookielessaudiences.dart';

Future<void> main() async {
  final client = CookielessAudiences(const String.fromEnvironment('COOKIELESS_KEY'));
  final page = await client.segment('https://example.com/blog');

  print(page['audience_type']);
  print(CookielessAudiences.labelsFor(page));
  client.close();
}
```

## Everything the class does

| Member | Notes |
|---|---|
| `CookielessAudiences(key, {client, timeout})` | pass your own `http.Client` for tests or proxies |
| `segment(url, {structured: true})` | the coded v2 profile |
| `categorize(url, {confidence, rootFallback})` | IAB categories for a URL |
| `categorizeText(text)` | IAB categories for text |
| `vocabularies()` | static, no key needed |
| `labelsFor(map)` | static, codes to readable names |
| `CookielessAudiencesException` | `status`, `message`, `body` |

## Planning around personas

Media buyers often start from a persona and look for sites. Use `segment` to see which personas a site carries, then keep the ones that match.

```dart
final wanted = {'Data Scientist', 'Software Developer'};
final persona = (page['personas'] as List).cast<Map>();
final hits = persona.where((p) => wanted.contains(p['persona'])).toList();
print('${hits.length} matching personas');
```

That is the building block of [media planning by persona](https://www.cookielessaudiences.com/use-cases/media-planning-by-persona.php): a list of sites in, a shortlist of fits out.

## Dealing with failures

```dart
try {
  final page = await client.segment(url);
} on CookielessAudiencesException catch (e) {
  switch (e.status) {
    case 401:
      print('Check the key');
    case 403:
      print('Inactive key or no credits left');
    case 410 || 411:
      print('Page unreadable, skip it');
    default:
      print(e);
  }
}
```

## Testing without the network

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final mock = MockClient((req) async => http.Response('{"status":200,"audience_type":"consumer"}', 200));
final client = CookielessAudiences('test', client: mock);
```

The constructor accepts any `http.Client`, so unit tests stay offline.

## Parallel work with plain futures

```dart
final urls = ['https://a.example', 'https://b.example'];
final pages = await Future.wait(urls.map((u) => client.segment(u).catchError((_) => <String, dynamic>{})));
```

Keep the batch size modest and chunk long lists.

## Other ways to use the data

The same profile feeds [audience personas for advertising](https://www.cookielessaudiences.com/features/audience-personas-advertising.php) work and anywhere you need a readable audience description for a domain.

## Common questions

**Can Flutter web call this directly?** Possible, but the key would be visible to every visitor. Proxy through your server.

**Do the allowed values drift?** Vocabularies are versioned, and every response reports its `vocab_version`.

**What sizes does the key support?** See the plans on the pricing page of the site.

MIT license. Contact info@alpha-quantum.com.
