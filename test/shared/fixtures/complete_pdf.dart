import 'dart:convert';

/// Complete one-page PDF with byte-correct xref offsets. Unlike signature-only
/// fixtures this can also be used by the native open proof.
List<int> completePdfFixtureBytes() {
  final text = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  final stream = 'BT /F1 18 Tf 32 64 Td (Mknoon PDF fixture) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 120] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${ascii.encode(stream).length} >>\nstream\n${stream}endstream',
  ];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(ascii.encode(text.toString()).length);
    text.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = ascii.encode(text.toString()).length;
  text.write('xref\n0 ${offsets.length}\n0000000000 65535 f \n');
  for (final offset in offsets.skip(1)) {
    text.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  text.write(
    'trailer\n<< /Size ${offsets.length} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return ascii.encode(text.toString());
}
