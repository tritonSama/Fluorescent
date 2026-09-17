import 'dart:convert';
import 'render_graph.dart';
import 'render_pass.dart';

/// Exception thrown when schema parsing or validation fails.
class RenderGraphSchemaException implements Exception {
  final String message;
  RenderGraphSchemaException(this.message);

  @override
  String toString() => 'RenderGraphSchemaException: $message';
}

/// Parser and serializer for data-driven RenderGraph configurations.
class RenderGraphSchema {
  /// Parse a JSON string into a [RenderGraph].
  static RenderGraph parseJson(String jsonString) {
    try {
      final decoded = json.decode(jsonString);
      if (decoded is! Map) {
        throw RenderGraphSchemaException(
            'Expected JSON root to be an object/Map, got ${decoded.runtimeType}');
      }
      return parseMap(decoded);
    } on RenderGraphSchemaException {
      rethrow;
    } catch (e) {
      throw RenderGraphSchemaException('Failed to parse JSON schema: $e');
    }
  }

  /// Parse a YAML or YAML-compatible string into a [RenderGraph].
  /// Supports JSON (a strict subset of YAML 1.2) and standard YAML key-value syntax.
  static RenderGraph parseYaml(String yamlString) {
    final trimmed = yamlString.trim();
    if (trimmed.isEmpty) {
      throw RenderGraphSchemaException('Empty YAML schema string');
    }
    if (trimmed.startsWith('{')) {
      return parseJson(trimmed);
    }
    try {
      final map = _parseSimpleYaml(trimmed);
      return parseMap(map);
    } catch (e) {
      if (e is RenderGraphSchemaException) rethrow;
      throw RenderGraphSchemaException('Failed to parse YAML schema: $e');
    }
  }

  /// Parse a [Map] (JSON-decoded or YAML-decoded) into a [RenderGraph].
  static RenderGraph parseMap(Map<dynamic, dynamic> rawMap) {
    final map = _normalizeMap(rawMap);

    final outputAttachment = map['outputAttachment'] as String? ?? 'backbuffer';

    // Parse attachments
    final attachmentsMap = <String, AttachmentDescriptor>{};
    final rawAttachments = map['attachments'];
    if (rawAttachments != null) {
      if (rawAttachments is Map) {
        rawAttachments.forEach((key, val) {
          if (val is! Map) {
            throw RenderGraphSchemaException(
                'Attachment "$key" configuration must be a Map');
          }
          final valMap = Map<String, dynamic>.from(val);
          valMap['name'] ??= key;
          final desc = AttachmentDescriptor.fromJson(valMap);
          attachmentsMap[desc.name] = desc;
        });
      } else if (rawAttachments is List) {
        for (final item in rawAttachments) {
          if (item is! Map) {
            throw RenderGraphSchemaException(
                'Attachment item in list must be a Map');
          }
          final itemMap = Map<String, dynamic>.from(item);
          if (itemMap['name'] == null) {
            throw RenderGraphSchemaException(
                'Attachment item in list must contain a "name" property');
          }
          final desc = AttachmentDescriptor.fromJson(itemMap);
          attachmentsMap[desc.name] = desc;
        }
      } else {
        throw RenderGraphSchemaException(
            '"attachments" property must be a Map or List');
      }
    }

    // Parse passes
    final passesMap = <String, RenderPassDescriptor>{};
    final rawPasses = map['passes'];
    if (rawPasses != null) {
      if (rawPasses is List) {
        for (final item in rawPasses) {
          if (item is! Map) {
            throw RenderGraphSchemaException('Pass item in list must be a Map');
          }
          final itemMap = Map<String, dynamic>.from(item);
          if (itemMap['name'] == null ||
              (itemMap['name'] as String).trim().isEmpty) {
            throw RenderGraphSchemaException(
                'Render pass descriptor must contain a non-empty "name" property');
          }
          final desc = RenderPassDescriptor.fromJson(itemMap);
          passesMap[desc.name] = desc;
        }
      } else if (rawPasses is Map) {
        rawPasses.forEach((key, val) {
          if (val is! Map) {
            throw RenderGraphSchemaException(
                'Pass "$key" configuration must be a Map');
          }
          final valMap = Map<String, dynamic>.from(val);
          valMap['name'] ??= key;
          final desc = RenderPassDescriptor.fromJson(valMap);
          passesMap[desc.name] = desc;
        });
      } else {
        throw RenderGraphSchemaException(
            '"passes" property must be a List or Map');
      }
    }

    return RenderGraph(
      attachments: attachmentsMap,
      passes: passesMap,
      outputAttachment: outputAttachment,
    );
  }

