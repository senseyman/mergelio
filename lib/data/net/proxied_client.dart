import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../domain/net/proxy.dart';

/// An http client that routes every request the way [policy] says. The
/// default client only ever goes direct, which fails behind a proxy that
/// git itself gets through.
http.Client proxiedHttpClient(ProxyPolicy policy) =>
    IOClient(HttpClient()..findProxy = policy.findProxy);
