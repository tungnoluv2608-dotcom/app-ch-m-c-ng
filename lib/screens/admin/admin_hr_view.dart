import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_rules_settings_view.dart'; // <-- Đường dẫn mới cho Admin
import 'dart:io';
import 'package:excel/excel.dart' hide Border; // 💥 Chặn xung đột Border hệ thống
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminHrView extends StatefulWidget {
  const AdminHrView({super.key});

  @override
  State<AdminHrView> createState() => _AdminHrViewState();
}

class _AdminHrViewState extends State<AdminHrView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<dynamic> _employeeList = [];

  // 🔥 BIẾN LỌC THÁNG / NĂM CHỦ ĐẠO TOÀN TRANG
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeList();
  }

  // 🔄 TRUY VẤN DANH SÁCH NHÂN VIÊN & TỰ ĐỘNG ĐẾM CÔNG THEO THÁNG TRÊN APP
  Future<void> _fetchEmployeeList() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 1. Đọc toàn bộ danh sách hồ sơ nhân sự
      final data = await supabase.from('profiles').select().order('full_name');
      List<dynamic> employees = data;

      // 2. Tính số ngày của tháng đang chọn trên bộ lọc
      int daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
      final startOfMonthStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-01T00:00:00";
      final endOfMonthStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${daysInMonth}T23:59:59";

      // 3. Quét nhanh log điểm danh của tháng này để đếm số ngày đi làm hiển thị lên giao diện
      final attendanceData = await supabase
          .from('attendance_logs')
          .select('user_id')
          .gte('check_in_time', startOfMonthStr)
          .lte('check_in_time', endOfMonthStr);
      
      final List<dynamic> logs = attendanceData as List<dynamic>;

      // 4. Gắn kèm số ngày công vào dữ liệu hiển thị trên danh sách app
      for (var emp in employees) {
        final String userId = emp['id'] ?? '';
        int count = logs.where((log) => log['user_id'] == userId).length;
        emp['monthly_work_count'] = count; // Lưu biến tạm để vẽ giao diện UI
      }

      print("🔍 ĐỌC BẢNG PROFILES ĐƯỢC: ${employees.length} DÒNG.");
      print("DỮ LIỆU THÔ PROFILES KÈM CÔNG: $employees");
      
      if (mounted) {
        setState(() {
          _employeeList = employees;
        });
      }
    } catch (e) {
      print("🚨 LỖI TẠI ADMIN_HR_VIEW: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 📥 THUẬT TOÁN QUÉT DATA SUPABASE & DỰNG BẢNG MA TRẬN TIMESHEET THEO THÁNG RA EXCEL
  Future<void> _exportTimesheetToExcel() async {
    // Chỉ xuất những tài khoản đóng vai trò là nhân viên (employee) để tính công làm việc
    final employeesOnly = _employeeList.where((emp) => emp['role'] == 'employee' || emp['role'] == null).toList();

    if (employeesOnly.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Không có dữ liệu nhân viên để tính bảng công!'), backgroundColor: Colors.orange),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('Đang tổng hợp công tháng $_selectedMonth/$_selectedYear...'),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // 1. Tính số ngày tối đa trong tháng được chọn
      int daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;

      // 2. Tải toàn bộ nhật ký chấm công của cả tháng được chọn từ database
      final startOfMonthStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-01T00:00:00";
      final endOfMonthStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${daysInMonth}T23:59:59"; // 🔥 Đã bọc {daysInMonth} tránh lỗi

      final attendanceData = await supabase
          .from('attendance_logs')
          .select('user_id, date, is_late')
          .gte('check_in_time', startOfMonthStr)
          .lte('check_in_time', endOfMonthStr);

      final List<dynamic> monthlyLogs = attendanceData as List<dynamic>;

      // 3. Khởi tạo tệp Excel
      var excel = Excel.createExcel();
      String sheetName = "Timesheet_T${_selectedMonth}_$_selectedYear";
      excel.rename('Sheet1', sheetName);
      Sheet sheetObject = excel[sheetName];

      // Style cho hàng tiêu đề chính màu xám đậm chữ trắng in đậm
      CellStyle headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.blueGrey800,
        horizontalAlign: HorizontalAlign.Center,
      );

      // 4. Khởi tạo danh sách tiêu đề các cột
      List<String> headers = ["STT", "Mã Số NV", "Họ và Tên"];
      for (int i = 1; i <= daysInMonth; i++) {
        headers.add(i.toString().padLeft(2, '0'));
      }
      headers.addAll(["Tổng Ngày Làm (X)", "Tổng Lần Muộn (M)"]);

      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      // Gắn style màu nền cho Header
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.cellStyle = headerStyle;
      }

      // 5. Vòng lặp tính toán công chi tiết từng ngày cho mỗi nhân viên đổ vào file Excel
      for (int index = 0; index < employeesOnly.length; index++) {
        final emp = employeesOnly[index];
        final String userId = emp['id'] ?? '';
        final String empCode = emp['employee_code'] ?? 'NV-${index + 1}';
        final String empName = emp['full_name'] ?? 'Không rõ';

        List<CellValue> rowData = [
          IntCellValue(index + 1),
          TextCellValue(empCode),
          TextCellValue(empName),
        ];

        int workDaysCount = 0;
        int lateTimesCount = 0;

        // Quét qua từng ngày trong tháng để kiểm tra log
        for (int day = 1; day <= daysInMonth; day++) {
          final String currentDayStr = "$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}";
          
          // Kiểm tra xem nhân viên này có log check-in trong ngày đang xét hay không
          var matchLog = monthlyLogs.firstWhere(
            (log) => log['user_id'] == userId && log['date'].toString() == currentDayStr,
            orElse: () => <String, dynamic>{}, 
          );

          // Kiểm tra xem Map có dữ liệu hay không bằng lệnh .isNotEmpty
          if (matchLog.isNotEmpty) {
            if (matchLog['is_late'] == true) {
              rowData.add(TextCellValue("M")); // M: Đi muộn
              lateTimesCount++;
            } else {
              rowData.add(TextCellValue("X")); // X: Đúng giờ
            }
            workDaysCount++;
          } else {
            rowData.add(TextCellValue("V")); // V: Vắng mặt
          }
        }

        // Đổ hai cột tổng kết công tháng vào cuối dòng Excel
        rowData.add(IntCellValue(workDaysCount));
        rowData.add(IntCellValue(lateTimesCount));

        sheetObject.appendRow(rowData);
      }

      // 6. Lưu file và mở hệ thống bảng Share đa năng của điện thoại
      var fileBytes = excel.save();
      final directory = await getTemporaryDirectory();
      String filePath = "${directory.path}/Bang_Cong_Thang_${_selectedMonth}_$_selectedYear.xlsx";
      
      File file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      await Share.shareXFiles([XFile(filePath)], text: 'Bảng tổng hợp công tháng $_selectedMonth/$_selectedYear');

    } catch (e) {
      print("Lỗi xuất bảng công Excel: $e");
    }
  }

  void _viewEmployeeDetail(String userId, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            EmployeeDetailScreen(userId: userId, userName: userName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TẦNG 1: HEADER QUẢN LÝ TIÊU ĐỀ + NÚT XUẤT TIMESHEET EXCEL THÁNG MÀU XANH LÁ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '👥 QUẢN LÝ NHÂN SỰ CÔNG TY',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.file_download_rounded, color: Colors.green, size: 28),
                tooltip: 'Xuất bảng công tháng ra Excel',
                onPressed: _exportTimesheetToExcel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // ACTION TAG: Đếm tổng nhân sự & Nút cấu hình quy chế công ty
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tổng số nhân sự: ${_employeeList.length}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminRuleSettingsView(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 16, color: Colors.blue),
                label: const Text(
                  'Cấu hình quy chế',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 🔥 WIDGET TIỆN ÍCH CHỌN THÁNG / NĂM: ĐỔI ĐẾM CÔNG CHO CẢ APP LẪN FILE FILE XUẤT
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Chọn kỳ chốt công:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                Row(
                  children: [
                    DropdownButton<int>(
                      value: _selectedMonth,
                      underline: const SizedBox(),
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                      items: List.generate(12, (index) => index + 1).map((month) {
                        return DropdownMenuItem<int>(value: month, child: Text('Tháng $month '));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedMonth = val);
                          _fetchEmployeeList(); // 🔥 Gọi lại quét đồng bộ UI app ngay tức khắc
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _selectedYear,
                      underline: const SizedBox(),
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13),
                      items: [2024, 2025, 2026, 2027].map((year) {
                        return DropdownMenuItem<int>(value: year, child: Text('Năm $year'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedYear = val);
                          _fetchEmployeeList(); // 🔥 Gọi lại quét đồng bộ UI app ngay tức khắc
                        }
                      },
                    ),
                  ],
                )
              ],
            ),
          ),

          const SizedBox(height: 16),
          // DANH SÁCH CHI TIẾT HIỂN THỊ HỒ SƠ & SỐ NGÀY CÔNG XANH LÁ
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchEmployeeList,
              child: ListView.builder(
                itemCount: _employeeList.length,
                itemBuilder: (context, index) {
                  final emp = _employeeList[index];
                  final String role = emp['role'] ?? 'employee';
                  
                  // 🔥 LẤY BIẾN SỐ NGÀY CÔNG ĐÃ ĐƯỢC TÍNH TOÁN THEO THÁNG CHỌN ĐỘNG
                  final int monthlyWorkCount = emp['monthly_work_count'] ?? 0;

                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: role == 'admin'
                            ? Colors.red.shade100
                            : Colors.blue.shade100,
                        child: Text(
                          (emp['full_name'] ?? 'U')[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: role == 'admin' ? Colors.red : Colors.blue,
                          ),
                        ),
                      ),
                      title: Text(
                        emp['full_name'] ?? 'Chưa đặt tên',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vai trò: ${role == 'admin' ? 'Quản lý (Sếp)' : 'Nhân viên'}'),
                          if (role != 'admin') ...[
                            const SizedBox(height: 4),
                            Text(
                              'Công tháng $_selectedMonth: $monthlyWorkCount ngày làm', // 🔥 Chữ xanh lá hiển thị trực quan
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      onTap: () => _viewEmployeeDetail(
                        emp['id'],
                        emp['full_name'] ?? 'Nhân viên',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// MÀN HÌNH XEM CHI TIẾT LỊCH SỬ CÔNG CỦA RIÊNG TỪNG NHÂN VIÊN
// ====================================================================
class EmployeeDetailScreen extends StatefulWidget {
  final String userId;
  final String userName;
  const EmployeeDetailScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<dynamic> _history = [];
  int _workDays = 0;
  int _lateTimes = 0;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeAttendance();
  }

  Future<void> _fetchEmployeeAttendance() async {
    try {
      final data = await supabase
          .from('attendance_logs')
          .select()
          .eq('user_id', widget.userId)
          .order('date', ascending: false);

      final Map<String, dynamic> groupedLogs = {};
      final uniqueDays = <String>{};
      final daysWithLate = <String>{};

      for (var row in data) {
        final String? dateStr = row['date']?.toString();
        if (dateStr == null) continue;

        uniqueDays.add(dateStr);

        if (!groupedLogs.containsKey(dateStr)) {
          groupedLogs[dateStr] = row;
        } else {
          if (groupedLogs[dateStr]['check_out_time'] == null &&
              row['check_out_time'] != null) {
            groupedLogs[dateStr]['check_out_time'] = row['check_out_time'];
          }
          if (groupedLogs[dateStr]['check_in_time'] == null &&
              row['check_in_time'] != null) {
            groupedLogs[dateStr]['check_in_time'] = row['check_in_time'];
          }
        }

        if (row['is_late'] == true) {
          daysWithLate.add(dateStr);
        }
      }

      final List<dynamic> cleanHistory = groupedLogs.values.toList();
      cleanHistory.sort(
        (a, b) => b['date'].toString().compareTo(a['date'].toString()),
      );

      if (mounted) {
        setState(() {
          _history = cleanHistory;
          _workDays = uniqueDays.length;
          _lateTimes = daysWithLate.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Lỗi tải lịch sử công: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return "--:--";
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Lịch sử: ${widget.userName}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade100),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Tổng ngày công',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$_workDays ngày',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Số lần đi muộn',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$_lateTimes lần',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '📜 CHI TIẾT CÁC NGÀY LÀM VIỆC',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: _history.isEmpty
                        ? const Center(
                            child: Text(
                              'Nhân viên này chưa có dữ liệu công.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _history.length,
                            itemBuilder: (context, index) {
                              final log = _history[index];
                              final bool isLate = log['is_late'] ?? false;
                              final checkIn = log['check_in_time'] != null
                                  ? DateTime.parse(log['check_in_time'])
                                  : null;
                              final checkOut = log['check_out_time'] != null
                                  ? DateTime.parse(log['check_out_time'])
                                  : null;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isLate
                                        ? Colors.red.shade50
                                        : Colors.green.shade50,
                                    child: Icon(
                                      Icons.calendar_today_rounded,
                                      color: isLate ? Colors.red : Colors.green,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    'Ngày: ${log['date']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 16.0),
                                    child: Text(
                                      'Vào: ${_formatTime(checkIn)}  |  Ra: ${_formatTime(checkOut)}',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLate
                                          ? Colors.red.shade50
                                          : Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isLate ? 'Đi Muộn' : 'Đúng Giờ',
                                      style: TextStyle(
                                        color: isLate
                                            ? Colors.red.shade700
                                            : Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}