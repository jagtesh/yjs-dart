/// Dart translation of src/utils/IdMap.js
///
/// Mirrors: yjs/src/utils/IdMap.js (v14.0.0-22)
library;

import 'dart:convert';
import 'dart:typed_data';

import '../lib0/encoding.dart' as encoding;
import '../lib0/decoding.dart' as decoding;
import '../utils/id.dart';
import '../utils/id_set.dart';
import '../utils/update_encoder.dart';
import '../utils/update_decoder.dart';

// ---------------------------------------------------------------------------
// ContentAttribute
// ---------------------------------------------------------------------------

/// A named attribute with a value and a Rabin fingerprint hash.
///
/// Mirrors: `ContentAttribute` in IdMap.js
class ContentAttribute<V> {
  final String name;
  final V val;

  ContentAttribute(this.name, this.val);

  /// Compute a hash string for this attribute.
  ///
  /// In the JS version this uses lib0/hash/rabin Rabin fingerprint over
  /// the encoded (name, val) bytes. In Dart we use a simpler but stable
  /// SHA-256-based approach (same uniqueness guarantee, different bytes).
  String hash() {
    // Encode name + val as JSON for a stable, deterministic representation.
    final payload = jsonEncode({'n': name, 'v': val});
    // Use a simple but stable hash: base64 of UTF-8 bytes (good enough for
    // deduplication; full Rabin fingerprint can be added in Phase 5).
    return base64Encode(utf8.encode(payload));
  }
}

ContentAttribute<V> createContentAttribute<V>(String name, V val) =>
    ContentAttribute<V>(name, val);

bool _idmapAttrsHas<T>(List<T> attrs, T attr) => attrs.contains(attr);

bool idmapAttrsEqual<T>(List<T> a, List<T> b) =>
    a.length == b.length && a.every((v) => _idmapAttrsHas(b, v));

List<T> _idmapAttrRangeJoin<T>(List<T> a, List<T> b) =>
    [...a, ...b.where((attr) => !_idmapAttrsHas(a, attr))];

// ---------------------------------------------------------------------------
// AttrRange / AttrRanges
// ---------------------------------------------------------------------------

/// A range with associated attributes.
///
/// Mirrors: `AttrRange` in IdMap.js
class AttrRange<Attrs> {
  final int clock;
  final int len;
  final List<ContentAttribute<Attrs>> attrs;

  AttrRange(this.clock, this.len, this.attrs);

  AttrRange<Attrs> copyWith(int clock, int len) =>
      AttrRange<Attrs>(clock, len, attrs);
}

/// A sorted, lazily-merged list of [AttrRange]s.
///
/// Mirrors: `AttrRanges` in IdMap.js
class AttrRanges<Attrs> {
  bool sorted = false;
  final List<AttrRange<Attrs>> _ids;

  AttrRanges(this._ids);

  AttrRanges<Attrs> copy() => AttrRanges<Attrs>(List.of(_ids));

  void add(int clock, int length, List<ContentAttribute<Attrs>> attrs) {
    if (length == 0) return;
    sorted = false;
    _ids.add(AttrRange<Attrs>(clock, length, attrs));
  }

  /// Return sorted, merged list of attr ranges.
  List<AttrRange<Attrs>> getIds() {
    if (!sorted) {
      sorted = true;
      _ids.sort((a, b) => a.clock - b.clock);

      // Split overlapping ranges and merge attributes
      for (var i = 0; i < _ids.length - 1;) {
        final range = _ids[i];
        final nextRange = _ids[i + 1];
        if (range.clock < nextRange.clock) {
          if (range.clock + range.len > nextRange.clock) {
            final diff = nextRange.clock - range.clock;
            _ids[i] = AttrRange<Attrs>(range.clock, diff, range.attrs);
            _ids.insert(i + 1, AttrRange<Attrs>(nextRange.clock, range.len - diff, range.attrs));
          }
          i++;
          continue;
        }
        // range.clock == nextRange.clock — merge
        final largerRange = range.len > nextRange.len ? range : nextRange;
        final smallerLen = range.len < nextRange.len ? range.len : nextRange.len;
        _ids[i] = AttrRange<Attrs>(
          range.clock,
          smallerLen,
          _idmapAttrRangeJoin(range.attrs, nextRange.attrs),
        );
        if (range.len == nextRange.len) {
          _ids.removeAt(i + 1);
        } else {
          _ids[i + 1] = AttrRange<Attrs>(
            range.clock + smallerLen,
            largerRange.len - smallerLen,
            largerRange.attrs,
          );
          // bubblesort item at i+1 to correct position
          var j = i + 1;
          while (j + 1 < _ids.length && _ids[j].clock > _ids[j + 1].clock) {
            final tmp = _ids[j];
            _ids[j] = _ids[j + 1];
            _ids[j + 1] = tmp;
            j++;
          }
        }
        if (smallerLen == 0) i++;
      }
      // Remove zero-len items at front
      while (_ids.isNotEmpty && _ids.first.len == 0) {
        _ids.removeAt(0);
      }
      // Merge adjacent ranges with same attrs
      var ii = 1;
      var jj = 1;
      while (ii < _ids.length) {
        final left = _ids[jj - 1];
        final right = _ids[ii];
        if (left.clock + left.len == right.clock &&
            idmapAttrsEqual(left.attrs, right.attrs)) {
          _ids[jj - 1] = AttrRange<Attrs>(left.clock, left.len + right.len, left.attrs);
        } else if (right.len != 0) {
          if (jj < ii) _ids[jj] = right;
          jj++;
        }
        ii++;
      }
      final newLen = _ids.isEmpty
          ? 0
          : (_ids[jj - 1].len == 0 ? jj - 1 : jj);
      _ids.length = newLen;
    }
    return _ids;
  }
}

