// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TestProfile _$TestProfileFromJson(Map<String, dynamic> json) => TestProfile(
      importedPackages: (json['importedPackages'] as List<dynamic>?)
          ?.map((e) => TestPackage.fromJson(e as Map<String, dynamic>))
          .toList(),
      generatedPackages: (json['generatedPackages'] as List<dynamic>?)
          ?.map((e) => GeneratedTestPackage.fromJson(e as Map<String, dynamic>))
          .toList(),
      publishers: (json['publishers'] as List<dynamic>?)
          ?.map((e) => TestPublisher.fromJson(e as Map<String, dynamic>))
          .toList(),
      users: (json['users'] as List<dynamic>?)
          ?.map((e) => TestUser.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultUser: json['defaultUser'] as String?,
    );

Map<String, dynamic> _$TestProfileToJson(TestProfile instance) =>
    <String, dynamic>{
      'importedPackages':
          instance.importedPackages.map((e) => e.toJson()).toList(),
      'generatedPackages':
          instance.generatedPackages.map((e) => e.toJson()).toList(),
      'publishers': instance.publishers.map((e) => e.toJson()).toList(),
      'users': instance.users.map((e) => e.toJson()).toList(),
      if (instance.defaultUser case final value?) 'defaultUser': value,
    };

TestPackage _$TestPackageFromJson(Map<String, dynamic> json) => TestPackage(
      name: json['name'] as String,
      uploaders: (json['uploaders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      publisher: json['publisher'] as String?,
      versions: (json['versions'] as List<dynamic>?)
          ?.map((e) => TestVersion.fromJson(e as Map<String, dynamic>))
          .toList(),
      isDiscontinued: json['isDiscontinued'] as bool?,
      replacedBy: json['replacedBy'] as String?,
      isUnlisted: json['isUnlisted'] as bool?,
      isFlutterFavorite: json['isFlutterFavorite'] as bool?,
      retractedVersions: (json['retractedVersions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      likeCount: (json['likeCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$TestPackageToJson(TestPackage instance) =>
    <String, dynamic>{
      'name': instance.name,
      if (instance.uploaders case final value?) 'uploaders': value,
      if (instance.publisher case final value?) 'publisher': value,
      if (instance.versions?.map((e) => e.toJson()).toList() case final value?)
        'versions': value,
      if (instance.isDiscontinued case final value?) 'isDiscontinued': value,
      if (instance.replacedBy case final value?) 'replacedBy': value,
      if (instance.isUnlisted case final value?) 'isUnlisted': value,
      if (instance.isFlutterFavorite case final value?)
        'isFlutterFavorite': value,
      if (instance.retractedVersions case final value?)
        'retractedVersions': value,
      if (instance.likeCount case final value?) 'likeCount': value,
    };

TestVersion _$TestVersionFromJson(Map<String, dynamic> json) => TestVersion(
      version: json['version'] as String,
      created: json['created'] == null
          ? null
          : DateTime.parse(json['created'] as String),
    );

Map<String, dynamic> _$TestVersionToJson(TestVersion instance) =>
    <String, dynamic>{
      'version': instance.version,
      if (instance.created?.toIso8601String() case final value?)
        'created': value,
    };

GeneratedTestPackage _$GeneratedTestPackageFromJson(
        Map<String, dynamic> json) =>
    GeneratedTestPackage(
      name: json['name'] as String,
      uploaders: (json['uploaders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      publisher: json['publisher'] as String?,
      versions: (json['versions'] as List<dynamic>?)
          ?.map((e) => GeneratedTestVersion.fromJson(e as Map<String, dynamic>))
          .toList(),
      isDiscontinued: json['isDiscontinued'] as bool?,
      replacedBy: json['replacedBy'] as String?,
      isUnlisted: json['isUnlisted'] as bool?,
      isFlutterFavorite: json['isFlutterFavorite'] as bool?,
      retractedVersions: (json['retractedVersions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      likeCount: (json['likeCount'] as num?)?.toInt(),
      template: json['template'] == null
          ? null
          : TestArchiveTemplate.fromJson(
              json['template'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GeneratedTestPackageToJson(
        GeneratedTestPackage instance) =>
    <String, dynamic>{
      'name': instance.name,
      if (instance.uploaders case final value?) 'uploaders': value,
      if (instance.publisher case final value?) 'publisher': value,
      if (instance.isDiscontinued case final value?) 'isDiscontinued': value,
      if (instance.replacedBy case final value?) 'replacedBy': value,
      if (instance.isUnlisted case final value?) 'isUnlisted': value,
      if (instance.isFlutterFavorite case final value?)
        'isFlutterFavorite': value,
      if (instance.retractedVersions case final value?)
        'retractedVersions': value,
      if (instance.likeCount case final value?) 'likeCount': value,
      if (instance.versions?.map((e) => e.toJson()).toList() case final value?)
        'versions': value,
      if (instance.template?.toJson() case final value?) 'template': value,
    };

GeneratedTestVersion _$GeneratedTestVersionFromJson(
        Map<String, dynamic> json) =>
    GeneratedTestVersion(
      version: json['version'] as String,
      created: json['created'] == null
          ? null
          : DateTime.parse(json['created'] as String),
      template: json['template'] == null
          ? null
          : TestArchiveTemplate.fromJson(
              json['template'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$GeneratedTestVersionToJson(
        GeneratedTestVersion instance) =>
    <String, dynamic>{
      'version': instance.version,
      if (instance.created?.toIso8601String() case final value?)
        'created': value,
      if (instance.template?.toJson() case final value?) 'template': value,
    };

TestArchiveTemplate _$TestArchiveTemplateFromJson(Map<String, dynamic> json) =>
    TestArchiveTemplate(
      homepage: json['homepage'] as String?,
      repository: json['repository'] as String?,
      sdkConstraint: json['sdkConstraint'] as String?,
      markdownSamples: json['markdownSamples'] as bool?,
    );

Map<String, dynamic> _$TestArchiveTemplateToJson(
        TestArchiveTemplate instance) =>
    <String, dynamic>{
      if (instance.homepage case final value?) 'homepage': value,
      if (instance.repository case final value?) 'repository': value,
      if (instance.sdkConstraint case final value?) 'sdkConstraint': value,
      if (instance.markdownSamples case final value?) 'markdownSamples': value,
    };

TestPublisher _$TestPublisherFromJson(Map<String, dynamic> json) =>
    TestPublisher(
      name: json['name'] as String,
      members: (json['members'] as List<dynamic>?)
          ?.map((e) => TestMember.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TestPublisherToJson(TestPublisher instance) =>
    <String, dynamic>{
      'name': instance.name,
      'members': instance.members.map((e) => e.toJson()).toList(),
    };

TestMember _$TestMemberFromJson(Map<String, dynamic> json) => TestMember(
      email: json['email'] as String,
      role: json['role'] as String,
    );

Map<String, dynamic> _$TestMemberToJson(TestMember instance) =>
    <String, dynamic>{
      'email': instance.email,
      'role': instance.role,
    };

TestUser _$TestUserFromJson(Map<String, dynamic> json) => TestUser(
      email: json['email'] as String,
      likes:
          (json['likes'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$TestUserToJson(TestUser instance) => <String, dynamic>{
      'email': instance.email,
      'likes': instance.likes,
    };

ResolvedVersion _$ResolvedVersionFromJson(Map<String, dynamic> json) =>
    ResolvedVersion(
      package: json['package'] as String,
      version: json['version'] as String,
      created: json['created'] == null
          ? null
          : DateTime.parse(json['created'] as String),
    );

Map<String, dynamic> _$ResolvedVersionToJson(ResolvedVersion instance) =>
    <String, dynamic>{
      'package': instance.package,
      'version': instance.version,
      if (instance.created?.toIso8601String() case final value?)
        'created': value,
    };
