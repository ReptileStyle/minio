import 'package:convert/convert.dart';
import 'package:http/http.dart';
import 'package:mime/mime.dart' show lookupMimeType;
import 'package:minio/src/minio_client.dart';
import 'package:minio/src/minio_errors.dart';
import 'package:minio/src/minio_models_generated.dart';
import 'package:xml/xml.dart' as xml;

bool isValidBucketName(String bucket) {
  if (bucket.contains('/') || bucket.startsWith('arn:')) { // compatibility with typescript amazon s3 sdk
    return false;
  }

  return true;
}

bool isValidObjectName(String objectName) {
  if (!isValidPrefix(objectName)) return false;
  if (objectName.isEmpty) return false;
  return true;
}

bool isValidPrefix(String prefix) {
  if (prefix.length > 1024) return false;
  return true;
}

bool isAmazonEndpoint(String endpoint) {
  return endpoint == 's3.amazonaws.com' ||
      endpoint == 's3.cn-north-1.amazonaws.com.cn';
}

bool isVirtualHostStyle(String endpoint, bool useSSL, String? bucket) {
  if (bucket == null) {
    return false;
  }

  if (useSSL && bucket.contains('.')) {
    return false;
  }

  return isAmazonEndpoint(endpoint);
}

bool isValidEndpoint(String endpoint) {
  return isValidDomain(endpoint) || isValidIPv4(endpoint);
}

bool isValidIPv4(String? ip) {
  if (ip == null) return false;
  return RegExp(r'^(\d{1,3}\.){3}\d{1,3}$').hasMatch(ip);
}

bool isValidDomain(String? host) {
  if (host == null) return false;

  if (host.isEmpty || host.length > 255) {
    return false;
  }

  if (host.startsWith('-') || host.endsWith('-')) {
    return false;
  }

  if (host.startsWith('_') || host.endsWith('_')) {
    return false;
  }

  if (host.startsWith('.') || host.endsWith('.')) {
    return false;
  }

  final alphaNumerics = '`~!@#\$%^&*()+={}[]|\\"\';:><?/'.split('');
  for (final char in alphaNumerics) {
    if (host.contains(char)) return false;
  }

  return true;
}

bool isValidPort(int port) {
  if (port < 0) return false;
  if (port == 0) return true;
  const minPort = 1;
  const maxPort = 65535;
  return port >= minPort && port <= maxPort;
}

int implyPort(bool ssl) {
  return ssl ? 443 : 80;
}

String makeDateLong(DateTime date) {
  final isoDate = date.toIso8601String();

  // 'YYYYMMDDTHHmmss' + Z
  return '${isoDate.substring(0, 4)}${isoDate.substring(5, 7)}${isoDate.substring(8, 13)}${isoDate.substring(14, 16)}${isoDate.substring(17, 19)}Z';
}

String makeDateShort(DateTime date) {
  final isoDate = date.toIso8601String();

  // 'YYYYMMDD'
  return isoDate.substring(0, 4) +
      isoDate.substring(5, 7) +
      isoDate.substring(8, 10);
}

Map<String, String> prependXAMZMeta(Map<String, String?> metadata) {
  final newMetadata = Map<String, String>.from(metadata);
  for (final key in metadata.keys) {
    if (!isAmzHeader(key) &&
        !isSupportedHeader(key) &&
        !isStorageClassHeader(key)) {
      newMetadata['x-amz-meta-$key'] = newMetadata[key]!;
      newMetadata.remove(key);
    }
  }
  return newMetadata;
}

bool isAmzHeader(String input) {
  final key = input.toLowerCase();
  return key.startsWith('x-amz-meta-') ||
      key == 'x-amz-acl' ||
      key.startsWith('x-amz-server-side-encryption-') ||
      key == 'x-amz-server-side-encryption';
}

bool isSupportedHeader(String key) {
  final supportedHeaders = {
    'content-type',
    'cache-control',
    'content-encoding',
    'content-disposition',
    'content-language',
    'x-amz-website-redirect-location',
  };
  return supportedHeaders.contains(key.toLowerCase());
}

