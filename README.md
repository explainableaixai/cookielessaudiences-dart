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

<!--expanded-->
## Why a Dart client exists

Dart runs more places than people expect. It powers Flutter apps, command line tools, small servers and build scripts. A team that already owns a Flutter product often wants an internal dashboard in the same language, and an internal dashboard for media planning needs audience data. This package is the thinnest possible bridge between those two facts: one class, one dependency on `package:http`, and results as ordinary maps.

The package does not hide the shape of the service. Every method corresponds to one endpoint, every error corresponds to a status in the body, and every field in the answer is a key you can read in the [API reference](https://www.cookielessaudiences.com/api.php). Nothing is renamed, and nothing is flattened for you. When the service adds a field, your code can read it the day it appears.

## A planning dashboard in Flutter

Imagine a media planner who pastes a list of domains and wants to see, at a glance, which of them reach upper middle income professionals. The data flow is short:

1. A server function calls `segment` for each domain.
2. The server stores the answer.
3. The Flutter app reads from the server and renders a table.

Keep the API key on the server. A key shipped inside an app bundle can be extracted by anyone with a few minutes and a proxy. A tiny `shelf` server is enough:

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:cookielessaudiences/cookielessaudiences.dart';

final client = CookielessAudiences(const String.fromEnvironment('COOKIELESS_KEY'));

Future<Response> handle(Request req) async {
  final url = req.url.queryParameters['url'];
  if (url == null) return Response(400, body: 'url required');
  try {
    final page = await client.segment(url);
    return Response.ok(jsonEncode({
      'type': page['audience_type'],
      'income': (page['demographics'] as Map?)?['income_level'],
      'labels': CookielessAudiences.labelsFor(page),
    }), headers: {'content-type': 'application/json'});
  } on CookielessAudiencesException catch (e) {
    return Response(502, body: jsonEncode({'status': e.status, 'message': e.message}));
  }
}

Future<void> main() => io.serve(handle, 'localhost', 8080);
```

The Flutter side then calls your own endpoint and never sees the key.

## Reading the answer safely

Dart's type system rewards you for being explicit about what might be missing. A block without evidence is absent or empty, and you should model that:

```dart
List<String> ageBrackets(Map<String, dynamic> page) {
  final demo = page['demographics'];
  if (demo is! Map) return const [];
  final list = demo['age_bracket'];
  return list is List ? list.whereType<String>().toList() : const [];
}

bool isBusinessPage(Map<String, dynamic> page) => page['audience_type'] == 'b2b';
```

Write small accessors like these once and reuse them. They turn a loosely typed map into something your widgets can trust, and they give you one place to adapt if the vocabulary grows.

Confidence bands matter in a user interface too. Show a high confidence income band as a plain label. Show a low confidence one with a lighter style or a question mark. Planners learn quickly to read that visual language, and it keeps them from over trusting a weak answer.

## Offline friendly caching

A planner will reopen the same domain list several times in a week. Cache answers locally on the server with a simple map keyed by normalized URL, and include the date. In a small tool, a JSON file is enough. In a larger one, use SQLite.

Keep the vocabulary version next to each cached answer. If it changes, mark older entries as stale and refresh the ones that people actually open. You do not need to refresh everything at once, because pages change slowly.

## Batch processing in an isolate

Large batches can block a UI thread if you run them in the wrong place. In a Flutter desktop tool, push the loop into an isolate:

```dart
import 'dart:isolate';

Future<List<Map<String, dynamic>>> segmentBatch(List<String> urls, String key) {
  return Isolate.run(() async {
    final client = CookielessAudiences(key);
    final out = <Map<String, dynamic>>[];
    for (final url in urls) {
      try {
        out.add({'url': url, ...await client.segment(url)});
      } on CookielessAudiencesException catch (e) {
        out.add({'url': url, 'error': e.status});
      }
    }
    client.close();
    return out;
  });
}
```

Run a small number of futures at once inside the isolate. The service accepts up to 50 parallel threads by default, and a polite client stays well below that.

## Connecting audience data to other jobs

Audience profiles are a shared language between teams. A privacy team can read the fact that no cookies or user identifiers are involved. A planning team can read the personas. A data team can join the codes onto a warehouse table. The [guide to cookieless targeting](https://www.cookielessaudiences.com/features/cookieless-targeting.php) explains how those pieces fit together in a campaign.

If your company also deals with hiring data, the page on [blind screening of CVs](https://www.resumereaderapi.com/use-cases/cv-anonymization.php) describes how a single flag removes identifiers from a parsed resume, which is the same privacy first idea applied to candidates. If you evaluate other companies for acquisition, the description of the [120M domain classification engine](https://www.acquisitionuniverse.com/the-data-engine.php) shows how a classified universe of domains supports target screening.

## Troubleshooting

**`CookielessAudiencesException(403)`.** The key is inactive or the credits are used up.

**`CookielessAudiencesException(410)`.** The page had too little readable content. Skip it or try the root domain.

**`FormatException` while decoding.** The server returned something that was not JSON, usually because of a network proxy. Check the response in a debugger.

**Timeouts.** The default is 120 seconds. Raise it for slow pages, and lower concurrency if many calls time out together.

**Unexpected labels.** Check `vocab_version` in the response and compare with the vocabulary you fetched.

## Package facts

The package targets Dart 3 and uses records and pattern matching in the examples. It depends only on `package:http`. It does not store state, open sockets of its own or read environment variables, so it is easy to test and easy to reason about.

## Habits that keep a dashboard honest

A dashboard that shows audience data carries an implicit promise: these numbers describe real readers. Keep that promise by showing where each value came from. Display the vocabulary version in a footer, show the confidence band beside every figure, and let a planner click through to the page that was analysed. When a value is missing, say so, instead of showing a zero. A blank is honest, and a zero looks like a measurement.

Also think about how planners will export. A CSV with one row per domain and one column per attribute is the format they will ask for first. Provide it early, include the vocabulary version as a column, and the file will stay useful long after the screen has changed.

<!--further-->
## Further reading

The [Dart language site](https://dart.dev/) has the documentation for records, patterns, isolates and null safety that the examples above use, and it is the best place to check details of `package:http` behaviour on each platform.

## Common questions

**Can Flutter web call this directly?** Possible, but the key would be visible to every visitor. Proxy through your server.

**Do the allowed values drift?** Vocabularies are versioned, and every response reports its `vocab_version`.

**What sizes does the key support?** See the plans on the pricing page of the site.

MIT license. Contact info@alpha-quantum.com.
