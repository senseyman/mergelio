import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/net/proxy.dart';

final _https = Uri.parse('https://api.github.com/user');
final _http = Uri.parse('http://localhost:8080/appcast.json');

void main() {
  group('parseProxy', () {
    test('a bare host gets http and git\'s default port', () {
      final r = parseProxy('proxy.corp', 'http.proxy') as ProxyVia;
      expect(r.host, 'proxy.corp');
      expect(r.port, 1080);
      expect(r.setting, 'http.proxy');
    });

    test('an http url keeps its port and decoded credentials', () {
      final r = parseProxy(
        'http://me%40corp:p%3Ass@10.0.0.1:3128/',
        'HTTPS_PROXY',
      ) as ProxyVia;
      expect(r.host, '10.0.0.1');
      expect(r.port, 3128);
      expect(r.user, 'me@corp');
      expect(r.password, 'p:ss');
    });

    test('socks and https proxies are reported, not used', () {
      for (final raw in [
        'socks5://127.0.0.1:9050',
        'socks5h://h:1',
        'https://proxy.corp:443',
      ]) {
        final r = parseProxy(raw, 'http.proxy');
        expect(r, isA<ProxyUnsupported>(), reason: raw);
        expect((r as ProxyUnsupported).value, raw);
      }
    });

    test('something that is not a host is unsupported', () {
      expect(parseProxy('http://', 'http.proxy'), isA<ProxyUnsupported>());
      expect(parseProxy('http://h:notaport', 'x'), isA<ProxyUnsupported>());
    });
  });

  group('noProxyMatches', () {
    test('matches the host and its subdomains, not lookalikes', () {
      expect(noProxyMatches('github.com', 'github.com'), isTrue);
      expect(noProxyMatches('api.github.com', 'github.com'), isTrue);
      expect(noProxyMatches('api.github.com', '.github.com'), isTrue);
      expect(noProxyMatches('notgithub.com', 'github.com'), isFalse);
    });

    test('takes a comma list, ignores case, spaces and ports', () {
      expect(noProxyMatches('API.GitHub.com', 'x.org, github.com'), isTrue);
      expect(noProxyMatches('git.corp', 'git.corp:443'), isTrue);
      expect(noProxyMatches('a.b', ''), isFalse);
    });

    test('an IPv6 entry keeps its colons; a bracketed one drops its port', () {
      expect(noProxyMatches('::1', '::1'), isTrue);
      expect(noProxyMatches('::1', '[::1]:8080'), isTrue);
      expect(noProxyMatches('::2', '::1'), isFalse);
    });

    test('a lone star exempts everything', () {
      expect(noProxyMatches('anything.example', '*'), isTrue);
    });
  });

  group('ProxyPolicy.routeFor in automatic mode', () {
    test('nothing configured goes direct', () {
      expect(const ProxyPolicy().routeFor(_https), isA<ProxyDirect>());
    });

    test('git http.proxy wins over the environment', () {
      const p = ProxyPolicy(
        gitProxy: 'git.proxy:8080',
        env: {'HTTPS_PROXY': 'env.proxy:3128'},
      );
      final r = p.routeFor(_https) as ProxyVia;
      expect(r.host, 'git.proxy');
      expect(r.setting, 'http.proxy');
    });

    test('an empty http.proxy turns the proxy off', () {
      const p = ProxyPolicy(gitProxy: '', env: {'HTTPS_PROXY': 'env:1'});
      final r = p.routeFor(_https) as ProxyDirect;
      expect(r.setting, 'http.proxy');
    });

    test('https targets read https_proxy, lowercase first', () {
      const p = ProxyPolicy(
        env: {'HTTPS_PROXY': 'upper:1', 'https_proxy': 'lower:2'},
      );
      expect((p.routeFor(_https) as ProxyVia).setting, 'https_proxy');
      const upperOnly = ProxyPolicy(env: {'HTTPS_PROXY': 'upper:1'});
      expect((upperOnly.routeFor(_https) as ProxyVia).host, 'upper');
    });

    test('http targets read only lowercase http_proxy', () {
      const upper = ProxyPolicy(env: {'HTTP_PROXY': 'upper:1'});
      expect(upper.routeFor(_http), isA<ProxyDirect>());
      const lower = ProxyPolicy(env: {'http_proxy': 'lower:2'});
      expect((lower.routeFor(_http) as ProxyVia).host, 'lower');
    });

    test('all_proxy is the fallback for either scheme', () {
      const p = ProxyPolicy(env: {'ALL_PROXY': 'all:9'});
      expect((p.routeFor(_https) as ProxyVia).setting, 'ALL_PROXY');
      expect((p.routeFor(_http) as ProxyVia).host, 'all');
    });

    test('empty variables count as unset', () {
      const p = ProxyPolicy(env: {'https_proxy': '', 'HTTPS_PROXY': 'u:1'});
      expect((p.routeFor(_https) as ProxyVia).host, 'u');
    });

    test('no_proxy exempts a host from git and environment proxies', () {
      const p = ProxyPolicy(
        gitProxy: 'git.proxy:8080',
        env: {'NO_PROXY': 'github.com'},
      );
      final r = p.routeFor(_https) as ProxyDirect;
      expect(r.setting, 'NO_PROXY');
      expect(p.routeFor(Uri.parse('https://gitlab.com/api')), isA<ProxyVia>());
    });
  });

  group('ProxyPolicy.routeFor in other modes', () {
    test('off ignores everything configured', () {
      const p = ProxyPolicy(
        mode: ProxyMode.off,
        gitProxy: 'git.proxy:1',
        env: {'HTTPS_PROXY': 'env:1'},
      );
      expect(p.routeFor(_https), isA<ProxyDirect>());
    });

    test('manual uses the typed url and ignores git and environment', () {
      const p = ProxyPolicy(
        mode: ProxyMode.manual,
        manualUrl: ' http://typed:3128 ',
        gitProxy: 'git.proxy:1',
        env: {'HTTPS_PROXY': 'env:1', 'NO_PROXY': '*'},
      );
      final r = p.routeFor(_https) as ProxyVia;
      expect(r.host, 'typed');
      expect(r.setting, kManualProxySetting);
    });

    test('manual with nothing typed goes direct', () {
      const p = ProxyPolicy(mode: ProxyMode.manual);
      expect(p.routeFor(_https), isA<ProxyDirect>());
    });
  });

  group('ProxyPolicy.findProxy', () {
    test('writes the directive dart:io understands', () {
      expect(const ProxyPolicy().findProxy(_https), 'DIRECT');
      expect(
        const ProxyPolicy(gitProxy: 'http://u:p@h:3128').findProxy(_https),
        'PROXY u:p@h:3128',
      );
      expect(
        const ProxyPolicy(gitProxy: 'http://[::1]:3128').findProxy(_https),
        'PROXY [::1]:3128',
      );
    });

    test('a user without a password sends no credentials', () {
      expect(
        const ProxyPolicy(gitProxy: 'http://u@h:3128').findProxy(_https),
        'PROXY h:3128',
      );
    });

    test('credentials the directive cannot carry are left out', () {
      // dart:io splits the directive on ';' and the userinfo on the first
      // ':', and its parse error quotes the whole directive — password
      // included — into a message that ends up in the log.
      for (final raw in [
        'http://u:se%3Bcret@h:3128',
        'http://u%3Bx:secret@h:3128',
        'http://a%3Ab:secret@h:3128',
      ]) {
        expect(
          ProxyPolicy(gitProxy: raw).findProxy(_https),
          'PROXY h:3128',
          reason: raw,
        );
      }
    });

    test('an unsupported proxy goes direct rather than failing', () {
      expect(
        const ProxyPolicy(gitProxy: 'socks5://h:1').findProxy(_https),
        'DIRECT',
      );
    });
  });

  test('ProxyMode reads what settings store, defaulting to automatic', () {
    expect(ProxyMode.parse('manual'), ProxyMode.manual);
    expect(ProxyMode.parse('off'), ProxyMode.off);
    expect(ProxyMode.parse('auto'), ProxyMode.auto);
    expect(ProxyMode.parse('garbage'), ProxyMode.auto);
  });
}
