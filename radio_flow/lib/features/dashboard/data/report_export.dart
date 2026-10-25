import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/report.dart';

final _dayFmt = DateFormat('dd/MM/yyyy');

String exportBaseName(DashboardReport r) {
  final f = DateFormat('yyyy-MM-dd');
  return 'RadioFlow_Bilan_${f.format(r.range.from)}_${f.format(r.range.to)}';
}

Uint8List buildXlsx(DashboardReport r) {
  final book = Excel.createExcel();
  final ranking = book['Classement'];
  ranking.appendRow([
    TextCellValue('Rang'),
    TextCellValue('Journaliste'),
    TextCellValue('Sons publiés'),
    TextCellValue('Sujets validés'),
    TextCellValue('Tâches terminées'),
    TextCellValue('Tâches en cours'),
  ]);
  for (var i = 0; i < r.rows.length; i++) {
    final row = r.rows[i];
    ranking.appendRow([
      IntCellValue(i + 1),
      TextCellValue(row.name),
      IntCellValue(row.audioCount),
      IntCellValue(row.approvedProposals),
      IntCellValue(row.tasksDone),
      IntCellValue(row.tasksOpen),
    ]);
  }
  ranking.appendRow([
    TextCellValue(''),
    TextCellValue('Total'),
    IntCellValue(r.totalAudio),
    IntCellValue(r.totalApproved),
    IntCellValue(r.totalDone),
    IntCellValue(r.totalOpen),
  ]);

  final tasks = book['Tâches en cours'];
  tasks.appendRow([
    TextCellValue('Responsable'),
    TextCellValue('Tâche'),
    TextCellValue('Statut'),
    TextCellValue('Échéance'),
  ]);
  for (final t in r.openTasks) {
    tasks.appendRow([
      TextCellValue(t.owner),
      TextCellValue(t.title),
      TextCellValue(t.status),
      TextCellValue(t.due == null ? '' : _dayFmt.format(t.due!)),
    ]);
  }

  final info = book['Période'];
  info.appendRow([TextCellValue('Période'), TextCellValue(r.range.label())]);
  info.appendRow([
    TextCellValue('Généré le'),
    TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(r.generatedAt)),
  ]);

  book.delete('Sheet1');
  return Uint8List.fromList(book.encode()!);
}

Future<Uint8List> buildPdf(DashboardReport r) async {
  final doc = pw.Document(title: 'Radio Flow – Bilan de production');
  final headStyle = pw.TextStyle(
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        pw.Text(
          'Radio Flow – Bilan de production',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Période : ${r.range.label()}'),
        pw.Text(
          'Généré le ${DateFormat('dd/MM/yyyy HH:mm').format(r.generatedAt)}',
          style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Classement des productions',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: [
            'Rang',
            'Journaliste',
            'Sons',
            'Sujets validés',
            'Tâches terminées',
            'Tâches en cours',
          ],
          data: [
            for (var i = 0; i < r.rows.length; i++)
              [
                '${i + 1}',
                r.rows[i].name,
                '${r.rows[i].audioCount}',
                '${r.rows[i].approvedProposals}',
                '${r.rows[i].tasksDone}',
                '${r.rows[i].tasksOpen}',
              ],
            [
              '',
              'Total',
              '${r.totalAudio}',
              '${r.totalApproved}',
              '${r.totalDone}',
              '${r.totalOpen}',
            ],
          ],
          headerStyle: headStyle,
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey800,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {
            0: pw.Alignment.center,
            1: pw.Alignment.centerLeft,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Tâches en cours',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (r.openTasks.isEmpty)
          pw.Text('Aucune tâche en cours.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Responsable', 'Tâche', 'Statut', 'Échéance'],
            data: [
              for (final t in r.openTasks)
                [
                  t.owner,
                  t.title,
                  t.status,
                  t.due == null ? '' : _dayFmt.format(t.due!),
                ],
            ],
            headerStyle: headStyle,
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey800,
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
      ],
    ),
  );
  return doc.save();
}
