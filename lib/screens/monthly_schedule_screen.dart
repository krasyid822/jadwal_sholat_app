import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jadwal_sholat_app/utils/prayer_calculation_utils.dart';
import 'package:jadwal_sholat_app/utils/prayer_time_formatter.dart';

// Removed old per-day wrapper class; the table computes times per day on-demand

class MonthlyScheduleScreen extends StatefulWidget {
  final Coordinates coordinates;

  const MonthlyScheduleScreen({super.key, required this.coordinates});

  @override
  State<MonthlyScheduleScreen> createState() => _MonthlyScheduleScreenState();
}

class _MonthlyScheduleScreenState extends State<MonthlyScheduleScreen> {
  late DateTime _selectedDate;
  late DateTime _baseMonth;
  bool _isHijriCalendar = false;
  bool _hidePastDays = false;

  void _goToPreviousMonth() {
    setState(() {
      if (_isHijriCalendar) {
        // Untuk mode Hijriah, navigasi berdasarkan bulan Hijriah
        final currentHijri = HijriCalendar.fromDate(_selectedDate);
        final newHijriMonth = currentHijri.hMonth - 1;
        int newHijriYear = currentHijri.hYear;
        int adjustedMonth = newHijriMonth;

        if (adjustedMonth < 1) {
          adjustedMonth = 12;
          newHijriYear--;
        }

        final hijriDate = HijriCalendar();
        hijriDate.hYear = newHijriYear;
        hijriDate.hMonth = adjustedMonth;
        hijriDate.hDay = 1;

        _selectedDate = hijriDate.hijriToGregorian(
          hijriDate.hYear,
          hijriDate.hMonth,
          hijriDate.hDay,
        );
      } else {
        // Untuk mode Masehi, gunakan cara biasa
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month - 1,
          1,
        );
      }
    });
  }

  void _goToNextMonth() {
    setState(() {
      if (_isHijriCalendar) {
        // Untuk mode Hijriah, navigasi berdasarkan bulan Hijriah
        final currentHijri = HijriCalendar.fromDate(_selectedDate);
        final newHijriMonth = currentHijri.hMonth + 1;
        int newHijriYear = currentHijri.hYear;
        int adjustedMonth = newHijriMonth;

        if (adjustedMonth > 12) {
          adjustedMonth = 1;
          newHijriYear++;
        }

        final hijriDate = HijriCalendar();
        hijriDate.hYear = newHijriYear;
        hijriDate.hMonth = adjustedMonth;
        hijriDate.hDay = 1;

        _selectedDate = hijriDate.hijriToGregorian(
          hijriDate.hYear,
          hijriDate.hMonth,
          hijriDate.hDay,
        );
      } else {
        // Untuk mode Masehi, gunakan cara biasa
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month + 1,
          1,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _baseMonth = DateTime(now.year, now.month, 1);
    _selectedDate = _baseMonth;
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    try {
      await initializeDateFormatting('id_ID', null);
    } catch (e) {
      // Fallback jika locale Indonesia tidak tersedia
      debugPrint('Failed to initialize Indonesian locale: $e');
    }
  }

  /// Format tanggal dengan fallback jika locale tidak tersedia
  String _formatDate(DateTime date, String pattern) {
    try {
      return DateFormat(pattern, 'id_ID').format(date);
    } catch (e) {
      // Fallback ke format default tanpa locale
      return DateFormat(pattern).format(date);
    }
  }

  // Waktu diformat langsung saat rendering tabel menggunakan PrayerTimeFormatter

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_getMonthTitle(_selectedDate))),
      body: Column(
        children: [
          _buildCalendarToggle(),
          _buildPastDaysToggle(),
          Expanded(
            child: FutureBuilder<Widget>(
              future: _buildMonthlyTable(_selectedDate),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else {
                  return snapshot.data ?? const SizedBox();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthTitle(DateTime date) {
    if (!_isHijriCalendar) {
      return _formatDate(date, 'MMMM yyyy');
    }
    final h = HijriCalendar.fromDate(date);
    return '${h.getLongMonthName()} ${h.hYear} H';
  }

  Widget _buildCalendarToggle() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          // Tombol navigasi kiri
          IconButton(
            onPressed: _goToPreviousMonth,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Bulan Sebelumnya',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),

          const SizedBox(width: 8),

          // Toggle calendar type
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Masehi'),
                  icon: Icon(Icons.calendar_today),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Hijriah'),
                  icon: Icon(Icons.mosque),
                ),
              ],
              selected: {_isHijriCalendar},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _isHijriCalendar = newSelection.first;
                });
              },
            ),
          ),

          const SizedBox(width: 8),

          // Tombol navigasi kanan
          IconButton(
            onPressed: _goToNextMonth,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Bulan Berikutnya',
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPastDaysToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(
          color: _hidePastDays
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _hidePastDays ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: _hidePastDays
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hidePastDays
                      ? 'Hari lalu Disembunyikan'
                      : 'Sembunyikan hari lalu',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _hidePastDays
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _hidePastDays,
                onChanged: (value) {
                  setState(() {
                    _hidePastDays = value;
                  });
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                activeTrackColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Widget> _buildMonthlyTable(DateTime monthStart) async {
    final now = DateTime.now();
    final isCurrentMonth =
        now.year == monthStart.year && now.month == monthStart.month;

    // Tentukan tanggal akhir berdasarkan kalender yang dipilih
    late int daysInMonth;
    late DateTime monthEnd;

    if (_isHijriCalendar) {
      // Untuk kalender Hijriah, hitung berdasarkan bulan Hijriah yang sebenarnya
      final hijriStart = HijriCalendar.fromDate(monthStart);

      // Hitung panjang bulan Hijriah dengan menggunakan algoritma yang lebih akurat
      // Gunakan HijriCalendar untuk menentukan apakah bulan memiliki 29 atau 30 hari
      daysInMonth = _getHijriMonthLength(hijriStart.hYear, hijriStart.hMonth);

      // Konversi ke tanggal Masehi untuk hari terakhir bulan Hijriah
      final hijriEnd = HijriCalendar();
      hijriEnd.hYear = hijriStart.hYear;
      hijriEnd.hMonth = hijriStart.hMonth;
      hijriEnd.hDay = daysInMonth;

      monthEnd = hijriEnd.hijriToGregorian(
        hijriEnd.hYear,
        hijriEnd.hMonth,
        hijriEnd.hDay,
      );
    } else {
      // Untuk kalender Masehi, gunakan cara biasa
      daysInMonth = DateUtils.getDaysInMonth(monthStart.year, monthStart.month);
      monthEnd = DateTime(monthStart.year, monthStart.month, daysInMonth);
    }

    // Build rows berdasarkan range tanggal yang tepat
    final List<DataRow> rows = [];

    if (_isHijriCalendar) {
      // Untuk mode Hijriah, iterasi berdasarkan hari Hijriah
      final hijriStart = HijriCalendar.fromDate(monthStart);

      for (int day = 1; day <= daysInMonth; day++) {
        final hijriDate = HijriCalendar();
        hijriDate.hYear = hijriStart.hYear;
        hijriDate.hMonth = hijriStart.hMonth;
        hijriDate.hDay = day;

        // Konversi ke tanggal Masehi untuk perhitungan waktu sholat
        final currentDate = hijriDate.hijriToGregorian(
          hijriDate.hYear,
          hijriDate.hMonth,
          hijriDate.hDay,
        );

        if (_hidePastDays &&
            isCurrentMonth &&
            currentDate.isBefore(DateTime(now.year, now.month, now.day))) {
          continue; // skip past days if toggled
        }

        final prayerTimes =
            await PrayerCalculationUtils.calculatePrayerTimesEnhanced(
              widget.coordinates,
              DateComponents(
                currentDate.year,
                currentDate.month,
                currentDate.day,
              ),
            );

        final imsak = prayerTimes.fajr.subtract(const Duration(minutes: 10));
        final dhuha = PrayerCalculationUtils.calculateDhuha(
          prayerTimes.sunrise,
        );

        final isToday = DateUtils.isSameDay(currentDate, now);

        rows.add(
          _buildDataRow(
            currentDate,
            hijriDate,
            prayerTimes,
            imsak,
            dhuha,
            isToday,
          ),
        );
      }
    } else {
      // Untuk mode Masehi, gunakan cara biasa
      DateTime currentDate = monthStart;

      while (currentDate.isBefore(monthEnd.add(const Duration(days: 1)))) {
        if (_hidePastDays &&
            isCurrentMonth &&
            currentDate.isBefore(DateTime(now.year, now.month, now.day))) {
          currentDate = currentDate.add(const Duration(days: 1));
          continue; // skip past days in current month if toggled
        }

        final hijriDate = HijriCalendar.fromDate(currentDate);
        final prayerTimes =
            await PrayerCalculationUtils.calculatePrayerTimesEnhanced(
              widget.coordinates,
              DateComponents(
                currentDate.year,
                currentDate.month,
                currentDate.day,
              ),
            );

        final imsak = prayerTimes.fajr.subtract(const Duration(minutes: 10));
        final dhuha = PrayerCalculationUtils.calculateDhuha(
          prayerTimes.sunrise,
        );

        final isToday = DateUtils.isSameDay(currentDate, now);

        rows.add(
          _buildDataRow(
            currentDate,
            hijriDate,
            prayerTimes,
            imsak,
            dhuha,
            isToday,
          ),
        );

        currentDate = currentDate.add(const Duration(days: 1));
      }
    }

    if (rows.isEmpty) {
      return const Center(child: Text('Tidak ada jadwal untuk ditampilkan.'));
    }

    // Wrap DataTable in both horizontal and vertical scroll views
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 900),
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 48,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 44,
              columnSpacing: 20,
              columns: [
                if (!_isHijriCalendar) ...[
                  const DataColumn(label: Text('Tanggal')),
                  const DataColumn(label: Text('Hijriah')),
                ] else ...[
                  const DataColumn(label: Text('Hijriah')),
                  const DataColumn(label: Text('Tanggal')),
                ],
                const DataColumn(label: Text('Imsak')),
                const DataColumn(label: Text('Subuh')),
                const DataColumn(label: Text('Terbit')),
                const DataColumn(label: Text('Dhuha')),
                const DataColumn(label: Text('Dzuhur')),
                const DataColumn(label: Text('Ashar')),
                const DataColumn(label: Text('Maghrib')),
                const DataColumn(label: Text('Isya')),
              ],
              rows: rows,
            ),
          ),
        ),
      ),
    );
  }

  /// Helper method untuk membuat DataRow
  DataRow _buildDataRow(
    DateTime currentDate,
    HijriCalendar hijriDate,
    PrayerTimes prayerTimes,
    DateTime imsak,
    DateTime dhuha,
    bool isToday,
  ) {
    return DataRow(
      color: isToday
          ? WidgetStatePropertyAll(
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
            )
          : null,
      cells: [
        if (!_isHijriCalendar) ...[
          DataCell(Text(_formatDate(currentDate, 'd MMM'), softWrap: false)),
          DataCell(
            Text(
              '${hijriDate.hDay} ${hijriDate.getLongMonthName()}',
              softWrap: false,
            ),
          ),
        ] else ...[
          DataCell(
            Text(
              '${hijriDate.hDay} ${hijriDate.getLongMonthName()}',
              softWrap: false,
            ),
          ),
          DataCell(Text(_formatDate(currentDate, 'd MMM'), softWrap: false)),
        ],
        DataCell(
          Text(PrayerTimeFormatter.formatTimeForContext(context, imsak)),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(context, prayerTimes.fajr),
          ),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(
              context,
              prayerTimes.sunrise,
            ),
          ),
        ),
        DataCell(
          Text(PrayerTimeFormatter.formatTimeForContext(context, dhuha)),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(
              context,
              prayerTimes.dhuhr,
            ),
          ),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(context, prayerTimes.asr),
          ),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(
              context,
              prayerTimes.maghrib,
            ),
          ),
        ),
        DataCell(
          Text(
            PrayerTimeFormatter.formatTimeForContext(context, prayerTimes.isha),
          ),
        ),
      ],
    );
  }

  /// Menghitung panjang bulan Hijriah (29 atau 30 hari)
  /// Menggunakan algoritma kalkulasi berbasis siklus lunar
  int _getHijriMonthLength(int hijriYear, int hijriMonth) {
    // Algoritma sederhana: bulan-bulan tertentu memiliki 30 hari, sisanya 29 hari
    // Bulan 1,3,5,7,9,11 = 30 hari
    // Bulan 2,4,6,8,10 = 29 hari
    // Bulan 12 = 29 hari (30 hari pada tahun kabisat)

    if (hijriMonth == 12) {
      // Bulan 12 (Zulhijjah) - cek tahun kabisat Hijriah
      return _isHijriLeapYear(hijriYear) ? 30 : 29;
    } else if (hijriMonth % 2 == 1) {
      // Bulan ganjil (1,3,5,7,9,11) = 30 hari
      return 30;
    } else {
      // Bulan genap (2,4,6,8,10) = 29 hari
      return 29;
    }
  }

  /// Menentukan apakah tahun Hijriah adalah tahun kabisat
  bool _isHijriLeapYear(int hijriYear) {
    // Siklus 30 tahun Hijriah: tahun ke 2,5,7,10,13,16,18,21,24,26,29 adalah kabisat
    final List<int> leapYears = [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29];
    final yearInCycle = hijriYear % 30;
    return leapYears.contains(yearInCycle);
  }

  // Removed legacy list-based helpers
}
