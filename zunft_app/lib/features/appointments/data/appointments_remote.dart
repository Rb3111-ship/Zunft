import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// An appointment action failed. [message] is German and safe to show.
class AppointmentException implements Exception {
  const AppointmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The one server call appointments need besides normal sync: an employee marking an appointment
/// that is assigned to them as done (employees may not edit appointments themselves). Faked in tests.
abstract class AppointmentsRemote {
  Future<void> setStatus(String id, String status);
}

class SupabaseAppointmentsRemote implements AppointmentsRemote {
  SupabaseAppointmentsRemote(this._client);

  final SupabaseClient _client;

  @override
  Future<void> setStatus(String id, String status) async {
    try {
      await _client.rpc('set_appointment_status', params: {'p_id': id, 'p_status': status}).timeout(const Duration(seconds: 20));
    } on PostgrestException {
      throw const AppointmentException('Das war nicht möglich (nicht mehr zugewiesen?).');
    } catch (_) {
      throw const AppointmentException('Keine Verbindung. Zum Abhaken wird Internet gebraucht.');
    }
  }
}
