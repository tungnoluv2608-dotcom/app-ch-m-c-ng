import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminDashboardView extends StatefulWidget {
  final String employeeName;

  const AdminDashboardView({super.key, required this.employeeName});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // 🔥 BIẾN LỌC NGÀY CHỦ ĐẠO TOÀN TRANG DASHBOARD
  DateTime _selectedDate = DateTime.now(); 

  // Biến đếm số liệu hệ thống
  int _countPresent = 0;
  int _countLate = 0;
  int _countPendingRequests = 0;
  int _countOnLeave = 0;        
  int _countBusinessTrip = 0;   

  List<dynamic> _allPresentLogs = []; 
  List<dynamic> _allApprovedRequests = []; 
  List<dynamic> _top5Employees = [];  

  @override
  void initState() {
    super.initState();
    _loadAdminDashboard();
  }

  // 🔄 TRUY VẤN DỮ LIỆU THEO NGÀY ĐƯỢC CHỌN TRÊN TRANG DASHBOARD
  Future<void> _loadAdminDashboard() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Ép chuỗi ngày được chọn dạng YYYY-MM-DD
      final targetDateStr = _selectedDate.toIso8601String().substring(0, 10);
      
      // Tạo mốc thời gian 24h của riêng ngày đó để quét log điểm danh sạch sẽ
      final startOfTargetDateStr = "${targetDateStr}T00:00:00";
      final endOfTargetDateStr = "${targetDateStr}T23:59:59";

      final results = await Future.wait<dynamic>([
        supabase.from('attendance_logs').select('*, profiles!inner(full_name, role, employee_code)').gte('check_in_time', startOfTargetDateStr).lte('check_in_time', endOfTargetDateStr).eq('profiles.role', 'employee'),
        supabase.from('leave_requests').select('id').eq('status', 'Chờ duyệt'),
        supabase.from('leave_requests').select('leave_type, employee_name, reason').eq('status', 'Đã duyệt').eq('date', targetDateStr),
      ]);

      final List<dynamic> attendanceToday = results[0] as List<dynamic>;
      final List<dynamic> pendingRequests = results[1] as List<dynamic>;
      final List<dynamic> approvedRequestsToday = results[2] as List<dynamic>;

      // Lọc trùng lặp log check-in
      final Map<String, dynamic> uniqueLogs = {};
      for (var log in attendanceToday) {
        final userId = log['user_id'];
        if (userId != null && log['profiles'] != null) {
          uniqueLogs[userId] = log;
        }
      }

      final List<dynamic> filteredEmployees = uniqueLogs.values.toList();
      filteredEmployees.sort((a, b) => b['check_in_time'].toString().compareTo(a['check_in_time'].toString()));

      int present = filteredEmployees.length;
      int lateCount = filteredEmployees.where((log) => log['is_late'] == true).length;
      int onLeave = approvedRequestsToday.where((r) => r['leave_type'] == 'Nghỉ phép').length;
      int businessTrip = approvedRequestsToday.where((r) => r['leave_type'] == 'Đi công tác').length;

      if (mounted) {
        setState(() {
          _countPresent = present;
          _countLate = lateCount;
          _countPendingRequests = pendingRequests.length;
          _countOnLeave = onLeave;
          _countBusinessTrip = businessTrip;
          _allPresentLogs = filteredEmployees;
          _allApprovedRequests = approvedRequestsToday;
          _top5Employees = filteredEmployees.take(5).toList();
        });
      }
    } catch (e) {
      print("Lỗi tải thông tin Dashboard Admin: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 📥 HÀM XUẤT BÁO CÁO NHẬT KÝ ĐIỂM DANH THEO NGÀY ĐANG CHỌN
  Future<void> _exportDashboardToExcel() async {
    if (_allPresentLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Không có dữ liệu điểm danh ngày này để xuất!'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      final String formatSelectedDate = "${_selectedDate.day.toString().padLeft(2, '0')}_${_selectedDate.month.toString().padLeft(2, '0')}_${_selectedDate.year}";
      
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['Diem_Danh_Ngay_$formatSelectedDate'];
      excel.delete('Sheet1');

      // Style Header màu xanh lục (Green) đồng bộ mốc "Có mặt"
      CellStyle headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.green700,
        horizontalAlign: HorizontalAlign.Center,
      );

      List<String> headers = ["STT", "Mã Nhân Viên", "Họ và Tên", "Giờ Vào Ca", "Trạng Thái", "Ghi Chú"];
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.cellStyle = headerStyle;
      }

      // Đổ dữ liệu log điểm danh
      for (int index = 0; index < _allPresentLogs.length; index++) {
        final log = _allPresentLogs[index];
        String rawTime = log['check_in_time'] ?? '';
        String formattedTime = rawTime.isNotEmpty && rawTime.contains('T') 
            ? rawTime.split('T')[1].substring(0, 5) 
            : '--:--';

        List<CellValue> row = [
          IntCellValue(index + 1),
          TextCellValue(log['profiles']?['employee_code'] ?? 'NV-XX'),
          TextCellValue(log['profiles']?['full_name'] ?? 'Không rõ'),
          TextCellValue(formattedTime),
          TextCellValue(log['is_late'] == true ? '💥 Muộn' : '✨ Đúng giờ'),
          TextCellValue(log['note'] ?? ''),
        ];
        sheetObject.appendRow(row);
      }

      var fileBytes = excel.save();
      final directory = await getTemporaryDirectory();
      String filePath = "${directory.path}/Bao_Cao_Cham_Cong_$formatSelectedDate.xlsx";
      
      File file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      await Share.shareXFiles([XFile(filePath)], text: 'Báo cáo điểm danh văn phòng ngày $formatSelectedDate');
    } catch (e) {
      print("Lỗi xuất file Dashboard: $e");
    }
  }

  // 🔥 HÀM BẬT LỊCH CHỌN NGÀY NGAY TẠI TRANG CHỦ
  Future<void> _selectDashboardDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.blue),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      await _loadAdminDashboard(); // Tải lại toàn bộ số liệu và biểu đồ theo ngày mới vừa chọn
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '--:--';
    try {
      final parts = dateTimeStr.split('T');
      if (parts.length > 1) {
        final timeParts = parts[1].split(':');
        if (timeParts.length > 1) return '${timeParts[0]}:${timeParts[1]}';
      }
    } catch (e) {
      print(e);
    }
    return '--:--';
  }

  void _navigateToDetailList(String filterMode, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminDetailListScreen(
          filterMode: filterMode,
          screenTitle: title,
          presentLogs: _allPresentLogs,
          approvedRequests: _allApprovedRequests,
          selectedDate: _selectedDate, // Truyền ngày sếp đang chọn sang màn hình con để đồng bộ luôn
        ),
      ),
    );
  }

  // 📊 WIDGET BIỂU ĐỒ TRÒN
  Widget _buildPieChartCard() {
    int total = _countPresent + _countOnLeave + _countBusinessTrip;
    if (total == 0) total = 1; 

    int onTimeCount = _countPresent - _countLate;
    if (onTimeCount < 0) onTimeCount = 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 TỶ LỆ QUÂN SỐ TRONG NGÀY',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 35,
                      sections: [
                        PieChartSectionData(color: Colors.green, value: onTimeCount.toDouble(), radius: 22, showTitle: false),
                        PieChartSectionData(color: Colors.red, value: _countLate.toDouble(), radius: 22, showTitle: false),
                        PieChartSectionData(color: Colors.teal, value: _countBusinessTrip.toDouble(), radius: 22, showTitle: false),
                        PieChartSectionData(color: Colors.orange, value: _countOnLeave.toDouble(), radius: 22, showTitle: false),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildIndicator(Colors.green, 'Đúng giờ ($onTimeCount)'),
                      const SizedBox(height: 8),
                      _buildIndicator(Colors.red, 'Đi muộn ($_countLate)'),
                      const SizedBox(height: 8),
                      _buildIndicator(Colors.teal, 'Công tác ($_countBusinessTrip)'),
                      const SizedBox(height: 8),
                      _buildIndicator(Colors.orange, 'Nghỉ phép ($_countOnLeave)'),
                    ],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(Color color, String text) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }

  Widget _buildClickableStatCard(String title, String value, Color color, IconData icon, VoidCallback onTap) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
              const Spacer(),
              Text(title, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String formatSelectedDate = "${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}";

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: _loadAdminDashboard,
        child: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- TẦNG 1: HEADER QUẢN TRỊ + 🔥 BỘ CHỌN LỊCH TRANG CHỦ ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('👑 Xin chào Sếp, ${widget.employeeName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                            const SizedBox(height: 4),
                            Text('Hệ thống điều hành tổng quan ngày công', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      
                      // 🔥 BỘ ĐIỀU KHIỂN: NÚT XUẤT EXCEL + WIDGET BẤM LỌC LỊCH NGÀY THÁNG NĂM
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.file_download_rounded, color: Colors.green, size: 30),
                            tooltip: 'Xuất báo cáo Excel ngày này',
                            onPressed: _exportDashboardToExcel,
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: _selectDashboardDate,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    formatSelectedDate,
                                    style: const TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // GRID CẤU TRÚC THẺ THỐNG KÊ BẤM ĐƯỢC
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14, 
                    mainAxisSpacing: 14,
                    childAspectRatio: 1.35, 
                    children: [
                      _buildClickableStatCard('Đang có mặt', '$_countPresent', Colors.green, Icons.person_add_alt_1_rounded, () => _navigateToDetailList('present', 'DANH SÁCH CÓ MẶT NGÀY $formatSelectedDate')),
                      _buildClickableStatCard('Đi muộn trong ngày', '$_countLate', Colors.red, Icons.alarm_on_rounded, () => _navigateToDetailList('late', 'DANH SÁCH ĐI MUỘN NGÀY $formatSelectedDate')),
                      _buildClickableStatCard('Đang đi công tác', '$_countBusinessTrip', Colors.teal, Icons.flight_takeoff_rounded, () => _navigateToDetailList('business', 'CÔNG TÁC NGÀY $formatSelectedDate')),
                      _buildClickableStatCard('Nghỉ phép/Vắng', '$_countOnLeave', Colors.orange, Icons.no_accounts_rounded, () => _navigateToDetailList('leave', 'NGHỈ PHÉP NGÀY $formatSelectedDate')),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // BIỂU ĐỒ TRÒN XU HƯỚNG QUÂN SỐ
                  _buildPieChartCard(),
                  const SizedBox(height: 18),

                  // BANNER CẢNH BÁO ĐƠN TỪ CHỜ DUYỆT
                  if (_countPendingRequests > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.shade300)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: const CircleAvatar(radius: 20, backgroundColor: Colors.amber, child: Icon(Icons.mail_outline_rounded, color: Colors.white, size: 22)),
                        title: Text('Có $_countPendingRequests đơn từ đang chờ sếp duyệt!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.black54),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // KHU VỰC THEO DÕI REAL-TIME TÓM TẮT (TỐI ĐA 5 NGƯỜI)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 8),
                          Text('LOG ĐIỂM DANH NGÀY $formatSelectedDate', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        ],
                      ),
                      TextButton(
                        onPressed: () => _navigateToDetailList('present', 'DANH SÁCH CÓ MẶT NGÀY $formatSelectedDate'),
                        child: const Text('Xem tất cả', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  _top5Employees.isEmpty
                      ? const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: Text('Không có ai check-in ngày này.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 13))))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _top5Employees.length,
                          itemBuilder: (context, index) {
                            final log = _top5Employees[index];
                            final String name = log['profiles']?['full_name'] ?? 'Nhân viên';
                            final bool isLate = log['is_late'] ?? false;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: CircleAvatar(radius: 20, backgroundColor: isLate ? Colors.red.shade50 : Colors.green.shade50, child: Icon(Icons.person, color: isLate ? Colors.red : Colors.green, size: 20)),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                subtitle: Text('Vào ca: ${_formatTime(log['check_in_time'])}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                trailing: Text(isLate ? '💥 Muộn' : '✨ Đúng giờ', style: TextStyle(color: isLate ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
      ),
    );
  }
}

// ====================================================================
// 📊 MÀN HÌNH HIỂN THỊ DANH SÁCH CHI TIẾT TỪNG LOẠI ĐƠN & THEO DÕI CÓ SEARCH
// ====================================================================
class AdminDetailListScreen extends StatefulWidget {
  final String filterMode;
  final String screenTitle;
  final List<dynamic> presentLogs;
  final List<dynamic> approvedRequests;
  final DateTime selectedDate; 

  const AdminDetailListScreen({super.key, required this.filterMode, required this.screenTitle, required this.presentLogs, required this.approvedRequests, required this.selectedDate});

  @override
  State<AdminDetailListScreen> createState() => _AdminDetailListScreenState();
}

class _AdminDetailListScreenState extends State<AdminDetailListScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _displayList = [];
  List<dynamic> _fullFilteredList = [];

  @override
  void initState() {
    super.initState();
    _processDataFilter();
  }

  void _processDataFilter() {
    List<dynamic> temp = [];
    if (widget.filterMode == 'present') {
      temp = widget.presentLogs;
    } else if (widget.filterMode == 'late') {
      temp = widget.presentLogs.where((log) => log['is_late'] == true).toList();
    } else if (widget.filterMode == 'leave') {
      temp = widget.approvedRequests.where((r) => r['leave_type'] == 'Nghỉ phép').toList();
    } else if (widget.filterMode == 'business') {
      temp = widget.approvedRequests.where((r) => r['leave_type'] == 'Đi công tác').toList();
    }

    setState(() {
      _fullFilteredList = temp;
      _displayList = temp;
    });
  }

  void _filterSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() => _displayList = _fullFilteredList);
      return;
    }
    
    List<dynamic> result = [];
    final lowerQuery = query.toLowerCase();

    for (var item in _fullFilteredList) {
      String name = '';
      if (widget.filterMode == 'present' || widget.filterMode == 'late') {
        name = item['profiles']?['full_name']?.toString() ?? '';
      } else {
        name = item['employee_name']?.toString() ?? '';
      }
      
      if (name.toLowerCase().contains(lowerQuery)) {
        result.add(item);
      }
    }

    setState(() => _displayList = result);
  }

  Color _getThemeColor() {
    switch (widget.filterMode) {
      case 'present': return Colors.green;
      case 'late': return Colors.red;
      case 'business': return Colors.teal;
      case 'leave': return Colors.orange;
      default: return Colors.blue;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isAttendanceMode = widget.filterMode == 'present' || widget.filterMode == 'late';
    final Color mainColor = _getThemeColor();
    final String dateLabel = "${widget.selectedDate.day.toString().padLeft(2, '0')}/${widget.selectedDate.month.toString().padLeft(2, '0')}/${widget.selectedDate.year}";

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(widget.screenTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: mainColor,
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
        elevation: 0,
      ),
      body: Column(
        children: [
          // THANH TÌM KIẾM
          Container(
            padding: const EdgeInsets.all(12.0),
            color: mainColor.withOpacity(0.1),
            child: TextField(
              controller: _searchController,
              onChanged: _filterSearch,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên nhân viên nhanh...',
                hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                prefixIcon: Icon(Icons.search, size: 24, color: mainColor),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Danh sách ngày $dateLabel:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                Text('${_displayList.length} nhân sự', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: mainColor)),
              ],
            ),
          ),

          // LIST HIỂN THỊ CHI TIẾT NHÂN VIÊN
          Expanded(
            child: _displayList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open_rounded, size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text('Không tìm thấy ai trong danh mục ngày này.', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 15)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _displayList.length,
                    itemBuilder: (context, index) {
                      final item = _displayList[index];
                      
                      String name = isAttendanceMode ? (item['profiles']?['full_name'] ?? 'Không xác định') : (item['employee_name'] ?? 'Không xác định');
                      String code = isAttendanceMode ? (item['profiles']?['employee_code'] ?? 'NV-XX') : 'Đã duyệt';
                      String note = isAttendanceMode ? (item['note'] ?? '') : '';

                      String subtitleText = isAttendanceMode
                          ? 'Vào ca: ${item['check_in_time'].toString().replaceAll('T', ' ').substring(11, 16)}'
                          : 'Lý do: ${item['reason'] ?? "Không có"}';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 25,
                                backgroundColor: mainColor.withOpacity(0.12),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: TextStyle(fontWeight: FontWeight.bold, color: mainColor, fontSize: 20)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black)),
                                    const SizedBox(height: 4),
                                    Text(isAttendanceMode ? 'Mã số: $code' : 'Trạng thái: $code', style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text(subtitleText, style: TextStyle(fontSize: 15, color: Colors.grey.shade900, fontWeight: FontWeight.w500)),
                                    if (note.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(note, style: TextStyle(fontSize: 13, color: item['is_late'] == true ? Colors.purple : Colors.teal, fontWeight: FontWeight.bold)),
                                    ]
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: mainColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                  isAttendanceMode ? (item['is_late'] == true ? '💥 Muộn' : '✨ Đúng giờ') : (item['leave_type'] ?? 'Đơn từ'),
                                  style: TextStyle(color: mainColor, fontWeight: FontWeight.bold, fontSize: 13), 
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}