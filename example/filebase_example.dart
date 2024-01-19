import 'dart:developer';

import 'package:minio/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 's3.filebase.com',
    accessKey: '<YOUR_ACCESS_KEY>',
    secretKey: '<YOUR_SECRET_KEY>',
  );

  final buckets = await minio.listBuckets();
  log('buckets: $buckets');

  final objects = await minio.listObjects(buckets.first.name).toList();
  log('objects: $objects');
}
