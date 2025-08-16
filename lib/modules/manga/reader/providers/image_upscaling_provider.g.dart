// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_upscaling_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$upscaleImageHash() => r'645ad3d826af5e9bdba3561091df7ccc54396372';

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

/// See also [upscaleImage].
@ProviderFor(upscaleImage)
const upscaleImageProvider = UpscaleImageFamily();

/// See also [upscaleImage].
class UpscaleImageFamily extends Family<AsyncValue<Uint8List?>> {
  /// See also [upscaleImage].
  const UpscaleImageFamily();

  /// See also [upscaleImage].
  UpscaleImageProvider call({
    required UChapDataPreload data,
    required bool upscale,
  }) {
    return UpscaleImageProvider(
      data: data,
      upscale: upscale,
    );
  }

  @override
  UpscaleImageProvider getProviderOverride(
    covariant UpscaleImageProvider provider,
  ) {
    return call(
      data: provider.data,
      upscale: provider.upscale,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'upscaleImageProvider';
}

/// See also [upscaleImage].
class UpscaleImageProvider extends FutureProvider<Uint8List?> {
  /// See also [upscaleImage].
  UpscaleImageProvider({
    required UChapDataPreload data,
    required bool upscale,
  }) : this._internal(
          (ref) => upscaleImage(
            ref as UpscaleImageRef,
            data: data,
            upscale: upscale,
          ),
          from: upscaleImageProvider,
          name: r'upscaleImageProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$upscaleImageHash,
          dependencies: UpscaleImageFamily._dependencies,
          allTransitiveDependencies:
              UpscaleImageFamily._allTransitiveDependencies,
          data: data,
          upscale: upscale,
        );

  UpscaleImageProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.data,
    required this.upscale,
  }) : super.internal();

  final UChapDataPreload data;
  final bool upscale;

  @override
  Override overrideWith(
    FutureOr<Uint8List?> Function(UpscaleImageRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UpscaleImageProvider._internal(
        (ref) => create(ref as UpscaleImageRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        data: data,
        upscale: upscale,
      ),
    );
  }

  @override
  FutureProviderElement<Uint8List?> createElement() {
    return _UpscaleImageProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UpscaleImageProvider &&
        other.data == data &&
        other.upscale == upscale;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, data.hashCode);
    hash = _SystemHash.combine(hash, upscale.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UpscaleImageRef on FutureProviderRef<Uint8List?> {
  /// The parameter `data` of this provider.
  UChapDataPreload get data;

  /// The parameter `upscale` of this provider.
  bool get upscale;
}

class _UpscaleImageProviderElement extends FutureProviderElement<Uint8List?>
    with UpscaleImageRef {
  _UpscaleImageProviderElement(super.provider);

  @override
  UChapDataPreload get data => (origin as UpscaleImageProvider).data;
  @override
  bool get upscale => (origin as UpscaleImageProvider).upscale;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
