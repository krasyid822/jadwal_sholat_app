import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hijri/hijri_calendar.dart';

/// Kelas utilitas untuk memformat tanggal dan waktu sholat.
/// Mengelola konversi dan format untuk kalender Masehi dan Hijriah.
class PrayerTimeFormatter {
  // Formatter standar untuk waktu (contoh: 04:35)
  static final DateFormat _timeFormatter = DateFormat('HH:mm');

  // Daftar nama bulan Hijriah dalam Bahasa Indonesia.
  static const List<String> _hijriMonthNames = [
    'Muharram',
    'Safar',
    'Rabiul Awal',
    'Rabiul Akhir',
    'Jumadil Awal',
    'Jumadil Akhir',
    'Rajab',
    'Sya\'ban',
    'Ramadhan',
    'Syawal',
    'Dzulqa\'dah',
    'Dzulhijjah',
  ];

  // Daftar nama hari dalam Bahasa Indonesia.
  static const List<String> _dayNames = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// Memformat objek DateTime menjadi string waktu (HH:mm).
  /// Contoh: DateTime(2025, 8, 22, 4, 30) -> "04:30"
  static String formatTime(DateTime time) {
    return _timeFormatter.format(time);
  }

  /// Memformat waktu mengikuti preferensi format 12/24 jam dari sistem operasi.
  /// - Menggunakan 24 jam jika perangkat di-set 24h, selain itu 12h (dengan AM/PM).
  static String formatTimeForContext(BuildContext context, DateTime time) {
    final use24h = MediaQuery.maybeOf(context)?.alwaysUse24HourFormat ?? false;
    final formatter = use24h ? DateFormat('HH:mm') : DateFormat('h:mm a');
    return formatter.format(time);
  }

  /// Memformat objek DateTime menjadi string tanggal Masehi yang mudah dibaca.
  /// Contoh: DateTime(2025, 8, 22) -> "Jumat, 22 Agustus 2025"
  static String formatGregorianDate(DateTime date) {
    // 'EEEE' untuk nama hari lengkap, 'd' untuk tanggal, 'MMMM' untuk nama bulan, 'y' untuk tahun.
    final dayName = _dayNames[date.weekday - 1];
    return "$dayName, ${DateFormat('d MMMM y', 'id_ID').format(date)}";
  }

  /// Mengonversi tanggal Masehi ke Hijriah dan memformatnya menjadi string.
  /// Contoh: DateTime(2025, 8, 22) -> "28 Jumadil Awal 1447 H"
  static String formatHijriDate(DateTime date) {
    // Inisialisasi kalender Hijriah dari tanggal Masehi.
    final hijriDate = HijriCalendar.fromDate(date);

    final day = hijriDate.hDay;
    // Mengambil nama bulan dari daftar berdasarkan indeks (hMonth - 1).
    final month = _hijriMonthNames[hijriDate.hMonth - 1];
    final year = hijriDate.hYear;

    return '$day $month $year H';
  }
}
