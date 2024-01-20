import 'dart:io';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';

void main() async {
  Minio.init(
    endPoint: 'play.min.io',
    accessKey: 'Q3AM3UQ867SPQQA43P2F',
    secretKey: 'zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG',
  );

  await Minio.shared.fPutObject('testbucket', 'test.png', 'example/custed.png');

  final stat = await Minio.shared.statObject('testbucket', 'test.png');
  assert(
    stat.size == File('example/custed.png').lengthSync(),
    'data size does not match',
  );
}
