import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

/// Everything about opening a person's own EPUB, on their own device.
///
/// The app never hosts or relays a book: each person opens a file they
/// already have (DRM-free), and the room only keeps *where everybody is*. For
/// that to mean anything, "chapter 4, paragraph 17" has to be the same place
/// on every phone holding the same file — so this reads an EPUB into plain
/// blocks **deterministically**: the same bytes always give the same chapters
/// and the same paragraph numbers, on any device, in any order.
///
/// What is kept: headings, paragraphs, quotes, scene breaks. What is not:
/// images, tables' layout, fonts and the book's own styling — the text is
/// drawn in the app's own soft reading style, which is also what lets every
/// theme (light, dark, clay…) read comfortably.

/// One drawn piece of a chapter.
class BookBlock {
  final String text;

  /// 0 paragraph · 1..3 heading · -1 scene break.
  final int level;
  final bool quote;
  const BookBlock(this.text, {this.level = 0, this.quote = false});

  bool get isHeading => level > 0;
  bool get isBreak => level < 0;
}

class BookChapter {
  /// The chapter's own heading, when its first block is one.
  final String? title;
  final List<BookBlock> blocks;
  const BookChapter(this.title, this.blocks);
}

class BookContent {
  final String title;
  final String? author;
  final List<BookChapter> chapters;

  /// `_before[i]` = how many blocks come before chapter i (for the progress of
  /// a place in the whole book).
  final List<int> _before;
  final int totalBlocks;

  BookContent._(this.title, this.author, this.chapters, this._before, this.totalBlocks);

  factory BookContent(String title, String? author, List<BookChapter> chapters) {
    final before = <int>[];
    var running = 0;
    for (final c in chapters) {
      before.add(running);
      running += c.blocks.length;
    }
    return BookContent._(title, author, chapters, before, running);
  }

  /// 0..1 through the whole book at a place.
  double fractionAt(int chapter, int block) {
    if (totalBlocks <= 0 || chapters.isEmpty) return 0;
    final c = chapter.clamp(0, chapters.length - 1);
    final b = block.clamp(0, math.max(0, chapters[c].blocks.length - 1));
    return ((_before[c] + b) / totalBlocks).clamp(0.0, 1.0);
  }
}

/// What parsing in the background hands back: either a book or a reason.
/// (A plain value rather than a thrown error, so nothing depends on how an
/// exception crosses the isolate boundary.)
class BookParseResult {
  final BookContent? content;

  /// `drm` · `empty` · `broken`
  final String? error;
  const BookParseResult.ok(BookContent this.content) : error = null;
  const BookParseResult.failed(String this.error) : content = null;
}

/// A book that could not be opened, with something kind to tell the person.
class BookOpenException implements Exception {
  final String code; // drm | empty | broken | missing
  const BookOpenException(this.code);

  @override
  String toString() => 'BookOpenException($code)';
}

/// An opened file: where it is, its fingerprint, and what is in it.
class LocalBook {
  final String path;
  final String hash;
  final BookContent content;
  const LocalBook({required this.path, required this.hash, required this.content});
}

/// SHA-256 of a file, streamed (a big file is never held in memory for this).
Future<String> fileSha256(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

Future<LocalBook> openEpubFile(String path) async {
  final file = File(path);
  if (!await file.exists()) throw const BookOpenException('missing');
  final hash = await fileSha256(path);
  final bytes = await file.readAsBytes();
  final result = await compute(parseEpubBytes, bytes);
  final content = result.content;
  if (content == null) throw BookOpenException(result.error ?? 'broken');
  return LocalBook(path: path, hash: hash, content: content);
}

// --- parsing --------------------------------------------------------------

const _fontObfuscation = {
  'http://www.idpf.org/2008/embedding',
  'http://ns.adobe.com/pdf/enc#RC',
};

const _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'ul', 'ol', 'li', 'dl', 'dt', 'dd',
  'table', 'thead', 'tbody', 'tr', 'td', 'th', 'figure', 'figcaption', 'pre', 'aside',
  'header', 'footer', 'main', 'body', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr',
};

final RegExp _headingTag = RegExp(r'^h([1-6])$');
final RegExp _spaces = RegExp(r'\s+');

