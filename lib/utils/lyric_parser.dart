class LyricSyllable {
  final int startMs;
  final int durationMs;
  final String text;

  const LyricSyllable(this.startMs, this.durationMs, this.text);
}

class LyricLine {
  final int startMs;
  final int durationMs;
  final List<LyricSyllable> syllables;

  const LyricLine(this.startMs, this.durationMs, this.syllables);

  String get text => syllables.map((syllable) => syllable.text).join();
}

List<LyricLine> parseKrc(String? content) {
  if (content == null || content.isEmpty) return const [];
  content = content.replaceAll(r'\n', String.fromCharCode(10));
  final lines = <LyricLine>[];
  final linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
  final syllablePattern = RegExp(r'<(\d+),(\d+),\d+>([^<]*)');
  for (final raw in content.split(String.fromCharCode(10))) {
    final lineMatch = linePattern.firstMatch(raw.trim());
    if (lineMatch == null) continue;
    final start = int.tryParse(lineMatch.group(1)!) ?? 0;
    final duration = int.tryParse(lineMatch.group(2)!) ?? 0;
    final syllables = <LyricSyllable>[];
    for (final match in syllablePattern.allMatches(lineMatch.group(3)!)) {
      syllables.add(LyricSyllable(
        start + (int.tryParse(match.group(1)!) ?? 0),
        int.tryParse(match.group(2)!) ?? 0,
        match.group(3) ?? '',
      ));
    }
    if (syllables.isNotEmpty) {
      lines.add(LyricLine(start, duration, syllables));
    }
  }
  lines.sort((a, b) => a.startMs.compareTo(b.startMs));
  return lines;
}

List<LyricLine> parseLyrics(String? content) {
  content = content?.replaceAll(r'\n', String.fromCharCode(10));
  final krc = parseKrc(content);
  if (krc.isNotEmpty || content == null || content.isEmpty) return krc;
  final lines = <LyricLine>[];
  final pattern = RegExp(r'^\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)$');
  for (final raw in content.split(String.fromCharCode(10))) {
    final match = pattern.firstMatch(raw.trim());
    if (match == null) continue;
    var fraction = match.group(3) ?? '';
    while (fraction.length < 3) {
      fraction += '0';
    }
    final start =
        (int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) * 1000 +
            (int.tryParse(fraction) ?? 0);
    final text = match.group(4)?.trim() ?? '';
    if (text.isNotEmpty) {
      lines.add(LyricLine(start, 0, [LyricSyllable(start, 0, text)]));
    }
  }
  lines.sort((a, b) => a.startMs.compareTo(b.startMs));
  return lines;
}

String lyricTextAt(LyricLine line, int positionMs) {
  if (line.syllables.length == 1) return line.text;
  final elapsed = positionMs - line.startMs;
  final out = StringBuffer();
  for (final syllable in line.syllables) {
    if (elapsed >= syllable.startMs - line.startMs) {
      out.write(syllable.text);
    } else {
      break;
    }
  }
  return out.toString();
}

/// Returns the continuous highlight progress for a KRC lyric line.
///
/// KRC syllable timings are often one character long. Returning a fractional
/// value here lets the UI reveal the active syllable smoothly instead of
/// jumping one character at a time.
double lyricProgressAt(LyricLine line, int positionMs) {
  if (line.syllables.isEmpty || positionMs < line.startMs) return 0;
  if (line.syllables.length == 1 && line.syllables.single.durationMs == 0) {
    return 1;
  }

  final weights = line.syllables
      .map((syllable) => syllable.text.isEmpty ? 0 : syllable.text.length)
      .toList();
  final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
  if (totalWeight == 0) return 0;

  var completedWeight = 0;
  for (var index = 0; index < line.syllables.length; index++) {
    final syllable = line.syllables[index];
    final weight = weights[index];
    if (positionMs < syllable.startMs) {
      return completedWeight / totalWeight;
    }

    final endMs = syllable.startMs + syllable.durationMs;
    if (syllable.durationMs > 0 && positionMs < endMs) {
      final localProgress =
          (positionMs - syllable.startMs) / syllable.durationMs;
      return ((completedWeight + weight * localProgress) / totalWeight)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    completedWeight += weight;
  }
  return 1;
}

int? lyricLineEndMs(LyricLine line, {int? nextLineStartMs}) {
  if (line.durationMs > 0) return line.startMs + line.durationMs;
  return nextLineStartMs;
}
