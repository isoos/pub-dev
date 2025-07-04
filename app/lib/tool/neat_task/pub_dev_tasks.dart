// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:gcloud/service_scope.dart' as ss;
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:pub_dev/service/download_counts/computations.dart';

import '../../account/backend.dart';
import '../../account/consent_backend.dart';
import '../../admin/backend.dart';
import '../../audit/backend.dart';
import '../../package/api_export/api_exporter.dart';
import '../../package/backend.dart';
import '../../search/backend.dart';
import '../../service/download_counts/sync_download_counts.dart';
import '../../service/email/backend.dart';
import '../../service/security_advisories/sync_security_advisories.dart';
import '../../service/topics/count_topics.dart';
import '../../shared/configuration.dart';
import '../../shared/datastore.dart';
import '../../shared/integrity.dart';
import '../../task/backend.dart';
import '../../task/cloudcompute/googlecloudcompute.dart';
import '../../task/global_lock.dart';
import '../../tool/backfill/backfill_new_fields.dart';
import '../maintenance/remove_orphaned_likes.dart';
import '../maintenance/update_package_likes.dart';
import 'datastore_status_provider.dart';

final _logger = Logger('pub_dev_tasks');

/// Creates and initialized periodic task schedulers.
void setupPeriodTaskSchedulers() {
  for (final scheduler in createPeriodicTaskSchedulers()) {
    ss.registerScopeExitCallback(() => scheduler.stop());
    scheduler.start();
  }
}

/// List of periodic task schedulers.
List<NeatPeriodicTaskScheduler> createPeriodicTaskSchedulers({
  @visibleForTesting bool isPostTestVerification = false,
}) {
  return [
    // Tries to send pending outgoing emails.
    _15mins(
      name: 'send-outgoing-emails',
      isRuntimeVersioned: false,
      task: () async {
        final acquireAbort = Completer();
        final acquireTimer = Timer(Duration(minutes: 2), () {
          acquireAbort.complete();
        });

        try {
          final lock = GlobalLock.create(
            'send-outgoing-emails',
            expiration: Duration(minutes: 20),
          );
          await lock.withClaim(
            (claim) async {
              await emailBackend.trySendAllOutgoingEmails(
                stopAfter: Duration(minutes: 10),
              );
            },
            abort: acquireAbort,
          );
        } finally {
          acquireTimer.cancel();
        }
      },
    ),

    // Deletes outgoing email entries that had failed to deliver.
    _daily(
      name: 'delete-outgoing-emails',
      isRuntimeVersioned: false,
      task: emailBackend.deleteDeadOutgoingEmails,
    ),

    // Backfills the fields that are new to the current release.
    _daily(
      name: 'backfill-new-fields',
      isRuntimeVersioned: true,
      task: backfillNewFields,
    ),

    // Deletes expired audit log records.
    _daily(
      name: 'delete-expired-audit-log-records',
      isRuntimeVersioned: false,
      task: () async => await auditBackend.deleteExpiredRecords(),
    ),

    // Deletes expired consent invites.
    _daily(
      name: 'delete-expired-consents',
      isRuntimeVersioned: false,
      task: () async => await consentBackend.deleteObsoleteConsents(),
    ),

    // Deletes expired sessions.
    _daily(
      name: 'delete-expired-sessions',
      isRuntimeVersioned: false,
      task: () async => await accountBackend.deleteExpiredSessions(),
    ),

    // Updates Package's stable, prerelease and preview version fields in case a
    // new Dart SDK got released.
    _daily(
      name: 'update-package-versions',
      isRuntimeVersioned: false,
      task: () async => await packageBackend.updateAllPackageVersions(),
    ),

    // Updates the public archive bucket from the canonical bucket, for the
    // unlikely case where an archive may be missing.
    _daily(
      name: 'sync-public-bucket-from-canonical-bucket',
      isRuntimeVersioned: false,
      task: () async =>
          await packageBackend.tarballStorage.updatePublicArchiveBucket(),
    ),

    // Exports the package name completion data to a bucket.
    _daily(
      name: 'synchronize-exported-api',
      isRuntimeVersioned: true,
      task: () async => await apiExporter.synchronizeExportedApi(),
    ),

    // Deletes admin-deleted entities.
    _weekly(
      name: 'delete-admin-deleted-entities',
      isRuntimeVersioned: false,
      task: () async => adminBackend.deleteAdminDeletedEntities(),
    ),

    // Deletes moderated packages, versions, publishers and users.
    _weekly(
      name: 'delete-moderated-subjects',
      isRuntimeVersioned: false,
      task: () async => adminBackend.deleteModeratedSubjects(),
    ),

    // Deletes task status entities where the status hasn't been updated
    // for more than a month.
    _weekly(
      name: 'delete-old-neat-task-statuses',
      isRuntimeVersioned: false,
      task: () => deleteOldNeatTaskStatuses(dbService),
    ),

    // Deletes orphaned like entities that are missing a reference.
    _weekly(
      name: 'remove-orphaned-likes',
      isRuntimeVersioned: false,
      task: removeOrphanedLikes,
    ),

    // Updates Package.likes with the correct new value.
    _weekly(
      name: 'update-package-likes',
      isRuntimeVersioned: false,
      task: updatePackageLikes,
    ),

    // Updates PackageState in taskBackend
    _weekly(
      name: 'backfill-task-tracking-state',
      isRuntimeVersioned: true,
      task: taskBackend.backfillTrackingState,
    ),

    // Deletes task results for old runtime versions
    _weekly(
      name: 'garbage-collect-task-results',
      isRuntimeVersioned: false,
      task: taskBackend.garbageCollect,
    ),

    // Delete very old instances that have been abandoned
    //
    // NOTE: This task will use Google Cloud API to remove worker instances.
    //       The client is not configured for fake environment, we should skip
    //       this task in post-test verifications.
    // TODO: Write fake cloud abstractions to improve code coverage here.
    if (!isPostTestVerification)
      _daily(
        name: 'garbage-collect-old-instances',
        isRuntimeVersioned: false,
        task: () async => await deleteAbandonedInstances(
          project: activeConfiguration.taskWorkerProject!,
        ),
      ),

    // Syncs download counts from storage bucket.
    //
    // NOTE: This task reports missing files in the logs.
    // TODO: Provide fake download data so that the task does not fail here.
    if (!isPostTestVerification)
      _daily(
        name: 'sync-download-counts',
        isRuntimeVersioned: false,
        task: syncDownloadCounts,
      ),

    _daily(
      name: 'compute-download-counts-30-days-totals',
      isRuntimeVersioned: false,
      task: compute30DaysTotalTask,
    ),

    _daily(
      name: 'compute-trend-scores-v2',
      isRuntimeVersioned: false,
      task: computeTrendScoreTask,
    ),

    _daily(
      name: 'count-topics',
      isRuntimeVersioned: false,
      task: countTopics,
    ),

    // NOTE: This task will fetch the advisories from a public endpoint,
    //       running it on every test is not worth it.
    // TODO: Consider injecting a fake data source for unit test.
    if (!isPostTestVerification)
      _daily(
        name: 'sync-security-advisories',
        isRuntimeVersioned: false,
        task: syncSecurityAdvisories,
      ),

    // Checks the Datastore integrity of the model objects.
    _weekly(
      name: 'check-datastore-integrity',
      isRuntimeVersioned: true,
      task: () async => await IntegrityChecker(dbService, concurrency: 4)
          .verifyAndLogIssues(),
      timeout: Duration(days: 1),
    ),
    // Deletes the old search snapshots
    _weekly(
      name: 'delete-old-search-snapshots',
      isRuntimeVersioned: true,
      task: () => searchBackend.deleteOldData(),
    ),

    // TODO: setup tasks to remove known obsolete (but now unmapped) fields from entities
  ];
}

