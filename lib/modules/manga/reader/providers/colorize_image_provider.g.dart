// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'colorize_image_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$processColorizeImageHash() =>
    r'521c020db731136102a83c224e1f24f8e4e45d9a';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [processColorizeImage].
@ProviderFor(processColorizeImage)
const processColorizeImageProvider = ProcessColorizeImageFamily();

/// See also [processColorizeImage].
class ProcessColorizeImageFamily extends Family<AsyncValue<Uint8List?>> {
  /// See also [processColorizeImage].
  const ProcessColorizeImageFamily();

  /// See also [processColorizeImage].
  ProcessColorizeImageProvider call({
    required UChapDataPreload data,
    required bool colorize,
  }) {
    return ProcessColorizeImageProvider(data: data, colorize: colorize);
  }

  @override
  ProcessColorizeImageProvider getProviderOverride(
    covariant ProcessColorizeImageProvider provider,
  ) {
    return call(data: provider.data, colorize: provider.colorize);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'processColorizeImageProvider';
}

/// See also [processColorizeImage].
class ProcessColorizeImageProvider extends FutureProvider<Uint8List?> {
  /// See also [processColorizeImage].
  ProcessColorizeImageProvider({
    required UChapDataPreload data,
    required bool colorize,
  }) : this._internal(
         (ref) => processColorizeImage(
           ref as ProcessColorizeImageRef,
           data: data,
           colorize: colorize,
         ),
         from: processColorizeImageProvider,
         name: r'processColorizeImageProvider',
         debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
             ? null
             : _$processColorizeImageHash,
         dependencies: ProcessColorizeImageFamily._dependencies,
         allTransitiveDependencies:
             ProcessColorizeImageFamily._allTransitiveDependencies,
         data: data,
         colorize: colorize,
       );

  ProcessColorizeImageProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.data,
    required this.colorize,
  }) : super.internal();

  final UChapDataPreload data;
  final bool colorize;

  @override
  Override overrideWith(
    FutureOr<Uint8List?> Function(ProcessColorizeImageRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: ProcessColorizeImageProvider._internal(
        (ref) => create(ref as ProcessColorizeImageRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        data: data,
        colorize: colorize,
      ),
    );
  }

  @override
  FutureProviderElement<Uint8List?> createElement() {
    return _ProcessColorizeImageProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is ProcessColorizeImageProvider &&
        other.data == data &&
        other.colorize == colorize;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, data.hashCode);
    hash = _SystemHash.combine(hash, colorize.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin ProcessColorizeImageRef on FutureProviderRef<Uint8List?> {
  /// The parameter `data` of this provider.
  UChapDataPreload get data;

  /// The parameter `colorize` of this provider.
  bool get colorize;
}

class _ProcessColorizeImageProviderElement
    extends FutureProviderElement<Uint8List?>
    with ProcessColorizeImageRef {
  _ProcessColorizeImageProviderElement(super.provider);

  @override
  UChapDataPreload get data => (origin as ProcessColorizeImageProvider).data;
  @override
  bool get colorize => (origin as ProcessColorizeImageProvider).colorize;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
