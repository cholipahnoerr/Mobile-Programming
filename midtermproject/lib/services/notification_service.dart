import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data; // Penamaan dibedakan
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // FIX: Gunakan penamaan import yang benar
    tz_data.initializeTimeZones();
    try {
      var rawLocation = await FlutterTimezone.getLocalTimezone();
      String timeZoneName = rawLocation.toString();
      // FIX: Jika string-nya aneh (ada tanda kurung), kita bersihkan
      if (timeZoneName.contains('(')) {
        // Mengambil teks di dalam kurung pertama sebelum koma
        // Contoh: TimezoneInfo(Asia/Bangkok, ...) -> Asia/Bangkok
        timeZoneName = timeZoneName.split('(')[1].split(',')[0];
      }

      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint("✅ Timezone Set to: $timeZoneName");
    } catch (e) {
      // JIKA GAGAL: Paksa pakai WIB (Asia/Jakarta) agar aplikasi tidak crash
      debugPrint("⚠️ Gagal deteksi Timezone, menggunakan fallback: Asia/Jakarta");
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      settings: initSettings, // Versi terbaru biasanya langsung oper variabelnya
      onDidReceiveNotificationResponse: (details) => debugPrint("Notif diklik"),
    );

    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }

    await scheduleDailyReminder();
  }

  Future<void> scheduleDailyReminder() async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id: 1,
        title: 'Reminder Malam',
        body: 'Sudah catat pengeluaran hari ini?',
        scheduledDate: _nextInstanceOfScheduledTime(),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_id',
            'Daily Reminder',
            importance: Importance.max, // FIX: Huruf Besar
            priority: Priority.high,    // FIX: Huruf Besar
            fullScreenIntent: true,     // FIX: Pindah ke dalam sini
            channelShowBadge: true,
            playSound: true,
            enableVibration: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      // FIX: Nama fungsi disamakan
      debugPrint("✅ Notif dijadwalkan: ${_nextInstanceOfScheduledTime()}");
      debugPrint("🕒 Jam HP Sekarang: ${tz.TZDateTime.now(tz.local)}");
    } catch (e) {
      debugPrint("❌ Notification error: $e");
    }
  }

  tz.TZDateTime _nextInstanceOfScheduledTime() {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    // SET KE 22:55 UNTUK TESTING
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 23, 50);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}