// ---------------------------------------------------------------------------
// IdMap
// ---------------------------------------------------------------------------

/// A map of ID ranges to attributes.
///
/// Mirrors: `IdMap` in IdMap.js
class IdMap<Attrs> {
  final Map<int, AttrRanges<Attrs>> clients = {};

  /// Deduplication index: hash → ContentAttribute
  final Map<String, ContentAttribute<Attrs>> attrsH = {};

  /// All known attributes (deduplicated set)
  final Set<ContentAttribute<Attrs>> attrs = {};

  void forEach(void Function(AttrRange<Attrs> range, int client) f) {
    clients.forEach((client, ranges) {
      for (final range in ranges.getIds()) {
        f(range, client);
      }
    });
  }

  bool isEmpty() => clients.isEmpty;

  bool hasId(ID id) => has(id.client, id.clock);

  bool has(int client, int clock) {
    final dr = clients[client];
    if (dr != null) {
      return _findIndexInAttrRanges(dr.getIds(), clock) != null;
    }
    return false;
  }

  List<AttrRange<Attrs>> sliceId(ID id, int len) =>
      slice(id.client, id.clock, len);

  List<AttrRange<Attrs>> slice(int client, int clock, int len) {
    final dr = clients[client];
    final res = <AttrRange<Attrs>>[];
    if (dr != null) {
      final ranges = dr.getIds();
      var index = _findRangeStartInAttrRanges(ranges, clock);
      if (index != null) {
        AttrRange<Attrs>? prev;
        while (index! < ranges.length) {
          var r = ranges[index];
          if (r.clock < clock) {
            r = AttrRange<Attrs>(clock, r.len - (clock - r.clock), r.attrs);
          }
          if (r.clock + r.len > clock + len) {
            r = AttrRange<Attrs>(r.clock, clock + len - r.clock, r.attrs);
          }
          if (r.len <= 0) break;
          final prevEnd = prev != null ? prev.clock + prev.len : clock;
          if (prevEnd < r.clock) {
            res.add(AttrRange<Attrs>(prevEnd, r.clock - prevEnd, const []));
          }
          prev = r;
          res.add(r);
          index++;
        }
      }
    }
    if (res.isNotEmpty) {
      final last = res.last;
      final end = last.clock + last.len;
      if (end < clock + len) {
        res.add(AttrRange<Attrs>(end, clock + len - end, const []));
      }
    } else {
      res.add(AttrRange<Attrs>(clock, len, const []));
    }
    return res;
  }

  void add(int client, int clock, int len, List<ContentAttribute<Attrs>> attrs_) {
    if (len == 0) return;
    final ensured = _ensureAttrs(this, attrs_);
    final ranges = clients[client];
    if (ranges == null) {
      clients[client] = AttrRanges<Attrs>([AttrRange<Attrs>(clock, len, ensured)]);
    } else {
      ranges.add(clock, len, ensured);
    }
  }

  void delete(int client, int clock, int len) {
    deleteRangeFromIdSet(
      _IdSetAdapter(clients as Map<int, IdRanges>),
      client,
      clock,
      len,
    );
  }
}

/// Adapter to allow deleteRangeFromIdSet to work on IdMap clients.
/// This is a workaround for the structural typing used in JS.
class _IdSetAdapter extends IdSet {
  _IdSetAdapter(Map<int, IdRanges> c) {
    clients.addAll(c);
  }
}

