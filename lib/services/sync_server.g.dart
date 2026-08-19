// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_server.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SyncServer)
final syncServerProvider = SyncServerFamily._();

final class SyncServerProvider
    extends $NotifierProvider<SyncServer, LiveSyncStatus> {
  SyncServerProvider._({
    required SyncServerFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'syncServerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$syncServerHash();

  @override
  String toString() {
    return r'syncServerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SyncServer create() => SyncServer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveSyncStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveSyncStatus>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SyncServerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$syncServerHash() => r'8333e1ba0600075e9410d7b522fcc4dd32f98fba';

final class SyncServerFamily extends $Family
    with
        $ClassFamilyOverride<
          SyncServer,
          LiveSyncStatus,
          LiveSyncStatus,
          LiveSyncStatus,
          int
        > {
  SyncServerFamily._()
    : super(
        retry: null,
        name: r'syncServerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SyncServerProvider call({required int syncId}) =>
      SyncServerProvider._(argument: syncId, from: this);

  @override
  String toString() => r'syncServerProvider';
}

abstract class _$SyncServer extends $Notifier<LiveSyncStatus> {
  late final _$args = ref.$arg as int;
  int get syncId => _$args;

  LiveSyncStatus build({required int syncId});
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<LiveSyncStatus, LiveSyncStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LiveSyncStatus, LiveSyncStatus>,
              LiveSyncStatus,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(syncId: _$args));
  }
}