/// Top-level so it can run in a background isolate (`compute`).
BookParseResult parseEpubBytes(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{};
    final lower = <String, ArchiveFile>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      files[name] = f;
      lower[name.toLowerCase()] = f;
    }
    ArchiveFile? find(String path) => files[path] ?? lower[path.toLowerCase()];
    String textOf(ArchiveFile f) {
      // archive 4.x: readBytes() is Uint8List? (null when the entry has no
      // content), so an empty entry reads as an empty string.
      final s = utf8.decode(f.readBytes() ?? const <int>[], allowMalformed: true);
      return s.startsWith('\uFEFF') ? s.substring(1) : s;
    }

    // Protected books can't be opened; font obfuscation is not protection.
    final enc = find('META-INF/encryption.xml');
    if (enc != null) {
      try {
        final doc = XmlDocument.parse(textOf(enc));
        for (final m in doc.findAllElements('EncryptionMethod')) {
          if (!_fontObfuscation.contains(m.getAttribute('Algorithm'))) {
            return const BookParseResult.failed('drm');
          }
        }
      } catch (_) {
        // A malformed encryption file proves nothing; carry on.
      }
    }

    final container = find('META-INF/container.xml');
    if (container == null) return const BookParseResult.failed('broken');
    final rootfile = XmlDocument.parse(textOf(container)).findAllElements('rootfile').firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path');
    if (opfPath == null) return const BookParseResult.failed('broken');
    final opfFile = find(opfPath);
    if (opfFile == null) return const BookParseResult.failed('broken');
    final opf = XmlDocument.parse(textOf(opfFile));

    String? meta(String name) {
      final el = opf.findAllElements(name).firstOrNull;
      final t = el?.innerText.replaceAll(_spaces, ' ').trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final title = meta('dc:title') ?? meta('title') ?? '';
    final author = meta('dc:creator') ?? meta('creator');

    final manifest = <String, ({String href, String type})>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (href: href, type: item.getAttribute('media-type') ?? '');
    }

    final opfDir = opfPath.contains('/') ? opfPath.substring(0, opfPath.lastIndexOf('/')) : '';
    final chapters = <BookChapter>[];
    for (final ref in opf.findAllElements('itemref')) {
      if (ref.getAttribute('linear') == 'no') continue;
      final item = manifest[ref.getAttribute('idref')];
      if (item == null) continue;
      if (item.type != 'application/xhtml+xml' && item.type != 'text/html') continue;
      final file = find(_resolve(opfDir, item.href));
      if (file == null) continue;
      final blocks = _blocksOf(textOf(file));
      if (blocks.isEmpty) continue; // covers, image pages, an empty nav
      final first = blocks.first;
      final heading = (first.isHeading && first.text.length <= 90) ? first.text : null;
      chapters.add(BookChapter(heading, blocks));
    }
    if (chapters.isEmpty) return const BookParseResult.failed('empty');
    return BookParseResult.ok(BookContent(title, author, chapters));
  } catch (_) {
    return const BookParseResult.failed('broken');
  }
}

/// `dir` + a manifest href (percent-encoded, maybe with `../` and a #fragment).
String _resolve(String dir, String href) {
  final clean = Uri.decodeFull(href.split('#').first);
  final parts = <String>[];
  for (final p in [if (dir.isNotEmpty) ...dir.split('/'), ...clean.split('/')]) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(p);
    }
  }
  return parts.join('/');
}

List<BookBlock> _blocksOf(String source) {
  final document = html_parser.parse(source);
  final body = document.body;
  if (body == null) return const [];
  final out = <BookBlock>[];
  _collect(body, out, quote: false);
  return out;
}

String _clean(String s) => s.replaceAll('\u00A0', ' ').replaceAll(_spaces, ' ').trim();

String _inlineText(dom.Node node) {
  final b = StringBuffer();
  void walk(dom.Node n) {
    if (n is dom.Text) {
      b.write(n.data);
    } else if (n is dom.Element) {
      final tag = n.localName;
      if (tag == 'br') {
        b.write(' ');
      } else if (tag == 'script' || tag == 'style') {
        return;
      } else {
        for (final c in n.nodes) {
          walk(c);
        }
      }
    }
  }

  walk(node);
  return _clean(b.toString());
}

bool _hasBlockDescendant(dom.Element el) {
  for (final c in el.children) {
    if (_blockTags.contains(c.localName)) return true;
    if (_hasBlockDescendant(c)) return true;
  }
  return false;
}

void _collect(dom.Element root, List<BookBlock> out, {required bool quote}) {
  final pending = StringBuffer();
  void flush() {
    final t = _clean(pending.toString());
    pending.clear();
    if (t.isNotEmpty) out.add(BookBlock(t, quote: quote));
  }

  for (final node in root.nodes) {
    if (node is dom.Text) {
      pending.write(node.data);
      continue;
    }
    if (node is! dom.Element) continue;
    final tag = node.localName ?? '';
    if (tag == 'script' || tag == 'style' || tag == 'head' || tag == 'nav') continue;
    if (tag == 'br') {
      pending.write(' ');
      continue;
    }
    if (tag == 'img' || tag == 'svg' || tag == 'image') continue;
    if (tag == 'hr') {
      flush();
      out.add(const BookBlock('', level: -1));
      continue;
    }
    final heading = _headingTag.firstMatch(tag);
    if (heading != null) {
      flush();
      final t = _inlineText(node);
      if (t.isNotEmpty) out.add(BookBlock(t, level: math.min(3, int.parse(heading.group(1)!))));
      continue;
    }
    if (!_blockTags.contains(tag)) {
      pending.write(_inlineText(node)); // an inline element sitting at block level
      continue;
    }
    flush();
    final isQuote = quote || tag == 'blockquote';
    if (_hasBlockDescendant(node)) {
      _collect(node, out, quote: isQuote);
    } else {
      final t = _inlineText(node);
      if (t.isNotEmpty) out.add(BookBlock(t, quote: isQuote));
    }
  }
  flush();
}
