// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:_pub_shared/data/account_api.dart' as account_api;
import 'package:_pub_shared/data/admin_api.dart';
import 'package:api_builder/_client_utils.dart';
import 'package:pub_dev/account/backend.dart';
import 'package:pub_dev/account/consent_backend.dart';
import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/audit/backend.dart';
import 'package:pub_dev/audit/models.dart';
import 'package:pub_dev/fake/backend/fake_auth_provider.dart';
import 'package:pub_dev/fake/backend/fake_email_sender.dart';
import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/publisher/backend.dart';
import 'package:pub_dev/shared/datastore.dart';
import 'package:test/test.dart';

import '../shared/test_models.dart';
import '../shared/test_services.dart';

void main() {
  group('Admin API: tool', () {
    group('bad tool', () {
      setupTestsWithAdminTokenIssues(
          (client) => client.adminExecuteTool('no-such-tool', ''));

      testWithProfile('auth with bad tool', fn: () async {
        final rs = await createPubApiClient(authToken: siteAdminToken)
            .adminExecuteTool('no-such-tool', '');
        final bodyText = utf8.decode(rs);
        expect(bodyText, contains('Available admin tools:'));
      });
    });

    group('user merger', () {
      setupTestsWithAdminTokenIssues(
          (client) => client.adminExecuteTool('user-merger', ''));

      testWithProfile('help', fn: () async {
        final rs = await createPubApiClient(authToken: siteAdminToken)
            .adminExecuteTool('user-merger', '--help');
        final bodyText = utf8.decode(rs);
        expect(bodyText, contains('Usage:'));
      });

      testWithProfile('merge all, but no problems detected', fn: () async {
        final rs = await createPubApiClient(authToken: siteAdminToken)
            .adminExecuteTool('user-merger', '');
        final bodyText = utf8.decode(rs);
        expect(bodyText, 'Fixed 0 `User` entities.');
      });

      testWithProfile('merge two user ids', fn: () async {
        final admin = await accountBackend.lookupUserByEmail('admin@pub.dev');
        final user = await accountBackend.lookupUserByEmail('user@pub.dev');
        final rs = await createPubApiClient(authToken: siteAdminToken)
            .adminExecuteTool(
                'user-merger',
                Uri(pathSegments: [
                  '--from-user-id',
                  admin.userId,
                  '--to-user-id',
                  user.userId,
                ]).toString());
        final bodyText = utf8.decode(rs);
        expect(bodyText, 'Merged `${admin.userId}` into `${user.userId}`.');

        final p = await packageBackend.lookupPackage('oxygen');
        expect(p!.uploaders, [user.userId]);
      });
    });

    group('publisher member invite', () {
      setupTestsWithAdminTokenIssues((client) => client.adminInvokeAction(
          'publisher-member-invite',
          AdminInvokeActionArguments(arguments: {
            'publisher': 'example.com',
            'email': 'member@example.com'
          })));

      testWithProfile('invite + accept', fn: () async {
        final adminClient = createPubApiClient(authToken: siteAdminToken);
        final adminOutput = await adminClient.adminInvokeAction(
            'publisher-member-invite',
            AdminInvokeActionArguments(arguments: {
              'publisher': 'example.com',
              'email': 'newmember@pub.dev'
            }));

        expect(adminOutput.output, {
          'message': 'Sent invitation',
          'publisher': 'example.com',
          'email': 'newmember@pub.dev'
        });

        final email = fakeEmailSender.sentMessages.first;
        expect(
            email.subject, 'You have a new invitation to confirm on pub.dev');

        final page = await auditBackend.listRecordsForPublisher('example.com');
        final r = page.records.firstWhere(
            (e) => e.kind == AuditLogRecordKind.publisherMemberInvited);
        expect(r.summary,
            '`support@pub.dev` invited `newmember@pub.dev` to be a member for publisher `example.com`.');

        late String consentId;
        await withFakeAuthRequestContext(
          'newmember@pub.dev',
          () async {
            final authenticatedUser = await requireAuthenticatedWebUser();
            final user = authenticatedUser.user;
            final consentRow = await dbService.query<Consent>().run().single;
            final consent =
                await consentBackend.getConsent(consentRow.consentId, user);
            expect(
                consent.descriptionHtml, contains('/publishers/example.com'));
            expect(consent.descriptionHtml,
                contains('perform administrative actions'));
            consentId = consentRow.consentId;
          },
        );

        final acceptingClient =
            await createFakeAuthPubApiClient(email: 'newmember@pub.dev');
        final rs = await acceptingClient.resolveConsent(
            consentId, account_api.ConsentResult(granted: true));
        expect(rs.granted, true);

        final page2 = await auditBackend.listRecordsForPublisher('example.com');
        final r2 = page2.records.firstWhere(
            (e) => e.kind == AuditLogRecordKind.publisherMemberInviteAccepted);
        expect(r2.summary,
            '`newmember@pub.dev` accepted member invite for publisher `example.com`.');

        final members =
            await publisherBackend.listPublisherMembers('example.com');
        expect(members, hasLength(2));
        expect(members.map((e) => e.email).toSet(), {
          'admin@pub.dev',
          'newmember@pub.dev',
        });
      });
    });
  });

  group('package uploader invite', () {
    setupTestsWithAdminTokenIssues((client) => client.adminInvokeAction(
        'package-invite-uploader',
        AdminInvokeActionArguments(
            arguments: {'package': 'oxygen', 'email': 'member@example.com'})));

    testWithProfile('invite + accept', fn: () async {
      final adminClient = createPubApiClient(authToken: siteAdminToken);
      final adminOutput = await adminClient.adminInvokeAction(
          'package-invite-uploader',
          AdminInvokeActionArguments(
              arguments: {'package': 'oxygen', 'email': 'newmember@pub.dev'}));

      expect(adminOutput.output, {
        'message': 'Invited user',
        'package': 'oxygen',
        'emailSent': true,
        'email': 'newmember@pub.dev',
      });

      final email = fakeEmailSender.sentMessages.first;
      expect(email.subject, 'You have a new invitation to confirm on pub.dev');

      final page = await auditBackend.listRecordsForPackage('oxygen');
      final r = page.records
          .firstWhere((e) => e.kind == AuditLogRecordKind.uploaderInvited);
      expect(r.summary,
          '`support@pub.dev` invited `newmember@pub.dev` to be an uploader for package `oxygen`.');

      late String consentId;
      await withFakeAuthRequestContext(
        'newmember@pub.dev',
        () async {
          final authenticatedUser = await requireAuthenticatedWebUser();
          final user = authenticatedUser.user;
          final consentRow = await dbService.query<Consent>().run().single;
          final consent =
              await consentBackend.getConsent(consentRow.consentId, user);
          expect(consent.descriptionHtml, contains('/packages/oxygen'));
          expect(consent.descriptionHtml,
              contains('perform administrative actions'));
          consentId = consentRow.consentId;
        },
      );

      final acceptingClient =
          await createFakeAuthPubApiClient(email: 'newmember@pub.dev');
      final rs = await acceptingClient.resolveConsent(
          consentId, account_api.ConsentResult(granted: true));
      expect(rs.granted, true);

      final page2 = await auditBackend.listRecordsForPackage('oxygen');
      final r2 = page2.records.firstWhere(
          (e) => e.kind == AuditLogRecordKind.uploaderInviteAccepted);
      expect(r2.summary,
          '`newmember@pub.dev` accepted uploader invite for package `oxygen`.');

      final uploaders =
          (await packageBackend.lookupPackage('oxygen'))!.uploaders;
      expect(uploaders!, hasLength(2));
      expect(
          await Future.wait(uploaders.map((uploader) async =>
              (await accountBackend.lookupUserById(uploader))!.email)),
          {
            'admin@pub.dev',
            'newmember@pub.dev',
          });
    });
  });

  group('create and delete publisher', () {
    testWithProfile('publisher has packages', fn: () async {
      final p1 = await publisherBackend.lookupPublisher('example.com');
      expect(p1, isNotNull);

      await expectLater(
          createPubApiClient(authToken: siteAdminToken).adminInvokeAction(
            'publisher-delete',
            AdminInvokeActionArguments(
              arguments: {'publisher': 'example.com'},
            ),
          ),
          throwsA(isA<RequestException>().having(
            (e) => e.bodyAsJson()['error'],
            '',
            {
              'code': 'NotAcceptable',
              'message':
                  'Publisher \"example.com\" cannot be deleted, as it has package(s): neon.'
            },
          )));

      final p2 = await publisherBackend.lookupPublisher('example.com');
      expect(p2, isNotNull);
    });
  });
}
