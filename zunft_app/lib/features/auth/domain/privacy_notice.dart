/// Privacy notice shown to employees before they join a business, and available later under
/// "Betrieb". It says what the app stores about a person who works in a business.
///
/// IMPORTANT: this is a plain-language draft written from how the app actually behaves. It is
/// NOT legal advice. Have a lawyer (or a data-protection officer) review and complete it - names,
/// addresses, legal bases and retention periods are the business's and Zunft's to fill in - before
/// real employees use the app.
class PrivacyNotice {
  static const title = 'Datenschutzhinweis für Mitarbeiter';

  static const sections = <({String heading, String text})>[
    (
      heading: 'Wer ist verantwortlich?',
      text: 'Verantwortlich für die Daten deiner Arbeit ist der Betrieb, dem du beitrittst. '
          'Zunft stellt dem Betrieb die App als technischen Dienstleister zur Verfügung.',
    ),
    (
      heading: 'Welche Daten werden über dich gespeichert?',
      text: 'Dein Name und deine E-Mail-Adresse, deine Rolle im Betrieb (z.B. Geselle), welchen Aufträgen du zugewiesen bist '
          'und alle Notizen, die du aufnimmst: der gesprochene oder getippte Text, die Sprachaufnahme, das Ergebnis der '
          'automatischen Auswertung, dein Name und der Zeitpunkt. Die App erfasst keinen Standort und keine Arbeitszeit.',
    ),
    (
      heading: 'Wofür?',
      text: 'Um Aufträge zu dokumentieren und daraus Angebote und Rechnungen für den Kunden zu erstellen. '
          'Der Betrieb sieht, wer welche Notiz wann aufgenommen hat.',
    ),
    (
      heading: 'Wer verarbeitet die Daten noch?',
      text: 'Technische Dienstleister im Auftrag: Hosting und Datenbank (Supabase), Spracherkennung (Deepgram) und '
          'Textauswertung durch KI (Google). Deine Sprachaufnahme und der Text werden dafür dorthin übermittelt.',
    ),
    (
      heading: 'Wie lange?',
      text: 'Notizen gehören zur Auftragsdokumentation und bleiben im Betrieb, solange er sie braucht und '
          'Aufbewahrungspflichten es verlangen. Dein Konto löschst du jederzeit selbst; deine Notizen bleiben dann beim '
          'Auftrag, ohne Verbindung zu einem Konto (nur dein Name als Text).',
    ),
    (
      heading: 'Dein Konto gehört dir',
      text: 'Du meldest dich mit deiner eigenen E-Mail an. Der Betrieb kann deinen Zugang zu seinen Daten beenden, '
          'aber nicht dein Konto. Du kannst den Betrieb jederzeit verlassen oder dein Konto löschen, '
          'und mit deinem Konto einen eigenen Betrieb gründen.',
    ),
    (
      heading: 'Deine Rechte',
      text:
          'Du hast das Recht auf Auskunft, Berichtigung und Löschung deiner Daten, auf Einschränkung der Verarbeitung '
              'und auf Beschwerde bei einer Datenschutzaufsichtsbehörde. Wende dich dazu an den Betrieb.',
    ),
  ];

  /// The notice as one text (for tests and copying).
  static String get fullText => [for (final s in sections) '${s.heading}\n${s.text}'].join('\n\n');
}