bool isStorageClassHeader(String key) {
  return key.toLowerCase() == 'x-amz-storage-class';
}

Map<String, String> extractMetadata(Map<String, String> metaData) {
  final newMetadata = <String, String>{};
  for (final key in metaData.keys) {
    if (isSupportedHeader(key) ||
        isStorageClassHeader(key) ||
        isAmzHeader(key)) {
      if (key.toLowerCase().startsWith('x-amz-meta-')) {
        newMetadata[key.substring(11, key.length)] = metaData[key]!;
      } else {
        newMetadata[key] = metaData[key]!;
      }
    }
  }
  return newMetadata;
}

String probeContentType(String path) {
  final contentType = lookupMimeType(path);
  return contentType ?? 'application/octet-stream';
}

Map<String, String> insertContentType(
  Map<String, String> metaData,
  String filePath,
) {
  for (final key in metaData.keys) {
    if (key.toLowerCase() == 'content-type') {
      return metaData;
    }
  }

  final newMetadata = Map<String, String>.from(metaData);
  newMetadata['content-type'] = probeContentType(filePath);
  return newMetadata;
}

Future<void> validateStreamed(
  StreamedResponse streamedResponse, {
  int? expect,
}) async {
  if (streamedResponse.statusCode >= 400) {
    final response = await MinioResponse.fromStream(streamedResponse);
    final body = xml.XmlDocument.parse(response.body);
    final error = Error.fromXml(body.rootElement);
    throw MinioS3Error(error.message, error, response);
  }

  if (expect != null && streamedResponse.statusCode != expect) {
    final response = await MinioResponse.fromStream(streamedResponse);
    throw MinioS3Error(
      '$expect expected, got ${streamedResponse.statusCode}',
      null,
      response,
    );
  }
}

void validate(MinioResponse response, {int? expect}) {
  if (response.statusCode >= 400) {
    Error error;

    // Parse HTTP response body as XML only when not empty
    if (response.body.isEmpty) {
      error = Error(response.reasonPhrase, null, response.reasonPhrase, null);
    } else {
      // check valid xml
      if (response.body.startsWith('<?xml')) {
        final body = xml.XmlDocument.parse(response.body);
        error = Error.fromXml(body.rootElement);
      } else {
        // not valid xml
        error = Error(response.reasonPhrase, null, response.reasonPhrase, null);
      }
    }

    throw MinioS3Error(error.message, error, response);
  }

  if (expect != null && response.statusCode != expect) {
    throw MinioS3Error(
      '$expect expected, got ${response.statusCode}',
      null,
      response,
    );
  }
}

final _a = 'a'.codeUnitAt(0);
final _A = 'A'.codeUnitAt(0);
final _z = 'z'.codeUnitAt(0);
final _Z = 'Z'.codeUnitAt(0);
final _0 = '0'.codeUnitAt(0);
final _9 = '9'.codeUnitAt(0);

final _pathIgnoredChars = {
  '%'.codeUnitAt(0),
  '-'.codeUnitAt(0),
  '_'.codeUnitAt(0),
  '.'.codeUnitAt(0),
  '~'.codeUnitAt(0),
  '/'.codeUnitAt(0),
};

/// encode [uri].path to HTML hex escape sequence
String encodePath(Uri uri) {
  final result = StringBuffer();
  for (final char in uri.path.codeUnits) {
    if (_A <= char && char <= _Z ||
        _a <= char && char <= _z ||
        _0 <= char && char <= _9) {
      result.writeCharCode(char);
      continue;
    }

    if (_pathIgnoredChars.contains(char)) {
      result.writeCharCode(char);
      continue;
    }

    result.write('%');
    result.write(hex.encode([char]).toUpperCase());
  }
  return result.toString();
}

/// encode [uri].path to HTML hex escape sequence
String encodeCanonicalQuery(String query) {
  return Uri.encodeQueryComponent(query).replaceAll('+', '%20');
}