// ignore: non_constant_identifier_names
NeatPeriodicTaskScheduler _15mins({
  required String name,
  required bool isRuntimeVersioned,
  required NeatPeriodicTask task,
}) {
  return NeatPeriodicTaskScheduler(
    name: name,
    interval: Duration(minutes: 15),
    timeout: Duration(minutes: 10),
    status: DatastoreStatusProvider.create(dbService, name,
        isRuntimeVersioned: isRuntimeVersioned),
    task: _wrapMemoryLogging(name, task),
  );
}

NeatPeriodicTaskScheduler _daily({
  required String name,
  required bool isRuntimeVersioned,
  required NeatPeriodicTask task,
}) {
  return NeatPeriodicTaskScheduler(
    name: name,
    interval: Duration(hours: 24),
    timeout: Duration(hours: 12),
    status: DatastoreStatusProvider.create(dbService, name,
        isRuntimeVersioned: isRuntimeVersioned),
    task: _wrapMemoryLogging(name, task),
  );
}

NeatPeriodicTaskScheduler _weekly({
  required String name,
  required bool isRuntimeVersioned,
  required NeatPeriodicTask task,
  Duration timeout = const Duration(hours: 12),
}) {
  return NeatPeriodicTaskScheduler(
    name: name,
    interval: Duration(days: 6), // shifts the day when the task is triggered
    timeout: timeout,
    status: DatastoreStatusProvider.create(dbService, name,
        isRuntimeVersioned: isRuntimeVersioned),
    task: _wrapMemoryLogging(name, task),
  );
}

NeatPeriodicTask _wrapMemoryLogging(String name, NeatPeriodicTask task) {
  return () async {
    final startMaxRssInKiB = ProcessInfo.maxRss ~/ 1024;
    try {
      await task();
    } finally {
      final endMaxRssInKiB = ProcessInfo.maxRss ~/ 1024;
      final diffMaxRssInKiB = endMaxRssInKiB - startMaxRssInKiB;
      final message =
          'Periodic task $name completed with max memory use $endMaxRssInKiB ($diffMaxRssInKiB)';
      if (diffMaxRssInKiB > 10 * 1024) {
        // Take a notice, when the memory usage increased with more than 10 MB.
        // Let the log message stand out a bit, we should investigate, but no need to alert on it.
        _logger.info('[periodic-task-max-rss-warning] $message');
      } else {
        _logger.info(message);
      }
    }
  };
}
