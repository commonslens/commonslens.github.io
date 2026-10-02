import 'dart:convert';

import 'search_models.dart';

/// Pure compiler from typed search state to CirrusSearch syntax and UI chips.
/// It performs no I/O and owns every display/query clause transformation.
class SearchQueryCompiler {
  const SearchQueryCompiler();

  static final RegExp multiQuerySeparator = RegExp(r'\s+\+\s+');

  static const Map<LicensePreset, String> _licenseClauses = {
    LicensePreset.cc0: 'haswbstatement:P275=Q6938433',
    LicensePreset.ccBy4: 'haswbstatement:P275=Q20007257',
    LicensePreset.ccBySa4: 'haswbstatement:P275=Q18199165',
    LicensePreset.publicDomain: 'haswbstatement:P6216=Q88088423',
  };

  static const Map<QualityFilter, String> _qualityClauses = {
    QualityFilter.qualityImage: 'hastemplate:"Quality image"',
    QualityFilter.valuedImage: 'hastemplate:"Valued image"',
    QualityFilter.featuredPicture:
        'incategory:"Featured pictures on Wikimedia Commons"',
  };

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  String buildSignature(SearchState state) =>
      jsonEncode(_canonicalizeJson(state.toJson()));

  dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalizeJson(value[key])};
    }
    if (value is List) {
      final values = value.map(_canonicalizeJson).toList();
      values.sort(
        (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
      );
      return values;
    }
    return value;
  }

  QueryBuildResult buildQuery(SearchState state, {FileFormat? overrideFormat}) {
    final parts = <String>[];
    final chips = <QueryChipData>[];

    if (state.localOnly) {
      parts.add('local:');
      chips.add(const QueryChipData(id: 'localOnly', label: 'Local only'));
    }

    final queryText = state.queryText.trim();
    if (queryText.isNotEmpty) {
      if (state.titleOnly) {
        parts.add('intitle:"$queryText"');
        chips.add(const QueryChipData(id: 'titleOnly', label: 'Title only'));
      } else {
        parts.add(queryText);
      }
    }

    switch (state.tab) {
      case MediaTabType.allMedia:
        chips.add(const QueryChipData(id: 'tab', label: 'All media'));
        break;
      case MediaTabType.images:
        chips.add(const QueryChipData(id: 'tab', label: 'Images'));
        parts.add('filetype:bitmap');
        break;
      case MediaTabType.vectors:
        chips.add(const QueryChipData(id: 'tab', label: 'SVG / Diagrams'));
        parts.add('filetype:drawing');
        break;
      case MediaTabType.audio:
        chips.add(const QueryChipData(id: 'tab', label: 'Audio'));
        parts.add('filetype:audio');
        break;
      case MediaTabType.video:
        chips.add(const QueryChipData(id: 'tab', label: 'Video'));
        parts.add('filetype:video');
        break;
      case MediaTabType.documents:
        chips.add(const QueryChipData(id: 'tab', label: 'Docs'));
        parts.add('filetype:office');
        break;
    }

    for (final format in state.formats.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      chips.add(
        QueryChipData(
          id: 'format:${format.name}',
          label: fileFormatLabel(format),
        ),
      );
    }

    if (overrideFormat != null) {
      parts.add('filemime:"${_getMimeString(overrideFormat)}"');
    }

    // Union mode (OR) for categories works exactly like statementsUnion
    // below: this join is just an honest preview of intent for the display
    // query / chips. The actual OR execution — same precedence problem as
    // statements have when mixed into one big AND'd query string — happens
    // via per-category fan-out in _fetchPageForCategory further down.
    final includeCategories = (state.categories.toList()..sort())
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (state.categoriesUnion && includeCategories.length > 1) {
      final clauses = includeCategories
          .map((c) =>
              state.deepCategoryMode ? 'deepcat:"$c"' : 'incategory:"$c"')
          .toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final c in includeCategories) {
        parts.add(state.deepCategoryMode ? 'deepcat:"$c"' : 'incategory:"$c"');
      }
    }
    for (final c in includeCategories) {
      chips.add(QueryChipData(
        id: 'category:$c',
        label: state.deepCategoryMode ? 'Deep category: $c' : 'Category: $c',
      ));
    }

    for (final category in state.excludeCategories.toList()..sort()) {
      final safe = category.trim();
      if (safe.isEmpty) continue;

      if (state.deepCategoryMode) {
        parts.add('-deepcat:"$safe"');
        chips.add(QueryChipData(
            id: 'excludeCategory:$safe', label: 'Not in deep category: $safe'));
      } else {
        parts.add('-incategory:"$safe"');
        chips.add(QueryChipData(
            id: 'excludeCategory:$safe', label: 'Not in category: $safe'));
      }
    }

    if (state.languageCode != null && state.languageCode!.trim().isNotEmpty) {
      final lang = state.languageCode!.trim();
      parts.add('inlanguage:$lang');
      chips.add(QueryChipData(id: 'language', label: 'Language: $lang'));
    }

    if (state.contentModel != null && state.contentModel!.trim().isNotEmpty) {
      final model = state.contentModel!.trim();
      parts.add('contentmodel:$model');
      chips.add(QueryChipData(id: 'contentModel', label: 'Model: $model'));
    }

    if (state.createdDate != null) {
      final created = state.createdDate!;
      if (created.from != null && created.from!.trim().isNotEmpty) {
        final from = created.from!.trim();
        parts.add('creationdate:>=$from');
        chips.add(QueryChipData(id: 'createdFrom', label: 'Created ≥ $from'));
      }
      if (created.to != null && created.to!.trim().isNotEmpty) {
        final to = created.to!.trim();
        parts.add('creationdate:<$to');
        chips.add(QueryChipData(id: 'createdTo', label: 'Created < $to'));
      }
    }

    if (state.editedDate != null) {
      final edited = state.editedDate!;
      if (edited.from != null && edited.from!.trim().isNotEmpty) {
        final from = edited.from!.trim();
        parts.add('lasteditdate:>=$from');
        chips.add(QueryChipData(id: 'editedFrom', label: 'Edited ≥ $from'));
      }
      if (edited.to != null && edited.to!.trim().isNotEmpty) {
        final to = edited.to!.trim();
        parts.add('lasteditdate:<$to');
        chips.add(QueryChipData(id: 'editedTo', label: 'Edited < $to'));
      }
    }

    // License (structured-data statement — see _licenseClauses). A file
    // only ever carries one license, so selecting more than one is always
    // an OR match ("any of these"), never an AND. With 2+ selected, Cirrus
    // can't reliably OR this clause together with every other active
    // AND'd filter in one query string (same precedence hazard noted
    // elsewhere in this file), so this join is a preview only — the real
    // OR execution happens via per-license fan-out in _fetchPageForLicense
    // further down, same shape as categories/depicts/statements union mode.
    final selectedLicenses = state.licensePresets.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (selectedLicenses.length == 1) {
      final clause = _licenseClauses[selectedLicenses.first];
      if (clause != null) {
        parts.add(clause);
        chips.add(QueryChipData(
          id: 'license:${selectedLicenses.first.name}',
          label: licensePresetLabel(selectedLicenses.first),
        ));
      }
    } else if (selectedLicenses.length > 1) {
      final clauses = selectedLicenses
          .map((l) => _licenseClauses[l])
          .whereType<String>()
          .toList();
      if (clauses.isNotEmpty) parts.add(clauses.join(' OR '));
      for (final l in selectedLicenses) {
        chips.add(QueryChipData(
            id: 'license:${l.name}', label: licensePresetLabel(l)));
      }
    }

    // Attribution requirement — no CirrusSearch keyword exposes this
    // directly (it's a MediaWiki-computed extmetadata flag derived from
    // the license, not a Wikidata statement, and nothing in Cirrus's own
    // keyword docs/Phabricator covers it), so unlike every other filter in
    // this method it can't be folded into srsearch. It's applied as a
    // client-side post-filter instead — see _matchesAttribution and its
    // call site in _fetchSingleAttempt below. Still surfaced as a chip
    // here so it appears in the active filters bar like everything else.
    if (state.attributionRequired != null) {
      chips.add(QueryChipData(
        id: 'attributionRequired',
        label: state.attributionRequired!
            ? 'Attribution required'
            : 'No attribution required',
      ));
    }

    if (state.qualityFilter != QualityFilter.any) {
      final clause = _qualityClauses[state.qualityFilter];
      if (clause != null) {
        parts.add(clause);
        chips.add(QueryChipData(
          id: 'quality',
          label: qualityFilterLabel(state.qualityFilter),
        ));
      }
    }

    if (state.minWidth != null && state.minWidth! > 0) {
      parts.add('filew:>${state.minWidth}');
      chips.add(QueryChipData(
        id: 'minWidth',
        label: 'Width ≥ ${state.minWidth}px',
      ));
    }
    if (state.minHeight != null && state.minHeight! > 0) {
      parts.add('fileh:>${state.minHeight}');
      chips.add(QueryChipData(
        id: 'minHeight',
        label: 'Height ≥ ${state.minHeight}px',
      ));
    }
    if (state.maxWidth != null && state.maxWidth! > 0) {
      parts.add('filew:<${state.maxWidth}');
      chips.add(QueryChipData(
        id: 'maxWidth',
        label: 'Width ≤ ${state.maxWidth}px',
      ));
    }
    if (state.maxHeight != null && state.maxHeight! > 0) {
      parts.add('fileh:<${state.maxHeight}');
      chips.add(QueryChipData(
        id: 'maxHeight',
        label: 'Height ≤ ${state.maxHeight}px',
      ));
    }

    // filesize: — always raw bytes on the wire; a UI can offer MB/KB and
    // convert before this point, but this method never guesses at units.
    if (state.minFileSizeBytes != null && state.minFileSizeBytes! > 0) {
      parts.add('filesize:>${state.minFileSizeBytes}');
      chips.add(QueryChipData(
        id: 'minFileSize',
        label: 'Size ≥ ${_formatBytes(state.minFileSizeBytes!)}',
      ));
    }
    if (state.maxFileSizeBytes != null && state.maxFileSizeBytes! > 0) {
      parts.add('filesize:<${state.maxFileSizeBytes}');
      chips.add(QueryChipData(
        id: 'maxFileSize',
        label: 'Size ≤ ${_formatBytes(state.maxFileSizeBytes!)}',
      ));
    }

    if (state.colorDepthBits != null && state.colorDepthBits! > 0) {
      parts.add('filebits:${state.colorDepthBits}');
      chips.add(QueryChipData(
        id: 'colorDepth',
        label: '${state.colorDepthBits}-bit color depth',
      ));
    }

    // hastemplate: generalized beyond the hardcoded QualityFilter presets
    // further down — GLAM/institutional sets, granular PD templates, or
    // anything else a template marks. Quoted whenever the name contains a
    // space, same convention as excludeTerms below.
    for (final template in state.templates.toList()..sort()) {
      final safe = template.trim();
      if (safe.isEmpty) continue;
      final token = safe.contains(' ') ? '"$safe"' : safe;
      parts.add('hastemplate:$token');
      chips.add(QueryChipData(id: 'template:$safe', label: 'Template: $safe'));
    }
    for (final template in state.excludeTemplates.toList()..sort()) {
      final safe = template.trim();
      if (safe.isEmpty) continue;
      final token = safe.contains(' ') ? '"$safe"' : safe;
      parts.add('-hastemplate:$token');
      chips.add(QueryChipData(
          id: 'excludeTemplate:$safe', label: 'Not template: $safe'));
    }

    // Union mode for depicts — same pattern and same reasoning as
    // categoriesUnion/statementsUnion: this is a preview join for the
    // display query / chips, real OR execution happens via per-entity
    // fan-out in _fetchPageForDepicts further down.
    final includeDepicts = state.depictsInclude.toList()
      ..sort((a, b) => a.qid.compareTo(b.qid));

    if (state.depictsUnion && includeDepicts.length > 1) {
      final clauses =
          includeDepicts.map((e) => 'haswbstatement:P180=${e.qid}').toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final entity in includeDepicts) {
        parts.add('haswbstatement:P180=${entity.qid}');
      }
    }
    for (final entity in includeDepicts) {
      chips.add(QueryChipData(
        id: 'depicts:${entity.qid}',
        label: 'Depicts: ${entity.label}',
      ));
    }

    for (final entity in state.depictsExclude.toList()
      ..sort((a, b) => a.qid.compareTo(b.qid))) {
      parts.add('-haswbstatement:P180=${entity.qid}');
      chips.add(QueryChipData(
        id: 'excludeDepicts:${entity.qid}',
        label: 'Not depicting: ${entity.label}',
      ));
    }

    // Generalized Wikidata property search — same haswbstatement: mechanism
    // as depicts (P180) above, but for any property the user picks. P180
    // and P275 (license) are deliberately excluded from the property picker
    // itself (see searchWikidataProperties) so this set can never overlap
    // or contradict depictsInclude/Exclude or licensePresets.
    //
    // Union mode (OR) is NOT expressed as a single "A OR B" query string
    // here — mixed with other required clauses (category, license, etc.),
    // Cirrus's OR only binds to its immediately adjacent term, same
    // precedence hazard as the "+"-query bug elsewhere in this file. The
    // real OR execution happens via per-statement fan-out in fetchPage
    // below; this join is just an honest preview of intent.
    final includeStatements = state.statementsInclude.toList()
      ..sort((a, b) => '${a.property.qid}${a.value.qid}'
          .compareTo('${b.property.qid}${b.value.qid}'));

    if (state.statementsUnion && includeStatements.length > 1) {
      final clauses = includeStatements
          .map((s) => 'haswbstatement:${s.property.qid}=${s.value.qid}')
          .toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final stmt in includeStatements) {
        parts.add('haswbstatement:${stmt.property.qid}=${stmt.value.qid}');
      }
    }
    for (final stmt in includeStatements) {
      chips.add(QueryChipData(
        id: 'statement:${stmt.property.qid}:${stmt.value.qid}',
        label: '${stmt.property.label}: ${stmt.value.label}',
      ));
    }

    for (final stmt in state.statementsExclude.toList()
      ..sort((a, b) => '${a.property.qid}${a.value.qid}'
          .compareTo('${b.property.qid}${b.value.qid}'))) {
      parts.add('-haswbstatement:${stmt.property.qid}=${stmt.value.qid}');
      chips.add(QueryChipData(
        id: 'excludeStatement:${stmt.property.qid}:${stmt.value.qid}',
        label: 'Not ${stmt.property.label}: ${stmt.value.label}',
      ));
    }

    if (state.nearCoord != null) {
      final coord = state.nearCoord!;
      final radius = coord.radiusKm.toStringAsFixed(0);
      parts.add('nearcoord:${radius}km,${coord.lat},${coord.lng}');
      chips.add(QueryChipData(
        id: 'nearCoord',
        label: 'Near ${coord.lat.toStringAsFixed(3)}, '
            '${coord.lng.toStringAsFixed(3)} (${radius}km)',
      ));
    } else if (state.nearTitle != null) {
      final nt = state.nearTitle!;
      final radius = nt.radiusKm.toStringAsFixed(0);
      parts.add('neartitle:"${radius}km,${nt.title}"');
      chips.add(QueryChipData(
        id: 'nearTitle',
        label: 'Near "${nt.title}" (${radius}km)',
      ));
    }

    for (final term in state.excludeTerms.toList()..sort()) {
      final safe = term.trim();
      if (safe.isEmpty) continue;
      final needsQuotes = safe.contains(' ');
      final token = needsQuotes ? '"$safe"' : safe;
      parts.add('-$token');
      chips.add(QueryChipData(id: 'exclude:$safe', label: 'Exclude: $safe'));
    }

    // morelike: — "files similar to these" via CirrusSearch's own
    // similarity engine. Combines with every other clause above (AND),
    // same as everything else in this method; it's just one more term in
    // the joined query string, not a special standalone request.
    final morelike = state.morelikeTitles
        .map((t) {
          final trimmed = t.trim();
          if (trimmed.isEmpty) return '';
          return trimmed.startsWith('File:') ? trimmed : 'File:$trimmed';
        })
        .where((t) => t.isNotEmpty)
        .toList()
      ..sort();
    if (morelike.isNotEmpty) {
      parts.add('morelike:${morelike.join('|')}');
      chips.add(QueryChipData(
        id: 'morelike',
        label: morelike.length == 1
            ? 'Similar to: ${morelike.first.replaceFirst('File:', '')}'
            : 'Similar to ${morelike.length} files',
      ));
    }

    // insource: — matches the file description page's raw wikitext, a
    // different corpus than the analyzed/indexed text `queryText` matches
    // against. Regex mode uses insource:/.../, literal mode wraps in
    // quotes the same way excludeTerms does above.
    final insource = state.insourceText?.trim() ?? '';
    if (insource.isNotEmpty) {
      final token =
          state.insourceRegex ? 'insource:/$insource/' : 'insource:"$insource"';
      parts.add(token);
      chips.add(QueryChipData(id: 'insource', label: 'Source: $insource'));
    }

    final srsearch = parts.join(' ').trim();

    return QueryBuildResult(
      srsearch: srsearch,
      chips: chips,
      debugPreview: srsearch,
    );
  }

  String _getMimeString(FileFormat format) {
    switch (format) {
      case FileFormat.jpg:
      case FileFormat.jpeg:
        return 'image/jpeg';
      case FileFormat.png:
        return 'image/png';
      case FileFormat.svg:
        return 'image/svg+xml';
      case FileFormat.gif:
        return 'image/gif';
      case FileFormat.tif:
      case FileFormat.tiff:
        return 'image/tiff';
      case FileFormat.webp:
        return 'image/webp';
      case FileFormat.pdf:
        return 'application/pdf';
      case FileFormat.djvu:
        return 'image/vnd.djvu';
      case FileFormat.ogg:
      case FileFormat.oga:
        return 'audio/ogg';
      case FileFormat.ogv:
        return 'video/ogg';
      case FileFormat.mp3:
        return 'audio/mpeg';
      case FileFormat.wav:
        return 'audio/wav';
      case FileFormat.webm:
        return 'video/webm';
      case FileFormat.mp4:
        return 'video/mp4';
    }
  }
}
