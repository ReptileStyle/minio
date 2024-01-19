import 'dart:developer';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 's3.amazonaws.com',
    accessKey: '',
    secretKey: '',
    region: 'us-east-1',
  );

  final url = await minio.fPutObject('homing-pigeon-dev', 'test.png', 'example/custed.png');

  log('url: $url');
}
