import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'templates.dart';

// Fonts are bundled assets; load each once. Space Grotesk has the glyphs for $ € £ ₹ ¥ × − · (checked with fontTools).
// Syne ExtraBold has no ₹, so it is only used for the plain-ASCII word INVOICE / QUOTATION, never for money.
final _fonts = <String, Future<pw.Font>>{};
Future<pw.Font> _font(String f) => _fonts.putIfAbsent(f, () async => pw.Font.ttf(await rootBundle.load('assets/fonts/$f.ttf')));

/// File name used when sharing or saving, safe on every file system: INV-2026-001.pdf
String pdfFileName(Doc d) {
  final base = d.number.trim().isEmpty ? (d.isInvoice ? 'invoice' : 'quotation') : d.number.trim();
  return '${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')}.pdf';
}

PdfColor _hex(int rgb) => PdfColor.fromInt(0xFF000000 | rgb);

/// Renders an invoice or quotation to PDF bytes from the live profile and client, in the document's template.
Future<Uint8List> buildPdf(Doc d) async {
  final p = store.profile;
  final c = store.client(d.clientId);
  final project = store.project(d.projectId);
  final tpl = templateOf(d);
  final look = tpl.look; // 'classic' | 'band' | 'minimal'
  final display = await _font('Syne-ExtraBold');
  final ink = PdfColor.fromHex('#16140F');
  final grey = PdfColor.fromHex('#6B6455');
  final accent = _hex(tpl.accent);
  final onBand = PdfColor.fromHex('#EEF3F2'); // text on the colour band
  final small = pw.TextStyle(fontSize: 9, color: grey);
  final label = pw.TextStyle(fontSize: 8, color: grey, letterSpacing: 1.5, fontWeight: pw.FontWeight.bold);
  final kindWord = d.isInvoice ? 'INVOICE' : 'QUOTATION';

  final biz = p.bizName.trim().isNotEmpty ? p.bizName.trim() : p.ownerName.trim();
  final taxId = p.taxId.trim();
  final paid = d.isInvoice && d.status == 'paid';
  final upiId = p.upi.replaceAll(RegExp(r'\s'), '');
  final showUpi = upiId.isNotEmpty && p.currency == '₹' && d.isInvoice && !paid && d.total > 0;
  final bankLines = p.bank.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final showBank = d.isInvoice && !paid && bankLines.isNotEmpty;
  final cTax = c?.gstin.trim() ?? '';

  pw.Widget block(String title, List<String> lines) {
    final shown = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(title, style: label),
      pw.SizedBox(height: 4),
      for (final (i, l) in shown.indexed)
        pw.Text(l, style: i == 0 ? pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold) : small),
    ]);
  }

  pw.Widget totalRow(String a, String b) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [pw.Expanded(child: pw.Text(a, style: small)), pw.SizedBox(width: 8), pw.Text(b)]),
      );

  // ---- the business block (right side of every header)
  final bizLines = [
    if (p.bizName.trim().isNotEmpty && p.ownerName.trim().isNotEmpty) p.ownerName.trim(),
    p.address.trim(),
    p.email.trim(),
    p.phone.trim(),
    if (taxId.isNotEmpty) 'Tax ID: $taxId',
  ].where((l) => l.isNotEmpty).toList();
  pw.Widget bizBlock({PdfColor? nameColor, PdfColor? lineColor}) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        if (biz.isNotEmpty) pw.Text(biz, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: nameColor), textAlign: pw.TextAlign.right),
        for (final l in bizLines) pw.Text(l, style: pw.TextStyle(fontSize: 9, color: lineColor ?? grey), textAlign: pw.TextAlign.right),
      ]);
  final paidMark = paid
      ? pw.Text('PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColor.fromHex('#2F7D5B'), letterSpacing: 2))
      : null;

  pw.Widget header() {
    switch (look) {
      case 'band':
        return pw.Container(
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(color: accent, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(kindWord, style: pw.TextStyle(font: display, fontSize: kindWord.length > 8 ? 21 : 30, color: PdfColors.white)),
                pw.SizedBox(height: 6),
                pw.Text(d.number, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                if (d.title.trim().isNotEmpty)
                  pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(d.title.trim(), style: pw.TextStyle(fontSize: 9, color: onBand))),
                if (paid)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: pw.Text('PAID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.white, letterSpacing: 2)),
                  ),
              ]),
            ),
            pw.SizedBox(width: 16),
            pw.Flexible(child: bizBlock(nameColor: PdfColors.white, lineColor: onBand)),
          ]),
        );
      case 'minimal':
        return pw.Column(children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(kindWord, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 4, color: ink)),
                pw.SizedBox(height: 4),
                pw.Text(d.number, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                if (d.title.trim().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(d.title.trim(), style: small)),
                if (paidMark != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: paidMark),
              ]),
            ),
            pw.SizedBox(width: 16),
            pw.Flexible(child: bizBlock()),
          ]),
          pw.SizedBox(height: 12),
          pw.Divider(thickness: .8, color: ink, height: 1),
        ]);
      default: // classic, unchanged
        return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(kindWord, style: pw.TextStyle(font: display, fontSize: 34, color: ink)),
              pw.Container(width: 60, height: 6, color: accent, margin: const pw.EdgeInsets.only(top: 6, bottom: 8)),
              pw.Text(d.number, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (d.title.trim().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(d.title.trim(), style: small)),
              if (paidMark != null) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: paidMark),
            ]),
          ),
          pw.SizedBox(width: 16),
          pw.Flexible(child: bizBlock()),
        ]);
    }
  }

  // ---- tables share one look per template
  pw.Widget table(List<String> headers, List<List<String>> rows,
      {Map<int, pw.TableColumnWidth>? widths, Map<int, pw.Alignment>? aligns, double fontSize = 10}) {
    final minimal = look == 'minimal';
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: null,
      headerStyle: pw.TextStyle(color: minimal ? ink : PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9, letterSpacing: 1),
      headerDecoration: minimal
          ? pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: ink, width: .8)))
          : pw.BoxDecoration(color: look == 'band' ? accent : ink),
      cellStyle: pw.TextStyle(fontSize: fontSize),
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      oddRowDecoration: minimal ? null : pw.BoxDecoration(color: PdfColor.fromHex('#F4F1EA')),
      rowDecoration: minimal ? pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: .4))) : null,
      columnWidths: widths,
      cellAlignments: aligns,
    );
  }

  pw.Widget totalBox() {
    final text = d.isInvoice ? (paid ? 'PAID' : 'AMOUNT DUE') : 'TOTAL';
    if (look == 'minimal') {
      return pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: ink, width: .8))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text(text, style: pw.TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(width: 8),
          pw.Expanded(child: pw.Text(money(d.total), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16))),
        ]),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: look == 'band' ? accent : ink, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text(text, style: pw.TextStyle(color: PdfColors.white, fontSize: 9, letterSpacing: 1.5)),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Text(money(d.total), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 16)),
        ),
      ]),
    );
  }

  // ---- a quotation's sections, payment schedule and signature block
  final titleColor = look == 'minimal' ? ink : accent;
  pw.Widget sectionTitle(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5, color: titleColor)),
      );

  List<pw.Widget> sectionWidgets(DocSection sec) {
    final blocks = parseBlocks(sec.body);
    final widgets = <pw.Widget>[];
    for (final (i, b) in blocks.indexed) {
      final w = switch (b) {
        ParaBlock() => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(b.text, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2))),
        BulletsBlock() => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            for (final it in b.items)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.SizedBox(width: 12, child: pw.Text('•', style: const pw.TextStyle(fontSize: 10))),
                  pw.Expanded(child: pw.Text(it, style: const pw.TextStyle(fontSize: 10, lineSpacing: 2))),
                ]),
              ),
            pw.SizedBox(height: 2),
          ]),
        TableBlock() => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: table(
              b.header,
              [for (final r in b.rows) [...r, ...List.filled((b.header.length - r.length).clamp(0, 99), '')].take(b.header.length).toList()],
              fontSize: 9,
            ),
          ),
      };
      if (i == 0) {
        final small = switch (b) { ParaBlock() => true, BulletsBlock() => b.items.length <= 8, TableBlock() => b.rows.length <= 6 };
        final group = pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [sectionTitle(sec.title), w]);
        // a Column may be split across pages; Inseparable keeps title and first block together, so no title is stranded at the foot of a page
        widgets.add(small ? pw.Inseparable(child: group) : group);
      } else {
        widgets.add(w);
      }
    }
    if (blocks.isEmpty) widgets.add(sectionTitle(sec.title));
    return widgets;
  }

  pw.Widget signature(String who) => pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(who, style: label),
          pw.SizedBox(height: 36),
          pw.Divider(thickness: .6, color: grey, height: 1),
          pw.SizedBox(height: 3),
          pw.Text('Name, signature and date', style: small),
        ]),
      );

  final pdf = pw.Document(
    title: d.number,
    author: biz,
    theme: pw.ThemeData.withFont(base: await _font('SpaceGrotesk-Regular'), bold: await _font('SpaceGrotesk-Bold')),
  );
  final scheduleSums = scheduleAmounts(d);
  final detailed = !d.isInvoice && (d.sections.isNotEmpty || d.schedule.isNotEmpty);
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(40),
    // Pages after the first carry a slim header so a loose sheet can always be identified.
    header: (ctx) => ctx.pageNumber == 1
        ? pw.SizedBox()
        : pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: .5))),
            child: pw.Row(children: [
              pw.Text('$kindWord ${d.number}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Spacer(),
              if (d.title.trim().isNotEmpty) pw.Flexible(child: pw.Text(d.title.trim(), style: small, maxLines: 1)),
            ]),
          ),
    footer: (ctx) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(children: [
        pw.Expanded(child: pw.Text(biz.isEmpty ? d.number : '$biz  ·  ${d.number}', style: small, maxLines: 1)),
        pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: small),
      ]),
    ),
    build: (_) => [
      header(),
      pw.SizedBox(height: 30),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: block(d.isInvoice ? 'BILL TO' : 'PREPARED FOR', [
            if (c == null) 'Client not specified' else c.name,
            if (c != null) ...[c.company, c.address, c.email, c.phone, if (cTax.isNotEmpty) 'Tax ID: $cTax'],
          ]),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: block('DETAILS', [
            if (project != null) project.name,
            'Date: ${fmtDate(d.date)}',
            '${d.isInvoice ? 'Due' : 'Valid until'}: ${fmtDate(d.due)}',
            if (d.isInvoice && d.terms.trim().isNotEmpty) 'Terms: ${d.terms.trim()}',
          ]),
        ),
      ]),
      pw.SizedBox(height: 26),
      if (d.items.isEmpty)
        pw.Text('No line items.', style: small)
      else
        table(
          ['#', 'DESCRIPTION', 'QTY', 'RATE', 'AMOUNT'],
          [for (final (i, it) in d.items.indexed) ['${i + 1}', it.desc.trim(), _qty(it), money(it.rate), money(it.amount)]],
          widths: {
            0: const pw.FixedColumnWidth(24),
            1: const pw.FlexColumnWidth(3.2),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.6),
          },
          aligns: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight
          },
        ),
      pw.SizedBox(height: 16),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (showUpi)
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(biz.isEmpty ? 'Payee' : biz)}'
                      '&am=${d.total.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent(d.number)}',
                  width: 84,
                  height: 84,
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(child: block('SCAN TO PAY', ['UPI', upiId])),
              ]),
            if (showUpi && showBank) pw.SizedBox(height: 12),
            if (showBank) block('BANK TRANSFER', bankLines),
          ]),
        ),
        pw.SizedBox(width: 20),
        pw.SizedBox(
          width: 220,
          child: pw.Column(children: [
            totalRow('Subtotal', money(d.subtotal)),
            if (d.discount > 0) totalRow('Discount (${_n(d.discount)}%)', '- ${money(d.discountAmount)}'),
            if (d.taxPct > 0) totalRow('Tax (${_n(d.taxPct)}%)', money(d.tax)),
            pw.SizedBox(height: 8),
            totalBox(),
          ]),
        ),
      ]),
      if (!d.isInvoice && d.schedule.isNotEmpty) ...[
        pw.SizedBox(height: 24),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sectionTitle('Payment schedule'),
          table(
            ['#', 'DUE', 'SHARE', 'AMOUNT'],
            [for (final (i, m) in d.schedule.indexed) ['${i + 1}', m.label.trim(), '${_n(m.pct)}%', money(scheduleSums[i])]],
            widths: {
              0: const pw.FixedColumnWidth(24),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.6),
            },
            aligns: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),
        ]),
      ],
      for (final sec in d.sections) ...[pw.SizedBox(height: 18), ...sectionWidgets(sec)],
      if (d.notes.trim().isNotEmpty) ...[
        pw.SizedBox(height: 28),
        pw.Text('NOTES', style: label),
        pw.SizedBox(height: 4),
        pw.Text(d.notes.trim(), style: small),
      ],
      if (detailed) ...[
        pw.SizedBox(height: 30),
        pw.Inseparable(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          sectionTitle('Acceptance'),
          pw.Text('To accept this quotation, sign below or confirm in writing by message or email.', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.Row(children: [signature('ACCEPTED BY${c == null ? '' : ' · ${c.name}'}'), pw.SizedBox(width: 28), signature('FOR${biz.isEmpty ? '' : ' · $biz'}')]),
        ])),
      ],
    ],
  ));
  return pdf.save();
}

/// 2 -> "2", 1.5 -> "1.5", 0.333 -> "0.33".
String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// "2 hrs"; the default unit 'x' reads better as a bare number.
String _qty(LineItem it) => it.unit.trim().isEmpty || it.unit.trim() == 'x' ? _n(it.qty) : '${_n(it.qty)} ${it.unit.trim()}';
