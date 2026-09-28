import 'dart:typed_data';

/// Tables a PDF viewer reads from an embedded TrueType or CFF font program.
///
/// Everything else — shaping tables, variation deltas, glyph names, device
/// metrics — is dead weight once the glyphs are already shaped and placed.
const Set<String> _pdfTables = {
  'head',
  'hhea',
  'hmtx',
  'maxp',
  'OS/2',
  'cmap',
  'post',
  'glyf',
  'loca',
  'cvt ',
  'fpgm',
  'prep',
  'CFF ',
  'CFF2',
};

/// Builds a font program for embedding in a PDF that keeps only `glyphIds`.
///
/// Glyph ids stay where they were, so shaped output that addresses glyphs
/// directly (a PDF `/CIDToGIDMap /Identity`) keeps working; dropped glyphs
/// become empty. Composite glyphs keep the glyphs they are built from, and
/// glyph 0 is always kept. Only tables a PDF renderer reads survive: variation
/// data goes, so a variable font embeds its default instance, which is also
/// the one the shaper measured.
///
/// CFF outlines are not pruned glyph by glyph, only stripped of the other
/// tables. `faceIndex` selects a face of a collection; the result is always a
/// single font, which is the only form a PDF can embed.
///
/// Throws [FormatException] when `bytes` is not a font this can read.
Uint8List subsetFontForPdf(
  Uint8List bytes,
  Iterable<int> glyphIds, {
  int faceIndex = 0,
}) {
  final data = ByteData.sublistView(bytes);
  final tables = _readDirectory(data, faceIndex);
  final flavor = data.getUint32(_faceOffset(data, faceIndex));

  final kept = <String, Uint8List>{
    for (final entry in tables.entries)
      if (_pdfTables.contains(entry.key))
        entry.key: Uint8List.sublistView(
          bytes,
          entry.value.offset,
          entry.value.offset + entry.value.length,
        ),
  };
  for (final tag in const ['head', 'hhea', 'hmtx', 'maxp']) {
    if (!kept.containsKey(tag)) {
      throw FormatException('The font has no $tag table.');
    }
  }
  // The copy is edited below; the caller's bytes stay untouched.
  kept['head'] = Uint8List.fromList(kept['head']!);

  final post = kept['post'];
  if (post != null && post.length >= 32) {
    // Version 3 drops the glyph names, which are most of a `post` table.
    kept['post'] = Uint8List.fromList(post.sublist(0, 32))
      ..setRange(0, 4, const [0, 3, 0, 0]);
  }

  final glyf = kept['glyf'];
  final loca = kept['loca'];
  if (glyf != null && loca != null) {
    final head = ByteData.sublistView(kept['head']!);
    final numGlyphs = ByteData.sublistView(kept['maxp']!).getUint16(4);
    final longOffsets = head.getInt16(50) == 1;
    final (newGlyf, newLoca, newLong, keep) = _subsetGlyf(
      glyf,
      loca,
      numGlyphs,
      longOffsets,
      glyphIds,
    );
    kept['glyf'] = newGlyf;
    kept['loca'] = newLoca;
    kept['hmtx'] = _zeroDroppedMetrics(kept['hmtx']!, kept['hhea']!, keep);
    head.setInt16(50, newLong ? 1 : 0);
  }
  if (kept.containsKey('cmap')) {
    // The PDF addresses glyphs by id, so no character mapping is read. An empty
    // table rather than none keeps strict font loaders from rejecting the file.
    kept['cmap'] = _emptyCmap;
  }

  return _writeFont(flavor, kept);
}

class _TableRecord {
  const _TableRecord(this.offset, this.length);
  final int offset;
  final int length;
}

int _faceOffset(ByteData data, int faceIndex) {
  if (data.lengthInBytes < 12) {
    throw const FormatException('The font data is truncated.');
  }
  // 'ttcf': a collection whose header lists the offset of every face.
  if (data.getUint32(0) != 0x74746366) {
    if (faceIndex != 0) {
      throw FormatException('The font has no face $faceIndex.');
    }
    return 0;
  }
  final faceCount = data.getUint32(8);
  if (faceIndex < 0 || faceIndex >= faceCount) {
    throw FormatException('The collection has no face $faceIndex.');
  }
  return data.getUint32(12 + faceIndex * 4);
}

