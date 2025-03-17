// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:_pub_shared/data/admin_api.dart';
import 'package:_pub_shared/data/package_api.dart';
import 'package:gcloud/storage.dart';
import 'package:googleapis/storage/v1.dart' show DetailedApiRequestError;
import 'package:logging/logging.dart';
import 'package:pub_dev/fake/backend/fake_auth_provider.dart';
import 'package:pub_dev/package/api_export/api_exporter.dart';
import 'package:pub_dev/shared/datastore.dart';
import 'package:pub_dev/shared/storage.dart';
import 'package:pub_dev/shared/utils.dart';
import 'package:pub_dev/shared/versions.dart';
import 'package:pub_dev/tool/test_profile/importer.dart';
import 'package:pub_dev/tool/test_profile/models.dart';
import 'package:test/test.dart';

import '../../shared/test_models.dart';
import '../../shared/test_services.dart';
import '../../task/fake_time.dart';

final _log = Logger('api_export.test');

final _testProfile = TestProfile(
  defaultUser: userAtPubDevEmail,
  generatedPackages: [
    GeneratedTestPackage(
      name: 'foo',
      versions: [
        GeneratedTestVersion(version: '1.0.0'),
      ],
    ),
  ],
  users: [
    TestUser(email: userAtPubDevEmail, likes: []),
  ],
);

void main() {
  testWithFakeTime('synchronizeExportedApi()',
      testProfile: _testProfile,
      expectedLogMessages: [
        'SHOUT Deleting object from public bucket: "packages/bar-2.0.0.tar.gz".',
        'SHOUT Deleting object from public bucket: "packages/bar-3.0.0.tar.gz".',
      ], (fakeTime) async {
    await storageService.createBucket('bucket');
    final bucket = storageService.bucket('bucket');
    final apiExporter =
        ApiExporter(dbService, storageService: storageService, bucket: bucket);

    await _testExportedApiSynchronization(
      fakeTime,
      bucket,
      apiExporter.synchronizeExportedApi,
    );
  });

  testWithFakeTime(
    'apiExporter.start()',
    expectedLogMessages: [
      'SHOUT Deleting object from public bucket: "packages/bar-2.0.0.tar.gz".',
      'SHOUT Deleting object from public bucket: "packages/bar-3.0.0.tar.gz".',
    ],
    testProfile: _testProfile,
    (fakeTime) async {
      await storageService.createBucket('bucket');
      final bucket = storageService.bucket('bucket');
      final apiExporter = ApiExporter(dbService,
          storageService: storageService, bucket: bucket);

      await apiExporter.synchronizeExportedApi();

      await apiExporter.start();

      await _testExportedApiSynchronization(
        fakeTime,
        bucket,
        () async => await fakeTime.elapse(minutes: 15),
      );

      await apiExporter.stop();
    },
  );
}

