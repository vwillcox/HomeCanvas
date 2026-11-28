import 'package:dio/dio.dart';

/// What the panel calls itself to the services that ask every client to say
/// who it is.
const String homeCanvasAgent = 'HomeCanvas/1.0 (home dashboard panel)';

/// A server's address as typed, with no spaces round it or slash after it,
/// ready for a path to be put on the end.
String trimAddress(String url) => url.trim().replaceAll(RegExp(r'/+$'), '');

/// An HTTP client with the panel's usual patience: ten seconds to connect,
/// fifteen for the answer. Given otherwise where a service is on the house's
/// own network and should answer at once, or is known to be slow.
Dio httpClient({
  Duration connect = const Duration(seconds: 10),
  Duration receive = const Duration(seconds: 15),
  String baseUrl = '',
  Map<String, Object?>? headers,
  ResponseType responseType = ResponseType.json,
  ValidateStatus? validateStatus,
  bool? followRedirects,
}) => Dio(
  BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: connect,
    receiveTimeout: receive,
    headers: headers,
    responseType: responseType,
    validateStatus: validateStatus,
    followRedirects: followRedirects,
  ),
);
