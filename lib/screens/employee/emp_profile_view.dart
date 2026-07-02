import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmpProfileView extends StatefulWidget {
  final String employeeName;
  const EmpProfileView({super.key, required this.employeeName});

  @override
  State<EmpProfileView> createState() => _EmpProfileViewState();
}

class _EmpProfileViewState extends State<EmpProfileView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  List<dynamic> _attendanceHistory = [];
  int _totalWorkingDays = 0;
  int _totalLateTimes = 0;

  @override
  void initState() {
    super.initState();
    _fetchAttendanceHistory();
  }

Future<void> _fetchAttendanceHistory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // 1. Tải toàn bộ log từ Database về
      final data = await supabase
          .from('attendance_logs')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false);

      // 2. BỘ LỌC THÔNG MINH: Gộp các dòng trùng ngày thành 1 dòng hiển thị duy nhất
      final Map<String, dynamic> groupedLogs = {};
      final uniqueDays = <String>{};
      final daysWithLate = <String>{};

      for (var row in data) {
        final String? dateStr = row['date']?.toString();
        if (dateStr == null) continue;

        uniqueDays.add(dateStr);

        // Nếu ngày này chưa có trong danh sách gộp, hoặc dòng hiện tại có chứa giờ check-in/check-out đầy đủ hơn thì đè vào
        if (!groupedLogs.containsKey(dateStr)) {
          groupedLogs[dateStr] = row;
        } else {
          // Ưu tiên giữ lại dòng có check_in_time và check_out_time chuẩn nhất
          if (groupedLogs[dateStr]['check_out_time'] == null && row['check_out_time'] != null) {
            groupedLogs[dateStr]['check_out_time'] = row['check_out_time'];
          }
          if (groupedLogs[dateStr]['check_in_time'] == null && row['check_in_time'] != null) {
            groupedLogs[dateStr]['check_in_time'] = row['check_in_time'];
          }
        }

        // Kiểm tra đi muộn: Chỉ ghi nhận đi muộn nếu dòng đó thực sự bị đánh dấu là đi muộn
        if (row['is_late'] == true) {
          daysWithLate.add(dateStr);
        }
      }

      // Chuyển Map đã lọc trùng thành danh sách hiển thị trên ListView công khai
      final List<dynamic> cleanHistory = groupedLogs.values.toList();
      // Sắp xếp lại lịch sử theo ngày mới nhất lên đầu
      cleanHistory.sort((a, b) => b['date'].toString().compareTo(a['date'].toString()));
      if (!mounted) return;
      setState(() {
        _attendanceHistory = cleanHistory;       // ✅ Lịch sử sạch, không trùng dòng
        _totalWorkingDays = uniqueDays.length;   // ✅ Số công chuẩn xác
        _totalLateTimes = daysWithLate.length;   // ✅ Số ngày đi muộn chuẩn xác
      });
    } catch (e) {
      print("Lỗi tải lịch sử công: $e");
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return "--:--";
    try {
      final dateTime = DateTime.parse(isoString);
      return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "--:--";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thông tin cá nhân cơ bản
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.blue.shade100,
                child: Text(
                  widget.employeeName.isNotEmpty ? widget.employeeName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.employeeName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('Chức vụ: Nhân viên', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Thống kê số ngày công & đi muộn
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('Số ngày công', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Text('$_totalWorkingDays', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text('Số lần đi muộn', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Text('$_totalLateTimes', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('📜 LỊCH SỬ CHẤM CÔNG THÁNG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 12),

          // Danh sách lịch sử hiển thị
          Expanded(
            child: _attendanceHistory.isEmpty
                ? const Center(child: Text('Chưa có dữ liệu chấm công nào.'))
                : ListView.builder(
                    itemCount: _attendanceHistory.length,
                    itemBuilder: (context, index) {
                      final log = _attendanceHistory[index];
                      final bool isLate = log['is_late'] ?? false;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ListTile(
                          leading: Icon(Icons.calendar_today, color: isLate ? Colors.orange : Colors.blue),
                          title: Text('Ngày: ${log['date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Vào: ${_formatTime(log['check_in_time'])} | Ra: ${_formatTime(log['check_out_time'])}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: isLate ? Colors.red.shade100 : Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              isLate ? 'Đi Muộn' : 'Đúng Giờ',
                              style: TextStyle(color: isLate ? Colors.red.shade700 : Colors.green.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
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