Map<String, _TableRecord> _readDirectory(ByteData data, int faceIndex) {
  final base = _faceOffset(data, faceIndex);
  if (base + 12 > data.lengthInBytes) {
    throw const FormatException('The font data is truncated.');
  }
  final count = data.getUint16(base + 4);
  final tables = <String, _TableRecord>{};
  for (var index = 0; index < count; index++) {
    final record = base + 12 + index * 16;
    if (record + 16 > data.lengthInBytes) {
      throw const FormatException('The table directory is truncated.');
    }
    final tag = String.fromCharCodes([
      for (var byte = 0; byte < 4; byte++) data.getUint8(record + byte),
    ]);
    final offset = data.getUint32(record + 8);
    final length = data.getUint32(record + 12);
    if (offset + length > data.lengthInBytes) {
      throw FormatException('The $tag table runs past the end of the font.');
    }
    tables[tag] = _TableRecord(offset, length);
  }
  return tables;
}

/// Zero advances for dropped glyphs compress to nothing; the PDF declares the
/// widths it uses in `/W` and never reads these.
Uint8List _zeroDroppedMetrics(Uint8List hmtx, Uint8List hhea, Set<int> keep) {
  final metrics = Uint8List.fromList(hmtx);
  final longCount = ByteData.sublistView(hhea).getUint16(34);
  final longBytes = longCount * 4;
  for (var glyph = 0; ; glyph++) {
    final start = glyph < longCount
        ? glyph * 4
        : longBytes + (glyph - longCount) * 2;
    final end = start + (glyph < longCount ? 4 : 2);
    if (end > metrics.length) {
      break;
    }
    if (!keep.contains(glyph)) {
      metrics.fillRange(start, end, 0);
    }
  }
  return metrics;
}

/// A format 4 subtable holding only the mandatory terminating segment.
final Uint8List _emptyCmap = Uint8List.fromList(const [
  0, 0, 0, 1, // version, one encoding record
  0, 3, 0, 1, 0, 0, 0, 12, // Windows Unicode BMP, subtable at 12
  0, 4, 0, 24, 0, 0, // format 4, length, language
  0, 2, 0, 2, 0, 0, 0, 0, // segCountX2, searchRange, entrySelector, rangeShift
  0xFF, 0xFF, 0, 0, // endCode, reservedPad
  0xFF, 0xFF, 0, 1, 0, 0, // startCode, idDelta, idRangeOffset
]);