Future<void> _testExportedApiSynchronization(
  FakeTime fakeTime,
  Bucket bucket,
  Future<void> Function() synchronize,
) async {
  _log.info('## Existing package');
  {
    await synchronize();

    // Check that exsting package was synchronized
    expect(
      await bucket.readGzippedJson('latest/api/packages/foo'),
      {
        'name': 'foo',
        'latest': isNotEmpty,
        'versions': hasLength(1),
      },
    );
    expect(
      await bucket.readGzippedJson('latest/api/package-name-completion-data'),
      {'packages': hasLength(1)},
    );
    expect(
      await bucket.readBytes('$runtimeVersion/api/archives/foo-1.0.0.tar.gz'),
      isNotNull,
    );
    expect(
      await bucket.readGzippedJson('$runtimeVersion/api/packages/foo'),
      {
        'name': 'foo',
        'latest': isNotEmpty,
        'versions': hasLength(1),
      },
    );
    expect(
      await bucket
          .readGzippedJson('$runtimeVersion/api/package-name-completion-data'),
      {'packages': hasLength(1)},
    );
    expect(
      await bucket.readBytes('$runtimeVersion/api/archives/foo-1.0.0.tar.gz'),
      isNotNull,
    );
  }

  _log.info('## New package');
  {
    await importProfile(
      profile: TestProfile(
        defaultUser: userAtPubDevEmail,
        generatedPackages: [
          GeneratedTestPackage(
            name: 'bar',
            versions: [GeneratedTestVersion(version: '2.0.0')],
            publisher: 'example.com',
          ),
        ],
      ),
    );

    // Synchronize again
    await synchronize();

    // Check that exsting package is still there
    expect(
      await bucket.readGzippedJson('latest/api/packages/foo'),
      isNotNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/foo-1.0.0.tar.gz'),
      isNotNull,
    );
    // Note. that name completion data won't be updated until search caches
    //       are purged, so we won't test that it is updated.

    // Check that new package was synchronized
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(1),
      },
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNotNull,
    );
  }

  _log.info('## New package version');
  {
    await importProfile(
      profile: TestProfile(
        defaultUser: userAtPubDevEmail,
        generatedPackages: [
          GeneratedTestPackage(
            name: 'bar',
            versions: [GeneratedTestVersion(version: '3.0.0')],
            publisher: 'example.com',
          ),
        ],
      ),
    );

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(2),
      },
    );
    // Check that versions are there
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNotNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-3.0.0.tar.gz'),
      isNotNull,
    );
  }

  _log.info('## Discontinued flipped on');
  {
    final api = await createFakeAuthPubApiClient(email: userAtPubDevEmail);
    await api.setPackageOptions(
      'bar',
      PkgOptions(isDiscontinued: true),
    );

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(2),
        'isDiscontinued': true,
      },
    );
  }

  _log.info('## Discontinued flipped off');
  {
    final api = await createFakeAuthPubApiClient(email: userAtPubDevEmail);
    await api.setPackageOptions(
      'bar',
      PkgOptions(isDiscontinued: false),
    );

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(2),
      },
    );
  }

  _log.info('## Version retracted');
  {
    final api = await createFakeAuthPubApiClient(email: userAtPubDevEmail);
    await api.setVersionOptions(
      'bar',
      '2.0.0',
      VersionOptions(isRetracted: true),
    );

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': contains(containsPair('retracted', true))
      },
    );
  }

  _log.info('## Version moderated');
  {
    // Elapse time before moderating package, because exported-api won't delete
    // recently created files as a guard against race conditions.
    fakeTime.elapseSync(days: 1);

    await withRetryPubApiClient(
      authToken: createFakeServiceAccountToken(email: 'admin@pub.dev'),
      (adminApi) async {
        await adminApi.adminInvokeAction(
          'moderate-package-version',
          AdminInvokeActionArguments(arguments: {
            'case': 'none',
            'package': 'bar',
            'version': '2.0.0',
            'state': 'true',
          }),
        );
      },
    );

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(1),
      },
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-3.0.0.tar.gz'),
      isNotNull,
    );
  }

  _log.info('## Version reinstated');
  {
    await withRetryPubApiClient(
        authToken: createFakeServiceAccountToken(email: 'admin@pub.dev'),
        (adminApi) async {
      await adminApi.adminInvokeAction(
        'moderate-package-version',
        AdminInvokeActionArguments(arguments: {
          'case': 'none',
          'package': 'bar',
          'version': '2.0.0',
          'state': 'false',
        }),
      );
    });

    // Synchronize again
    await synchronize();

    // Check that version listing was updated
    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(2),
      },
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNotNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-3.0.0.tar.gz'),
      isNotNull,
    );
  }

  _log.info('## Package moderated');
  {
    // Elapse time before moderating package, because exported-api won't delete
    // recently created files as a guard against race conditions.
    fakeTime.elapseSync(days: 1);

    await withRetryPubApiClient(
        authToken: createFakeServiceAccountToken(email: 'admin@pub.dev'),
        (adminApi) async {
      await adminApi.adminInvokeAction(
        'moderate-package',
        AdminInvokeActionArguments(arguments: {
          'case': 'none',
          'package': 'bar',
          'state': 'true',
        }),
      );
    });

    // Synchronize again
    await synchronize();

    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      isNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-3.0.0.tar.gz'),
      isNull,
    );
  }

  _log.info('## Package reinstated');
  {
    await withRetryPubApiClient(
        authToken: createFakeServiceAccountToken(email: 'admin@pub.dev'),
        (adminApi) async {
      await adminApi.adminInvokeAction(
        'moderate-package',
        AdminInvokeActionArguments(arguments: {
          'case': 'none',
          'package': 'bar',
          'state': 'false',
        }),
      );
    });

    // Synchronize again
    await synchronize();

    expect(
      await bucket.readGzippedJson('latest/api/packages/bar'),
      {
        'name': 'bar',
        'latest': isNotEmpty,
        'versions': hasLength(2),
      },
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-2.0.0.tar.gz'),
      isNotNull,
    );
    expect(
      await bucket.readBytes('latest/api/archives/bar-3.0.0.tar.gz'),
      isNotNull,
    );
  }
}

extension on Bucket {
  /// Read bytes from bucket, retur null if missing
  Future<Uint8List?> readBytes(String path) async {
    try {
      return await readAsBytes(path);
    } on DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Read gzipped JSON from bucket
  Future<Object?> readGzippedJson(String path) async {
    final bytes = await readBytes(path);
    if (bytes == null) {
      return null;
    }
    return utf8JsonDecoder.convert(gzip.decode(bytes));
  }
}
