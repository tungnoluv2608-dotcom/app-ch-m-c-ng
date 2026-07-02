import 'dart:async';
import 'package:app_cham_cong/main.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class EmpHomeView extends StatefulWidget {
  final String employeeName;
  const EmpHomeView({super.key, required this.employeeName});

  @override
  State<EmpHomeView> createState() => _EmpHomeViewState();
}

class _EmpHomeViewState extends State<EmpHomeView> {
  final supabase = Supabase.instance.client;
  final _networkInfo = NetworkInfo();
  DateTime? _leftWifiAt; // Mốc thời gian bắt đầu mất Wifi công ty
  bool _hasNotifiedLeave = false; // Cờ chặn việc bắn thông báo liên tục khi đã quá 10 phút
  Timer? _autoTrackingTimer; // Timer chạy ngầm 1 phút/lần

  bool _isLoading = true;
  bool _hasCheckedIn = false;
  String _checkInTimeText = "--:--";
  String _checkOutTimeText = "--:--";
  String _statusOffice = "🔍 ĐANG KIỂM TRA KẾT NỐI...";
  String _currentWifiName = "Chưa kết nối";

  DateTime? _lastCapturedInTime; // Lưu giờ vào để tính toán nhanh trên UI

  @override
  void initState() {
    super.initState();
    _initAttendanceAndStartTimer();
  }

  @override
  void dispose() {
    _autoTrackingTimer?.cancel();
    super.dispose();
  }