(Uint8List, Uint8List, bool, Set<int>) _subsetGlyf(
  Uint8List glyf,
  Uint8List loca,
  int numGlyphs,
  bool longOffsets,
  Iterable<int> glyphIds,
) {
  final locaData = ByteData.sublistView(loca);
  final needed = (numGlyphs + 1) * (longOffsets ? 4 : 2);
  if (loca.length < needed) {
    throw const FormatException('The loca table is shorter than maxp says.');
  }
  int offsetOf(int glyph) => longOffsets
      ? locaData.getUint32(glyph * 4)
      : locaData.getUint16(glyph * 2) * 2;

  (int, int) rangeOf(int glyph) {
    final start = offsetOf(glyph);
    final end = offsetOf(glyph + 1);
    if (end < start || end > glyf.length) {
      throw FormatException('Glyph $glyph lies outside the glyf table.');
    }
    return (start, end);
  }

  final keep = <int>{};
  final pending = <int>[
    0,
    for (final glyph in glyphIds)
      if (glyph > 0 && glyph < numGlyphs) glyph,
  ];
  final glyfData = ByteData.sublistView(glyf);
  while (pending.isNotEmpty) {
    final glyph = pending.removeLast();
    if (!keep.add(glyph)) {
      continue;
    }
    final (start, end) = rangeOf(glyph);
    // A negative contour count marks a composite, built from other glyphs.
    if (end - start < 10 || glyfData.getInt16(start) >= 0) {
      continue;
    }
    var cursor = start + 10;
    while (cursor + 4 <= end) {
      final flags = glyfData.getUint16(cursor);
      final component = glyfData.getUint16(cursor + 2);
      if (component < numGlyphs && !keep.contains(component)) {
        pending.add(component);
      }
      cursor += 4 + ((flags & 0x0001) != 0 ? 4 : 2);
      if ((flags & 0x0008) != 0) {
        cursor += 2;
      } else if ((flags & 0x0040) != 0) {
        cursor += 4;
      } else if ((flags & 0x0080) != 0) {
        cursor += 8;
      }
      if ((flags & 0x0020) == 0) {
        break;
      }
    }
  }

  final ranges = [
    for (var glyph = 0; glyph < numGlyphs; glyph++) rangeOf(glyph),
  ];
  var total = 0;
  for (final glyph in keep) {
    final (start, end) = ranges[glyph];
    total += (end - start + 3) & ~3;
  }
  // Short offsets store half the byte offset, so they reach 128KB.
  final useLong = total > 0x1FFFE;

  final newGlyf = Uint8List(total);
  final newLoca = Uint8List((numGlyphs + 1) * (useLong ? 4 : 2));
  final newLocaData = ByteData.sublistView(newLoca);
  void writeOffset(int glyph, int offset) => useLong
      ? newLocaData.setUint32(glyph * 4, offset)
      : newLocaData.setUint16(glyph * 2, offset >> 1);

  var cursor = 0;
  for (var glyph = 0; glyph < numGlyphs; glyph++) {
    writeOffset(glyph, cursor);
    if (!keep.contains(glyph)) {
      continue;
    }
    final (start, end) = ranges[glyph];
    newGlyf.setRange(cursor, cursor + end - start, glyf, start);
    cursor += (end - start + 3) & ~3;
  }
  writeOffset(numGlyphs, cursor);
  return (newGlyf, newLoca, useLong, keep);
}

int _checksum(Uint8List table) {
  var sum = 0;
  final full = table.length & ~3;
  final data = ByteData.sublistView(table);
  for (var offset = 0; offset < full; offset += 4) {
    sum = (sum + data.getUint32(offset)) & 0xFFFFFFFF;
  }
  if (full < table.length) {
    var last = 0;
    for (var index = 0; index < 4; index++) {
      last =
          (last << 8) | (full + index < table.length ? table[full + index] : 0);
    }
    sum = (sum + last) & 0xFFFFFFFF;
  }
  return sum;
}

Uint8List _writeFont(int flavor, Map<String, Uint8List> tables) {
  final tags = tables.keys.toList()..sort();
  var searchRange = 1;
  var entrySelector = 0;
  while (searchRange * 2 <= tags.length) {
    searchRange *= 2;
    entrySelector++;
  }
  searchRange *= 16;

  final headerSize = 12 + tags.length * 16;
  var size = headerSize;
  for (final tag in tags) {
    size += (tables[tag]!.length + 3) & ~3;
  }

  final out = Uint8List(size);
  final data = ByteData.sublistView(out)
    ..setUint32(0, flavor)
    ..setUint16(4, tags.length)
    ..setUint16(6, searchRange)
    ..setUint16(8, entrySelector)
    ..setUint16(10, tags.length * 16 - searchRange);

  // The whole-font checksum is taken with this field zeroed.
  ByteData.sublistView(tables['head']!).setUint32(8, 0);

  var offset = headerSize;
  var headOffset = 0;
  for (var index = 0; index < tags.length; index++) {
    final tag = tags[index];
    final table = tables[tag]!;
    final record = 12 + index * 16;
    for (var byte = 0; byte < 4; byte++) {
      data.setUint8(record + byte, tag.codeUnitAt(byte));
    }
    data
      ..setUint32(record + 4, _checksum(table))
      ..setUint32(record + 8, offset)
      ..setUint32(record + 12, table.length);
    out.setRange(offset, offset + table.length, table);
    if (tag == 'head') {
      headOffset = offset;
    }
    offset += (table.length + 3) & ~3;
  }

  data.setUint32(headOffset + 8, (0xB1B0AFBA - _checksum(out)) & 0xFFFFFFFF);
  return out;
}