  /// Serialize a [RenderGraph] to a standard JSON-compatible [Map].
  static Map<String, dynamic> toMap(RenderGraph graph) {
    return {
      'outputAttachment': graph.outputAttachment,
      'attachments': graph.attachments.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'passes': graph.passes.values.map((pass) => pass.toJson()).toList(),
    };
  }

  /// Serialize a [RenderGraph] to a JSON string.
  static String toJson(RenderGraph graph, {bool pretty = false}) {
    final map = toMap(graph);
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(map);
    }
    return json.encode(map);
  }

  /// Recursively normalize dynamic maps to String-keyed maps.
  static Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      final strKey = key.toString();
      if (value is Map) {
        result[strKey] = _normalizeMap(value);
      } else if (value is List) {
        result[strKey] = _normalizeList(value);
      } else {
        result[strKey] = value;
      }
    });
    return result;
  }

  static List<dynamic> _normalizeList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) return _normalizeMap(item);
      if (item is List) return _normalizeList(item);
      return item;
    }).toList();
  }

  /// Simple YAML indentation parser for YAML configurations without external dependencies.
  static Map<String, dynamic> _parseSimpleYaml(String yaml) {
    final lines = yaml.split(RegExp(r'\r?\n'));
    final result = <String, dynamic>{};
    _parseYamlLines(lines, 0, 0, result);
    return result;
  }

  static int _parseYamlLines(
    List<String> lines,
    int startIndex,
    int currentIndent,
    Map<String, dynamic> currentMap,
  ) {
    int i = startIndex;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        i++;
        continue;
      }

      final indent = line.indexOf(RegExp(r'\S'));
      if (indent < currentIndent) {
        return i;
      }

      final colonIndex = trimmed.indexOf(':');
      if (colonIndex != -1) {
        final key = trimmed.substring(0, colonIndex).trim();
        final rawVal = trimmed.substring(colonIndex + 1).trim();

        if (rawVal.isNotEmpty) {
          currentMap[key] = _parseScalarOrInline(rawVal);
          i++;
        } else {
          // Check next line to see if it's a map or list
          if (i + 1 < lines.length) {
            final nextLine = lines[i + 1];
            final nextTrimmed = nextLine.trim();
            final nextIndent = nextLine.indexOf(RegExp(r'\S'));

            if (nextIndent > indent) {
              if (nextTrimmed.startsWith('- ')) {
                // List of items
                final list = <dynamic>[];
                currentMap[key] = list;
                i = _parseYamlList(lines, i + 1, nextIndent, list);
              } else {
                // Nested Map
                final subMap = <String, dynamic>{};
                currentMap[key] = subMap;
                i = _parseYamlLines(lines, i + 1, nextIndent, subMap);
              }
            } else {
              currentMap[key] = null;
              i++;
            }
          } else {
            currentMap[key] = null;
            i++;
          }
        }
      } else {
        i++;
      }
    }
    return i;
  }

  static int _parseYamlList(
    List<String> lines,
    int startIndex,
    int currentIndent,
    List<dynamic> currentList,
  ) {
    int i = startIndex;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        i++;
        continue;
      }

      final indent = line.indexOf(RegExp(r'\S'));
      if (indent < currentIndent) {
        return i;
      }

      if (trimmed.startsWith('- ')) {
        final content = trimmed.substring(2).trim();
        if (content.contains(':')) {
          // List item is a map
          final itemMap = <String, dynamic>{};
          final colonIdx = content.indexOf(':');
          final k = content.substring(0, colonIdx).trim();
          final v = content.substring(colonIdx + 1).trim();
          if (v.isNotEmpty) {
            itemMap[k] = _parseScalarOrInline(v);
          } else {
            itemMap[k] = null;
          }
          currentList.add(itemMap);
          // Nested lines in this map item
          i++;
          if (i < lines.length) {
            final nextIndent = lines[i].indexOf(RegExp(r'\S'));
            if (nextIndent > indent) {
              i = _parseYamlLines(lines, i, nextIndent, itemMap);
            }
          }
        } else {
          currentList.add(_parseScalarOrInline(content));
          i++;
        }
      } else {
        i++;
      }
    }
    return i;
  }

  static dynamic _parseScalarOrInline(String val) {
    if (val.startsWith('[') && val.endsWith(']')) {
      final inner = val.substring(1, val.length - 1).trim();
      if (inner.isEmpty) return <dynamic>[];
      return inner
          .split(',')
          .map((s) => _parseScalarOrInline(s.trim()))
          .toList();
    }
    if (val == 'true') return true;
    if (val == 'false') return false;
    if (val == 'null') return null;
    final intVal = int.tryParse(val);
    if (intVal != null) return intVal;
    final doubleVal = double.tryParse(val);
    if (doubleVal != null) return doubleVal;
    if ((val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))) {
      return val.substring(1, val.length - 1);
    }
    return val;
  }
}
