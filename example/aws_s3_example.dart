import 'dart:developer';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';

void main() async {
  Minio.init(
    endPoint: 's3.amazonaws.com',
    accessKey: '',
    secretKey: '',
    region: 'us-east-1',
  );

  final url = await Minio.shared.fPutObject('', 'test.png', 'example/custed.png');
  log('url: $url');
}
