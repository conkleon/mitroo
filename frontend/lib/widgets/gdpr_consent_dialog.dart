import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GdprConsentDialog extends StatefulWidget {
  final Future<void> Function() onAccept;
  final VoidCallback onDecline;

  const GdprConsentDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  State<GdprConsentDialog> createState() => _GdprConsentDialogState();
}

class _GdprConsentDialogState extends State<GdprConsentDialog> {
  bool _showEnglish = false;
  bool _accepting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Πολιτική Απορρήτου',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _showEnglish ? _englishText : _greekText,
                style: GoogleFonts.inter(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showEnglish = !_showEnglish),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: Text(
                  _showEnglish
                      ? 'Εμφάνιση στα Ελληνικά'
                      : 'Show in English',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF6B7280),
                    decoration: TextDecoration.underline,
                    decorationColor: const Color(0xFF6B7280),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onDecline,
          child: Text(
            'Δεν αποδέχομαι',
            style: GoogleFonts.inter(color: const Color(0xFF6B7280)),
          ),
        ),
        FilledButton(
          onPressed: _accepting
              ? null
              : () async {
                  setState(() => _accepting = true);
                  await widget.onAccept();
                },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFC62828),
          ),
          child: Text(
            'Αποδέχομαι',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

const _greekText =
    'Η εφαρμογή Mitroo συλλέγει και επεξεργάζεται τα προσωπικά σας δεδομένα '
    '(ονοματεπώνυμο, email, τηλέφωνο, διεύθυνση, ημερομηνία γέννησης, ειδικότητες) '
    'αποκλειστικά για τη διαχείριση αποστολών και πόρων του Ελληνικού Ερυθρού Σταυρού. '
    'Τα δεδομένα αποθηκεύονται σε ασφαλείς διακομιστές και δεν κοινοποιούνται σε τρίτους '
    'εκτός Ε.Ε.Σ. Έχετε δικαίωμα πρόσβασης, διόρθωσης και διαγραφής των δεδομένων σας '
    'επικοινωνώντας με τον διαχειριστή. Με την αποδοχή, συναινείτε στην επεξεργασία των '
    'δεδομένων σας σύμφωνα με τον ΓΚΠΔ (Κανονισμός ΕΕ 2016/679).';

const _englishText =
    'The Mitroo application collects and processes your personal data '
    '(name, email, phone, address, date of birth, specializations) solely for mission '
    'and resource management within the Hellenic Red Cross. Data is stored on secure '
    'servers and is not shared with third parties outside H.R.C. You have the right to '
    'access, correct, and delete your data by contacting the administrator. By accepting, '
    'you consent to the processing of your data in accordance with the GDPR '
    '(EU Regulation 2016/679).';