  // Khởi chạy quét lần đầu và kích hoạt vòng lặp chạy ngầm
  Future<void> _initAttendanceAndStartTimer() async {
    await _syncAttendanceData();
    // Cứ 1 phút quét mạng 1 lần để tự động cập nhật giờ về hoặc cảnh báo
    _autoTrackingTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _executeAutoTrackingLogic();
    });
  }

  // Hàm hỗ trợ format chuỗi ISO UTC sang Giờ:Phút Local nhanh gọn
  String _formatIsoToLocalTime(String? isoString) {
  if (isoString == null) return "--:--";
  try {
    // Đọc thẳng chuỗi chữ thô từ DB về, KHÔNG gọi .toLocal() nữa
    final localDateTime = DateTime.parse(isoString); 
    return "${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}";
  } catch (e) {
    return "--:--";
  }
}

  // 1. Hàm đồng bộ dữ liệu từ Supabase lên giao diện
  Future<void> _syncAttendanceData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      // Thay vì lấy 1 dòng gây lỗi, lấy dạng danh sách List
      final List<dynamic> logsToday = await supabase
          .from('attendance_logs')
          .select()
          .eq('user_id', user.id)
          .eq('date', todayStr);

      if (mounted) {
        setState(() {
          if (logsToday.isNotEmpty) {
            // Nếu lỡ bị spam nhiều dòng rác cũ, bốc dòng đầu tiên để hiển thị giờ lên màn hình luôn
            final logToday = logsToday.first; 
            
            _hasCheckedIn = true; // Khóa cờ: Đã chấm công, chặn đứng lệnh INSERT tạo dòng mới
            _statusOffice = "🟢 ĐANG TRONG CA LÀM VIỆC (Đã đồng bộ)";
            
            _checkInTimeText = _formatIsoToLocalTime(logToday['check_in_time']);
            _checkOutTimeText = _formatIsoToLocalTime(logToday['check_out_time']);

            if (logToday['check_in_time'] != null) {
              _lastCapturedInTime = DateTime.parse(logToday['check_in_time']);
            }
          } else {
            // Nếu hôm nay hoàn toàn trống trải chưa chấm công
            _hasCheckedIn = false;
            _checkInTimeText = "--:--";
            _checkOutTimeText = "--:--";
            _lastCapturedInTime = null;
            _statusOffice = "🔴 CHƯA CHẤM CÔNG (Vui lòng kết nối Wifi văn phòng)";
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Lỗi đồng bộ trạng thái ban đầu: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hàm chạy ngầm tự lấy ID phần cứng của máy (Có kèm mẹo tự bypass nếu là máy ảo để test)
  Future<String> _getDeviceUniqueId() async {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    
    // 💡 MẸO TEST TRÊN MÁY ẢO: Nếu phát hiện là máy ảo (Emulator), tự tạo ID ngẫu nhiên theo thời gian để đổi acc test thoải mái
    if (!androidInfo.isPhysicalDevice) {
      return "MAY_AO_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}";
    }
    
    return androidInfo.id; // Nếu là máy thật của nhân viên, lấy đúng mã ID chip gốc của máy
  }

  Future<void> _showLocalNotification({required String title, required String body}) async {
    final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
    
    const AndroidNotificationDetails androidNotificationDetails = AndroidNotificationDetails(
      'company_tracking_channel', // ID kênh
      'Cảnh báo chấm công',       // Tên kênh hiển thị trong cài đặt máy
      channelDescription: 'Thông báo nhắc nhở nhân viên giữ kết nối Wifi văn phòng',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: DarwinNotificationDetails(),
    );
    
    // Bắn thông báo đẩy độc lập lên màn hình điện thoại
    await localNotifications.show(
    id: 0, // <-- Thêm chữ id: ở đây
    title: title, 
    body: body, 
    notificationDetails: notificationDetails,
  );
  }

  // 2. Bộ bộ não xử lý tự động: Check-in, Tự động Check-out, Chống log hộ và Bắn cảnh báo thiếu giờ
  Future<void> _executeAutoTrackingLogic() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final todayStr = DateTime.now().toIso8601String().substring(0, 10);
  final now = DateTime.now();

  // Lấy tên Wifi điện thoại hiện tại
  String? wifiName = await _networkInfo.getWifiName();
  if (wifiName != null) wifiName = wifiName.replaceAll('"', '');

  // 1. 🔄 TẢI TOÀN BỘ CẤU HÌNH HÀNH CHÍNH & QUY CHẾ ĐỘNG TỪ DATABASE
  final wifiSetting = await supabase
      .from('company_settings')
      .select('wifi_name, work_hours_required, start_work_time, lunch_start_time, lunch_end_time, max_late_early_per_month, max_hours_per_turn, half_day_hours')
      .eq('id', 'wifi_setting')
      .maybeSingle();

  final String companyWifiName = wifiSetting != null ? wifiSetting['wifi_name'] : "AndroidWifi";
  
  // Đọc các giá trị thời gian và quy chế động (có fallback an toàn)
  final String startWorkStr = wifiSetting?['start_work_time'] ?? "08:00";
  final double requiredHours = (wifiSetting?['work_hours_required'] ?? 8.0).toDouble();
  final String lunchStartStr = wifiSetting?['lunch_start_time'] ?? "12:00";
  final String lunchEndStr = wifiSetting?['lunch_end_time'] ?? "13:00";
  
  // Các biến quy chế mới phục vụ tính phạt đi muộn
  final double maxHoursPerTurn = (wifiSetting?['max_hours_per_turn'] ?? 2.0).toDouble();
  final double halfDayHours = (wifiSetting?['half_day_hours'] ?? 4.0).toDouble();

  if (!mounted) return;
  setState(() {
    _currentWifiName = wifiName ?? "Không xác định";
  });

  // 2. 🔍 QUÉT XEM HÔM NAY NHÂN VIÊN CÓ ĐƠN ĐI CÔNG TÁC HOẶC XIN ĐẾN MUỘN ĐÃ ĐƯỢC DUYỆT KHÔNG
  final approvedTickets = await supabase
      .from('leave_requests')
      .select('leave_type')
      .eq('user_id', user.id)
      .eq('status', 'Đã duyệt')
      .eq('date', todayStr);

  bool isBusinessTripToday = approvedTickets.any((t) => t['leave_type'] == 'Đi công tác');
  bool hasApprovedLateToday = approvedTickets.any((t) => t['leave_type'] == 'Xin đi muộn');

  // =========================================================================
  // 🔥 ĐỔI LOGIC: NẾU TRÙNG WIFI HOẶC ĐANG ĐI CÔNG TÁC THÌ ĐỀU KÍCH HOẠT VÀO CA
  // =========================================================================
  if (wifiName == companyWifiName || isBusinessTripToday) {
    if (!_hasCheckedIn) {
      
      // CHIẾN THUẬT KHÓA NGAY LOCAL: Chặn đứng spam request ngầm
      setState(() {
        _hasCheckedIn = true;
        _statusOffice = isBusinessTripToday 
            ? "💼 ĐANG TIẾN HÀNH CHECK-IN CÔNG TÁC TỰ ĐỘNG..."
            : "🔄 ĐANG TIẾN HÀNH CHECK-IN TỰ ĐỘNG...";
      });

      try {
        // KHÓA CHẶN CHẠY NGẦM: KIỂM TRA ĐÚNG MÁY CHÍNH CHỦ (Bỏ qua kiểm tra thiết bị nếu đi công tác)
        if (!isBusinessTripToday) {
          String currentDeviceId = await _getDeviceUniqueId();
          final profile = await supabase.from('profiles').select('device_id').eq('id', user.id).maybeSingle();
          String? savedDeviceId = profile?['device_id'];

          if (savedDeviceId == null) {
            await supabase.from('profiles').update({'device_id': currentDeviceId}).eq('id', user.id);
            savedDeviceId = currentDeviceId;
          }

          if (currentDeviceId != savedDeviceId && !currentDeviceId.startsWith("MAY_AO_")) {
            if (mounted) {
              setState(() {
                _hasCheckedIn = false;
                _statusOffice = "❌ THẤT BẠI: Thiết bị không hợp lệ! (Phát hiện hành vi đăng nhập hộ).";
              });
            }
            return;
          }
        }

        // 3. ⏱️ TÍNH TOÁN THỜI GIAN ĐI MUỘN VÀ ÁP DỤNG QUY CHẾ ĐỘNG
        final int startHour = int.parse(startWorkStr.split(':')[0]);
        final int startMinute = int.parse(startWorkStr.split(':')[1]);
        final caVao = DateTime(now.year, now.month, now.day, startHour, startMinute);
        
        int lateMinutes = now.isAfter(caVao) ? now.difference(caVao).inMinutes : 0;
        bool isLateToday = now.isAfter(caVao);
        String logNote = "Làm việc tại VP";

        // --- 💼 KỊCH BẢN A1: ĐANG ĐI CÔNG TÁC (Tính 1 công sạch, không phạt) ---
        if (isBusinessTripToday) {
          lateMinutes = 0;
          isLateToday = false;
          logNote = "💼 Đi công tác (Đã duyệt tính công)";
        } 
        // --- 🕒 KỊCH BẢN A2: ĐI MUỘN NHƯNG CÓ ĐƠN XIN PHÉP ---
        else if (hasApprovedLateToday && isLateToday) {
          double lateHours = lateMinutes / 60.0;

          if (lateHours >= halfDayHours) {
            // Muộn từ nửa ngày trở lên -> Tính nghỉ phép/không lương, tắt cờ đi muộn kỉ luật
            isLateToday = false;
            logNote = "📌 Đi muộn nửa ngày (Trừ 0.5 ngày phép/Không lương)";
          } else if (lateHours > maxHoursPerTurn) {
            // Muộn vượt khung quy định (Ví dụ > 2 tiếng) -> Giữ cờ muộn để tính phạt x2 lần
            isLateToday = true;
            logNote = "📌 Đi muộn vượt khung $maxHoursPerTurn giờ (Tính phạt x2 lần)";
          } else {
            // Đi muộn thông thường và có đơn xin phép -> Xem như đúng giờ
            isLateToday = false;
            logNote = "📌 Đi muộn có lý do (Đã duyệt)";
          }
        }

        // Ép chuỗi thô đúng số giờ Việt Nam hiện tại, cắt đuôi múi giờ
        String formatStringRaw = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
        
        // 4. 💾 TIẾN HÀNH CHÈN DÒNG CHẤM CÔNG LÊN SUPABASE
        await supabase.from('attendance_logs').insert({
          'user_id': user.id,
          'date': todayStr,                  // Ngày dạng YYYY-MM-DD
          'check_in_time': formatStringRaw,  // Lưu chuỗi thô giờ Việt Nam
          'late_minutes': lateMinutes,
          'is_late': isLateToday,
          'note': logNote,                   // Lưu vết ghi chú quy chế để hiển thị hoặc tính lương
        });
        
        if (!mounted) return;
        setState(() {
          _statusOffice = isBusinessTripToday ? "💼 ĐANG ĐI CÔNG TÁC" : "🟢 ĐANG Ở VĂN PHÒNG";
        });
        await _syncAttendanceData();
        
      } catch (e) {
        print("Lỗi chèn dòng tự động: $e");
        if (mounted) {
          setState(() {
            _hasCheckedIn = false;
            _statusOffice = "🔴 TRỤC TRẶC KẾT NỐI. ĐANG TỰ ĐỘNG THỬ LẠI...";
          });
        }
      }
    } else {
      // 5. 🔁 MÁY ĐÃ VÀO CA: KHÓA CHẶN SPAM ĐỂ CẬP NHẬT GIỜ RA CA (CHECK-OUT) NGẦM MỖI 5 PHÚT
      if (now.minute % 5 == 0) {
        String formatStringRaw = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

        await supabase.from('attendance_logs').update({
          'check_out_time': formatStringRaw, // Lưu chuỗi thô giờ Việt Nam lúc ra ca
        }).eq('user_id', user.id).eq('date', todayStr);
        
        if (!mounted) return;
        await _syncAttendanceData();
      }
    }
  }
    // KỊCH BẢN B: NHÂN VIÊN ĐI RA NGOÀI (MẤT WIFI CÔNG TY)
    else if (_hasCheckedIn) {
      if (isBusinessTripToday) return;
      if (_lastCapturedInTime != null) {
        
        // 1. Ghi nhận mốc thời gian bắt đầu ra ngoài (Nếu chưa ghi nhận)
        if (_leftWifiAt == null) {
          _leftWifiAt = DateTime.now();
          _hasNotifiedLeave = false; // Reset cờ thông báo
        }

        // 2. Tính số phút nhân viên đã ngắt kết nối Wifi thực tế
        int minutesOutside = DateTime.now().difference(_leftWifiAt!).inMinutes;

        // 3. Nếu đã ra ngoài vượt quá 10 phút và chưa bắn thông báo thì tiến hành nhắc nhở
        if (minutesOutside >= 0 && !_hasNotifiedLeave) {
          _hasNotifiedLeave = true; // Khóa cờ để không bị bắn thông báo lặp đi lặp lại mỗi phút
          
          // 🔥 GỌI HÀM BẮN THÔNG BÁO ĐẨY RA MÀN HÌNH KHÓA Ở ĐÂY
          _showLocalNotification(
            title: "🚨 CẢNH BÁO RỜI VĂN PHÒNG TOO LONG",
            body: "Bạn đã ra ngoài quá 10 phút mà chưa kết nối lại Wifi công ty. Hệ thống sẽ tự động tính thiếu giờ nếu bạn không quay lại!",
          );
        }

        // 4. Cập nhật chữ hiển thị trên app như cũ của bạn
        int currentWorkMins = now.difference(_lastCapturedInTime!).inMinutes;
        final int lunchStartHour = int.parse(lunchStartStr.split(':')[0]);
        final int lunchStartMin = int.parse(lunchStartStr.split(':')[1]);
        final int lunchEndHour = int.parse(lunchEndStr.split(':')[0]);
        final int lunchEndMin = int.parse(lunchEndStr.split(':')[1]);

        final lunchStart = DateTime(now.year, now.month, now.day, lunchStartHour, lunchStartMin);
        final lunchEnd = DateTime(now.year, now.month, now.day, lunchEndHour, lunchEndMin);
        
        // Giờ nghỉ trưa tự do thì không tính ép giờ
        if (_lastCapturedInTime!.isBefore(lunchStart) && now.isAfter(lunchEnd)) {
          currentWorkMins -= lunchEnd.difference(lunchStart).inMinutes; 
        }

        int requiredMinutes = (requiredHours * 60).toInt();

        if (currentWorkMins < requiredMinutes) {
          if (mounted) {
            setState(() {
              _statusOffice =
                  "⚠️ CẢNH BÁO: Bạn rời văn phòng $minutesOutside phút (Chưa làm đủ $requiredHours tiếng!). Nếu không quay lại, ngày hôm nay sẽ bị tính thiếu giờ!";
            });
          }
        }
      }
    }
    // 💡 MẸO ĐỒNG BỘ: Nếu nhân viên quay lại văn phòng (Kết nối lại đúng Wifi)
    else {
      // Reset hoàn toàn mốc đếm thời gian ra ngoài
      _leftWifiAt = null;
      _hasNotifiedLeave = false;
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _syncAttendanceData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '👋 Xin chào, ${widget.employeeName}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Thẻ trạng thái thông minh tự động thay đổi màu sắc dựa trên kỷ luật giờ giấc
            Card(
              color: _statusOffice.contains('⚠️')
                  ? Colors.red.shade50
                  : (_statusOffice.contains('❌')
                        ? Colors.red.shade100
                        : Colors.green.shade50),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'NHẬT KÝ ĐIỂM DANH TỰ ĐỘNG CHỐT CA',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.login_rounded,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Giờ đến văn phòng: ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              _checkInTimeText,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10), 
                        Row(
                          children: [
                            const Icon(
                              Icons.logout_rounded,
                              color: Colors.orange,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Ghi nhận giờ về cuối: ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            Text(
                              _checkOutTimeText,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text(
                      _statusOffice,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _statusOffice.contains('⚠️') || _statusOffice.contains('❌')
                            ? Colors.red.shade800
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            Card(
              elevation: 1,
              child: ListTile(
                leading: Icon(
                  Icons.wifi,
                  color: _hasCheckedIn && !_statusOffice.contains('⚠️')
                      ? Colors.green
                      : Colors.red,
                ),
                title: const Text(
                  'Mạng Wifi đang kết nối:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                subtitle: Text(
                  _currentWifiName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _syncAttendanceData,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}