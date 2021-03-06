// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library linter.src.config;

import 'package:analyzer/plugin/options.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:linter/src/plugin/linter_plugin.dart';
import 'package:yaml/yaml.dart';

/// Parse the given map into a lint config.
LintConfig parseConfig(Map optionsMap) {
  if (optionsMap != null) {
    var options = optionsMap['linter'];
    // Quick check of basic contract.
    if (options is Map) {
      return new _LintConfig().._parseMap(options);
    }
  }
  return null;
}

/// Process the given option [fileContents] and produce a corresponding
/// [LintConfig].
LintConfig processAnalysisOptionsFile(String fileContents, {String fileUrl}) {
  var yaml = loadYamlNode(fileContents, sourceUrl: fileUrl);
  if (yaml is YamlMap) {
    return parseConfig(yaml);
  }
  return null;
}

/// Processes analysis options files and translates them into [LintConfig]s.
class AnalysisOptionsProcessor extends OptionsProcessor {
  final List<Exception> exceptions = <Exception>[];
  final LinterPlugin plugin;
  AnalysisOptionsProcessor(this.plugin);

  @override
  void onError(Exception exception) {
    //TODO(pq): handle exceptions
    exceptions.add(exception);
  }

  @override
  void optionsProcessed(AnalysisContext context, Map<String, Object> options) {
    var lints = plugin.registerLints(context, parseConfig(options));
    if (lints.isNotEmpty) {
      var options = new AnalysisOptionsImpl.from(context.analysisOptions);
      options.lint = true;
      context.analysisOptions = options;
    }
  }
}

abstract class LintConfig {
  factory LintConfig.parse(String source, {String sourceUrl}) =>
      new _LintConfig().._parse(source, sourceUrl: sourceUrl);
  List<String> get fileExcludes;
  List<String> get fileIncludes;
  List<RuleConfig> get ruleConfigs;
}

abstract class RuleConfig {
  Map<String, dynamic> args = <String, dynamic>{};
  String get group;
  String get name;

  /// Provisional
  bool disables(String ruleName) =>
      ruleName == name && args['enabled'] == false;

  bool enables(String ruleName) => ruleName == name && args['enabled'] == true;
}

class _LintConfig implements LintConfig {
  @override
  final fileIncludes = <String>[];
  @override
  final fileExcludes = <String>[];
  @override
  final ruleConfigs = <RuleConfig>[];

  void addAsListOrString(value, List<String> list) {
    if (value is List) {
      value.forEach((v) => list.add(v));
    } else if (value is String) {
      list.add(value);
    }
  }

  bool asBool(scalar) {
    if (scalar is bool) {
      return scalar;
    }
    if (scalar is String) {
      if (scalar == 'true') {
        return true;
      }
      if (scalar == 'false') {
        return false;
      }
    }
    return null;
  }

  String asString(scalar) {
    if (scalar is String) {
      return scalar;
    }
    return null;
  }

  Map<String, dynamic> parseArgs(args) {
    bool enabled = asBool(args);
    if (enabled != null) {
      return {'enabled': enabled};
    }
    return null;
  }

  void _parse(String src, {String sourceUrl}) {
    var yaml = loadYamlNode(src, sourceUrl: sourceUrl);
    if (yaml is YamlMap) {
      _parseYaml(yaml);
    }
  }

  void _parseMap(Map options) {
    //TODO(pq): unify map parsing.
    if (options is YamlMap) {
      _parseYaml(options);
    } else {
      _parseRawMap(options);
    }
  }

  void _parseRawMap(Map options) {
    options.forEach((k, v) {
      if (k is! String) {
        return;
      }
      String key = k;
      switch (key) {
        case 'files':
          if (v is Map) {
            addAsListOrString(v['include'], fileIncludes);
            addAsListOrString(v['exclude'], fileExcludes);
          }
          break;

        case 'rules':
          // - unnecessary_getters
          // - camel_case_types
          if (v is List) {
            v.forEach((rule) {
              var config = new _RuleConfig();
              config.name = asString(rule);
              config.args = {'enabled': true};
              ruleConfigs.add(config);
            });
          }

          // {unnecessary_getters: false, camel_case_types: true}
          if (v is Map) {
            v.forEach((key, value) {
              // style_guide: {unnecessary_getters: false, camel_case_types: true}
              if (value is Map) {
                value.forEach((rule, args) {
                  // unnecessary_getters: false
                  var config = new _RuleConfig();
                  config.group = key;
                  config.name = asString(rule);
                  config.args = parseArgs(args);
                  ruleConfigs.add(config);
                });
              } else {
                //{unnecessary_getters: false}
                value = asBool(value);
                if (value != null) {
                  var config = new _RuleConfig();
                  config.name = asString(key);
                  config.args = {'enabled': value};
                  ruleConfigs.add(config);
                }
              }
            });
          }
          break;
      }
    });
  }

  void _parseYaml(YamlMap yaml) {
    yaml.nodes.forEach((k, v) {
      if (k is! YamlScalar) {
        return;
      }
      YamlScalar key = k;
      switch (key.toString()) {
        case 'files':
          if (v is YamlMap) {
            addAsListOrString(v['include'], fileIncludes);
            addAsListOrString(v['exclude'], fileExcludes);
          }
          break;

        case 'rules':

          // - unnecessary_getters
          // - camel_case_types
          if (v is List) {
            (v as List).forEach((rule) {
              var config = new _RuleConfig();
              config.name = asString(rule);
              config.args = {'enabled': true};
              ruleConfigs.add(config);
            });
          }

          // style_guide: {unnecessary_getters: false, camel_case_types: true}
          if (v is YamlMap) {
            v.forEach((key, value) {
              //{unnecessary_getters: false}
              if (value is bool) {
                var config = new _RuleConfig();
                config.name = asString(key);
                config.args = {'enabled': value};
                ruleConfigs.add(config);
              }

              // style_guide: {unnecessary_getters: false, camel_case_types: true}
              if (value is YamlMap) {
                value.forEach((rule, args) {
                  // TODO: verify format
                  // unnecessary_getters: false
                  var config = new _RuleConfig();
                  config.group = key;
                  config.name = asString(rule);
                  config.args = parseArgs(args);
                  ruleConfigs.add(config);
                });
              }
            });
          }
          break;
      }
    });
  }
}

class _RuleConfig extends RuleConfig {
  @override
  String group;
  @override
  String name;
}
