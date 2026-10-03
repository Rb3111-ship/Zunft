/// Standard trade definitions and units for German Handwerk
class TradeConstants {
  static const String tradeElektro = 'elektro';
  static const String tradeSHK = 'shk';
  static const String tradeMaler = 'maler';
  static const String tradeDachdecker = 'dachdecker';
  static const String tradeTischler = 'tischler';

  static const Map<String, String> tradeLabels = {
    tradeElektro: 'Elektrotechnik & Elektronik',
    tradeSHK: 'Sanitär, Heizung, Klima (SHK)',
    tradeMaler: 'Maler & Lackierer',
    tradeDachdecker: 'Dachdecker',
    tradeTischler: 'Tischler & Schreiner',
  };

  /// Common German billing units
  static const String unitHours = 'Std';
  static const String unitPieces = 'Stk';
  static const String unitMeters = 'm';
  static const String unitFlatFee = 'Pauschal';

  static const List<String> availableUnits = [
    unitHours,
    unitPieces,
    unitMeters,
    unitFlatFee,
  ];

  /// German standard VAT rate (19%)
  static const double defaultVatRate = 19.0;
}
