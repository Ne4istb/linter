// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:linter/src/io.dart';
import 'package:linter/src/pub.dart';
import 'package:path/path.dart' as p;

Pubspec _findAndParsePubspec(Directory root) {
  if (root.existsSync()) {
    File pubspec = root
        .listSync(followLinks: false)
        .firstWhere((f) => isPubspecFile(f), orElse: () => null);
    if (pubspec != null) {
      return new Pubspec.parse(pubspec.readAsStringSync(),
          sourceUrl: p.toUri(pubspec.path));
    }
  }
  return null;
}

/// A semantic representation of a Dart project.
///
/// Projects provide a semantic model of a Dart project based on the
/// [pub package layout conventions] (https://www.dartlang.org/tools/pub/package-layout.html).
/// This model allows clients to traverse project contents in a convenient and
/// standardized way, access global information (such as whether elements are
/// in the "public API") and resources that have special meanings in the
/// context of pub package layout conventions.
class DartProject {
  _ApiModel _apiModel;
  String _name;
  Pubspec _pubspec;

  /// Project root.
  final Directory root;

  /// Create a Dart project for the corresponding [context] and [sources].
  /// If a [dir] is unspecified the current working directory will be
  /// used.
  DartProject(AnalysisContext context, List<Source> sources, {Directory dir})
      : root = dir ?? Directory.current {
    _pubspec = _findAndParsePubspec(root);
    _apiModel = new _ApiModel(context, sources, root);
  }

  /// The project's name.
  ///
  /// Project names correspond to the package name as specified in the project's
  /// [pubspec]. The pubspec is found relative to the project [root].  If no
  /// pubspec can be found, the name defaults to the project root basename.
  String get name => _name ??= _calculateName();

  /// The project's pubspec.
  Pubspec get pubspec => _pubspec;

  /// Returns `true` if the given element is part of this project's public API.
  ///
  /// Public API elements are defined as all elements that are in the packages's
  /// `lib` directory, *less* those in `lib/src` (which are treated as private
  /// *implementation files*), plus elements having been explicitly exported
  /// via an `export` directive.
  bool isApi(Element element) => _apiModel.contains(element);

  String _calculateName() {
    if (pubspec != null) {
      var nameEntry = pubspec.name;
      if (nameEntry != null) {
        return nameEntry.value.text;
      }
    }
    return p.basename(root.path);
  }
}

/// An object that can be used to visit Dart project structure.
abstract class ProjectVisitor<T> {
  T visit(DartProject project) => null;
}

/// Captures the project's API as defined by pub package layout standards.
class _ApiModel {
  final AnalysisContext context;
  final List<Source> sources;
  final Directory root;
  final Set<LibraryElement> elements = new Set();

  _ApiModel(this.context, this.sources, this.root) {
    _calculate();
  }

  /// Return `true` if this element is part of the public API for this package.
  bool contains(Element element) {
    while (element != null) {
      if (!element.isPrivate && elements.contains(element)) {
        return true;
      }
      element = element.enclosingElement;
    }
    return false;
  }

  _calculate() {
    if (sources == null || sources.isEmpty) {
      return;
    }

    var libDir = root.path + '/lib';
    var libSrcDir = libDir + '/src';

    for (Source source in sources) {
      var path = source.uri.path;
      if (path.startsWith(libDir) && !path.startsWith(libSrcDir)) {
        var library = context.computeLibraryElement(source);
        var namespaceBuilder = new NamespaceBuilder();
        var exports = namespaceBuilder.createExportNamespaceForLibrary(library);
        var public = namespaceBuilder.createPublicNamespaceForLibrary(library);
        elements.addAll(exports.definedNames.values);
        elements.addAll(public.definedNames.values);
      }
    }
  }
}
