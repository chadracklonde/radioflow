import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/conductor_models.dart';

String conductorExportName(Conductor c) {
  final safe = c.title
      .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'RadioFlow_Conducteur_${DateFormat('yyyy-MM-dd').format(c.broadcastDate)}_$safe.pdf';
}

/// Conducteur imprimable pour la régie : une ligne par élément, avec durées et statuts.
Future<Uint8List> buildConductorPdf(
  Conductor conductor,
  List<ConductorLine> lines,
  Map<String, int> soundSeconds,
) async {
  final timing = ConductorTiming.compute(lines, soundSeconds);
  final doc = pw.Document(title: 'Radio Flow - Conducteur');
  final day = DateFormat('dd/MM/yyyy').format(conductor.broadcastDate);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text(
          '${conductor.title}${conductor.broadcastTime != null ? ' - ${conductor.broadcastTime}' : ''}',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Date : $day - Statut : ${conductor.status.label}'),
        pw.Text(
          'Duree prevue ${formatDuration(timing.planned)} - '
          'duree estimee ${formatDuration(timing.estimated)} '
          '(${timing.withSound}/${timing.counted} lignes avec son)',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['N°', 'Type', 'Titre', 'Statut', 'Prevu', 'Son'],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey800,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          data: [
            for (final l in lines)
              [
                l.position.toString().padLeft(2, '0'),
                l.itemType.label,
                l.title,
                l.status.label,
                l.plannedDuration == null
                    ? ''
                    : formatDuration(l.plannedDuration!),
                soundSeconds[l.id] == null
                    ? ''
                    : formatDuration(soundSeconds[l.id]!),
              ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Genere le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
        ),
      ],
    ),
  );
  return doc.save();
}