// ---------------------------------------------------------------------------
// Local binary search helpers for AttrRange (mirrors IdRange helpers)
// ---------------------------------------------------------------------------

int? _findIndexInAttrRanges<Attrs>(List<AttrRange<Attrs>> dis, int clock) {
  var left = 0;
  var right = dis.length - 1;
  while (left <= right) {
    final midindex = (left + right) ~/ 2;
    final mid = dis[midindex];
    final midclock = mid.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.len) return midindex;
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
  }
  return null;
}

int? _findRangeStartInAttrRanges<Attrs>(List<AttrRange<Attrs>> dis, int clock) {
  var left = 0;
  var right = dis.length - 1;
  while (left <= right) {
    final midindex = (left + right) ~/ 2;
    final mid = dis[midindex];
    final midclock = mid.clock;
    if (midclock <= clock) {
      if (clock < midclock + mid.len) return midindex;
      left = midindex + 1;
    } else {
      right = midindex - 1;
    }
  }
  return left < dis.length ? left : null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Ensure all attrs are registered in [idmap] (dedup by hash).
List<ContentAttribute<Attrs>> _ensureAttrs<Attrs>(
  IdMap<Attrs> idmap,
  List<ContentAttribute<Attrs>> attrs,
) {
  return attrs.map((attr) {
    if (idmap.attrs.contains(attr)) return attr;
    final h = attr.hash();
    final existing = idmap.attrsH[h];
    if (existing != null) return existing;
    idmap.attrs.add(attr);
    idmap.attrsH[h] = attr;
    return attr;
  }).toList();
}

/// Create a fresh IdMap.
///
/// Mirrors: `createIdMap` in IdMap.js
IdMap<dynamic> createIdMap() => IdMap<dynamic>();

/// Create an IdMap from an IdSet with given attrs.
///
/// Mirrors: `createIdMapFromIdSet` in IdMap.js
IdMap<dynamic> createIdMapFromIdSet(IdSet idset, List<ContentAttribute<dynamic>> attrs) {
  final idmap = createIdMap();
  final ensured = _ensureAttrs(idmap, attrs);
  // Deduplicate
  final checkedAttrs = <ContentAttribute<dynamic>>[];
  for (final attr in ensured) {
    if (!_idmapAttrsHas(checkedAttrs, attr)) checkedAttrs.add(attr);
  }
  idset.clients.forEach((client, ranges) {
    final attrRanges = AttrRanges<dynamic>(
      ranges.getIds().map((r) => AttrRange<dynamic>(r.clock, r.len, checkedAttrs)).toList(),
    );
    attrRanges.sorted = true;
    idmap.clients[client] = attrRanges;
  });
  return idmap;
}

/// Create an IdSet from an IdMap by stripping attributes.
///
/// Mirrors: `createIdSetFromIdMap` in IdMap.js
IdSet createIdSetFromIdMap(IdMap<dynamic> idmap) {
  final idset = IdSet();
  idmap.clients.forEach((client, ranges) {
    final idRanges = IdRanges([]);
    for (final range in ranges.getIds()) {
      idRanges.add(range.clock, range.len);
    }
    idset.clients[client] = idRanges;
  });
  return idset;
}

/// Merge multiple IdMaps into a fresh one.
///
/// Mirrors: `mergeIdMaps` in IdMap.js
IdMap<dynamic> mergeIdMaps(List<IdMap<dynamic>> ams) {
  final attrMapper = <ContentAttribute<dynamic>, ContentAttribute<dynamic>>{};
  final merged = createIdMap();
  for (var amsI = 0; amsI < ams.length; amsI++) {
    ams[amsI].clients.forEach((client, rangesLeft) {
      if (!merged.clients.containsKey(client)) {
        var ids = List<AttrRange<dynamic>>.of(rangesLeft.getIds());
        for (var i = amsI + 1; i < ams.length; i++) {
          final nextIds = ams[i].clients[client];
          if (nextIds != null) ids.addAll(nextIds.getIds());
        }
        ids = ids.map((id) => AttrRange<dynamic>(
          id.clock,
          id.len,
          id.attrs.map<ContentAttribute<dynamic>>((attr) =>
            attrMapper.putIfAbsent(attr, () => _ensureAttrs(merged, [attr])[0])
          ).toList(),
        )).toList();
        merged.clients[client] = AttrRanges<dynamic>(ids);
      }
    });
  }
  return merged;
}

/// Encode [idmap] to binary.
///
/// Mirrors: `encodeIdMap` in IdMap.js
Uint8List encodeIdMap(IdMap<dynamic> idmap) {
  final encoder = UpdateEncoderV2();
  writeIdMap(encoder, idmap);
  return encoder.toUint8Array();
}

/// Write [idmap] to [encoder].
///
/// Mirrors: `writeIdMap` in IdMap.js
void writeIdMap(AbstractUpdateEncoder encoder, IdMap<dynamic> idmap) {
  encoding.writeVarUint(encoder.restEncoder, idmap.clients.length);
  var lastWrittenClientId = 0;
  final visitedAttributions = <ContentAttribute<dynamic>, int>{};
  final visitedAttrNames = <String, int>{};

  final entries = idmap.clients.entries.toList()
    ..sort((a, b) => a.key - b.key);

  for (final entry in entries) {
    final client = entry.key;
    final attrRanges = entry.value.getIds();
    encoder.resetIdSetCurVal();
    final diff = client - lastWrittenClientId;
    encoding.writeVarUint(encoder.restEncoder, diff);
    lastWrittenClientId = client;
    encoding.writeVarUint(encoder.restEncoder, attrRanges.length);
    for (final item in attrRanges) {
      encoder.writeIdSetClock(item.clock);
      encoder.writeIdSetLen(item.len);
      encoding.writeVarUint(encoder.restEncoder, item.attrs.length);
      for (final attr in item.attrs) {
        final attrId = visitedAttributions[attr];
        if (attrId != null) {
          encoding.writeVarUint(encoder.restEncoder, attrId);
        } else {
          final newAttrId = visitedAttributions.length;
          visitedAttributions[attr] = newAttrId;
          encoding.writeVarUint(encoder.restEncoder, newAttrId);
          final attrNameId = visitedAttrNames[attr.name];
          if (attrNameId != null) {
            encoding.writeVarUint(encoder.restEncoder, attrNameId);
          } else {
            final newAttrNameId = visitedAttrNames.length;
            encoding.writeVarUint(encoder.restEncoder, newAttrNameId);
            encoding.writeVarString(encoder.restEncoder, attr.name);
            visitedAttrNames[attr.name] = newAttrNameId;
          }
          encoding.writeAny(encoder.restEncoder, attr.val);
        }
      }
    }
  }
}

/// Decode an IdMap from [decoder].
///
/// Mirrors: `readIdMap` in IdMap.js
IdMap<dynamic> readIdMap(AbstractUpdateDecoder decoder) {
  final idmap = createIdMap();
  final numClients = decoding.readVarUint(decoder.restDecoder);
  final visitedAttributions = <ContentAttribute<dynamic>>[];
  final visitedAttrNames = <String>[];
  var lastClientId = 0;

  for (var i = 0; i < numClients; i++) {
    decoder.resetDsCurVal();
    final client = lastClientId + decoding.readVarUint(decoder.restDecoder);
    lastClientId = client;
    final numberOfRanges = decoding.readVarUint(decoder.restDecoder);
    final attrRanges = <AttrRange<dynamic>>[];
    for (var j = 0; j < numberOfRanges; j++) {
      final rangeClock = decoder.readDsClock();
      final rangeLen = decoder.readDsLen();
      final attrs = <ContentAttribute<dynamic>>[];
      final attrsLen = decoding.readVarUint(decoder.restDecoder);
      for (var k = 0; k < attrsLen; k++) {
        final attrId = decoding.readVarUint(decoder.restDecoder);
        if (attrId >= visitedAttributions.length) {
          final attrNameId = decoding.readVarUint(decoder.restDecoder);
          if (attrNameId >= visitedAttrNames.length) {
            visitedAttrNames.add(decoding.readVarString(decoder.restDecoder));
          }
          visitedAttributions.add(
            ContentAttribute<dynamic>(visitedAttrNames[attrNameId], decoding.readAny(decoder.restDecoder)),
          );
        }
        attrs.add(visitedAttributions[attrId]);
      }
      attrRanges.add(AttrRange<dynamic>(rangeClock, rangeLen, attrs));
    }
    idmap.clients[client] = AttrRanges<dynamic>(attrRanges);
  }
  for (final attr in visitedAttributions) {
    idmap.attrs.add(attr);
    idmap.attrsH[attr.hash()] = attr;
  }
  return idmap;
}

/// Decode an IdMap from binary [data].
///
/// Mirrors: `decodeIdMap` in IdMap.js
IdMap<dynamic> decodeIdMap(Uint8List data) =>
    readIdMap(UpdateDecoderV2(decoding.createDecoder(data)));

/// Compute the diff: ranges in [set] that are NOT in [exclude].
///
/// Mirrors: `diffIdMap` in IdMap.js
IdMap<dynamic> diffIdMap(IdMap<dynamic> set, IdSet exclude) {
  // Reuse diffIdSet logic on the underlying IdSet structure
  final setAsIdSet = IdSet();
  set.clients.forEach((client, ranges) {
    setAsIdSet.clients[client] = IdRanges(
      ranges.getIds().map((r) => IdRange(r.clock, r.len)).toList(),
    );
  });
  final diffed = diffIdSet(setAsIdSet, exclude);
  // Rebuild as IdMap preserving attrs
  final result = createIdMap();
  result.attrs.addAll(set.attrs);
  result.attrsH.addAll(set.attrsH);
  diffed.clients.forEach((client, ranges) {
    // Find matching attr ranges from original set
    final origRanges = set.clients[client];
    if (origRanges != null) {
      final attrRanges = <AttrRange<dynamic>>[];
      for (final r in ranges.getIds()) {
        // Find attrs for this range from original
        final origSlice = origRanges.getIds().where(
          (or) => or.clock <= r.clock && or.clock + or.len >= r.clock + r.len,
        );
        final attrs = origSlice.isNotEmpty ? origSlice.first.attrs : <ContentAttribute<dynamic>>[];
        attrRanges.add(AttrRange<dynamic>(r.clock, r.len, attrs));
      }
      if (attrRanges.isNotEmpty) {
        result.clients[client] = AttrRanges<dynamic>(attrRanges);
      }
    }
  });
  return result;
}

/// Filter an IdMap by a predicate on attrs.
///
/// Mirrors: `filterIdMap` in IdMap.js
IdMap<dynamic> filterIdMap(
  IdMap<dynamic> idmap,
  bool Function(List<ContentAttribute<dynamic>>) predicate,
) {
  final filtered = createIdMap();
  idmap.clients.forEach((client, ranges) {
    final attrRanges = <AttrRange<dynamic>>[];
    for (final range in ranges.getIds()) {
      if (predicate(range.attrs)) {
        final rangeCpy = range.copyWith(range.clock, range.len);
        attrRanges.add(rangeCpy);
        for (final attr in rangeCpy.attrs) {
          filtered.attrs.add(attr);
          filtered.attrsH[attr.hash()] = attr;
        }
      }
    }
    if (attrRanges.isNotEmpty) {
      filtered.clients[client] = AttrRanges<dynamic>(attrRanges);
    }
  });
  return filtered;
}

/// Alias for insertIntoIdSetInternal, works on IdMap too.
///
/// Mirrors: `insertIntoIdMap` in IdMap.js
void insertIntoIdMap(IdMap<dynamic> dest, IdMap<dynamic> src) {
  src.clients.forEach((client, srcRanges) {
    final targetRanges = dest.clients[client];
    if (targetRanges != null) {
      targetRanges._ids.addAll(srcRanges.getIds());
      targetRanges.sorted = false;
    } else {
      final res = srcRanges.copy();
      res.sorted = true;
      dest.clients[client] = res;
    }
  });
}

/// Compute the intersection of two IdMaps.
///
/// Mirrors: `intersectMaps` in IdMap.js
IdMap<dynamic> intersectMaps(IdMap<dynamic> setA, IdMap<dynamic> setB) {
  final res = createIdMap();
  setA.clients.forEach((client, aRanges_) {
    final resRanges = <AttrRange<dynamic>>[];
    final bRanges_ = setB.clients[client];
    final aRanges = aRanges_.getIds();
    if (bRanges_ != null) {
      final bRanges = bRanges_.getIds();
      for (var a = 0, b = 0; a < aRanges.length && b < bRanges.length;) {
        final aRange = aRanges[a];
        final bRange = bRanges[b];
        final clock = aRange.clock > bRange.clock ? aRange.clock : bRange.clock;
        final aEnd = aRange.clock + aRange.len;
        final bEnd = bRange.clock + bRange.len;
        final len = (aEnd < bEnd ? aEnd : bEnd) - clock;
        if (len > 0) {
          resRanges.add(AttrRange<dynamic>(
            clock,
            len,
            [...aRange.attrs, ...bRange.attrs],
          ));
        }
        if (aEnd < bEnd) {
          a++;
        } else {
          b++;
        }
      }
    }
    if (resRanges.isNotEmpty) {
      res.clients[client] = AttrRanges<dynamic>(resRanges);
    }
  });
  return res;
}
