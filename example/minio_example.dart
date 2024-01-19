import 'dart:developer';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';

void main() async {
  final minio = Minio(
    endPoint: 'play.min.io',
    accessKey: 'Q3AM3UQ867SPQQA43P2F',
    secretKey: 'zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG',
    // enableTrace: true,
  );

  const bucket = '00test';
  const object = 'custed.png';
  const copy1 = 'custed.copy1.png';
  const copy2 = 'custed.copy2.png';

  if (!await minio.bucketExists(bucket)) {
    await minio.makeBucket(bucket);
    log('bucket $bucket created');
  } else {
    log('bucket $bucket already exists');
  }

  final poller = minio.listenBucketNotification(bucket, events: [
    's3:ObjectCreated:*',
  ],);
  poller.stream.listen((event) {
    log('--- event: ${event['eventName']}');
  });

  final region = await minio.getBucketRegion('00test');
  log('--- object region:');
  log(region);

  final etag = await minio.fPutObject(bucket, object, 'example/$object');
  log('--- etag:');
  log(etag);

  final url = await minio.presignedGetObject(bucket, object, expires: 1000);
  log('--- presigned url:');
  log(url);

  final copyResult1 = await minio.copyObject(bucket, copy1, '$bucket/$object');
  final copyResult2 = await minio.copyObject(bucket, copy2, '$bucket/$object');
  log('--- copy1 etag: ${copyResult1.eTag}');
  log('--- copy2 etag: ${copyResult2.eTag}');

  await minio.fGetObject(bucket, object, 'example/$copy1');
  log('--- copy1 downloaded');

  await minio.listObjects(bucket).forEach((chunk) {
    for (final o in chunk.objects) {
      log('--- objects: ${o.key}');
    }
  });

  await minio.listObjectsV2(bucket).forEach((chunk) {
    for (final o in chunk.objects) {
      log('--- objects(v2): ${o.key}');
    }
  });

  final stat = await minio.statObject(bucket, object);
  log('--- object stat: ${stat.etag}, ${stat.size}, ${stat.lastModified}, ${stat.metaData}');

  await minio.removeObject(bucket, object);
  log('--- object removed');

  await minio.removeObjects(bucket, [copy1, copy2]);
  log('--- copy1, copy2 removed');

  await minio.removeBucket(bucket);
  log('--- bucket removed');

  poller.stop();
}
