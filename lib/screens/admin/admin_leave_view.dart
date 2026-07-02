import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class AdminLeaveView extends StatefulWidget {
  const AdminLeaveView({super.key});

  @override
  State<AdminLeaveView> createState() => _AdminLeaveViewState();
}

class _AdminLeaveViewState extends State<AdminLeaveView> {
  final supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Số lượng đơn ĐANG CHỜ DUYỆT hiển thị trên 4 ô thẻ Stats
  int _countAllPending = 0;
  int _countLeavePending = 0;
  int _countLatePending = 0;
  int _countTripPending = 0;

  List<dynamic> _allRequests = [];    // Lưu toàn bộ đơn để truyền sang màn hình lọc & xuất file
  List<dynamic> _top5PendingRequests = []; // Top 5 đơn ĐANG CHỜ DUYỆT hiển thị ở trang chủ đơn từ

  @override
  void initState() {
    super.initState();
    _fetchPendingRequests();
  }

  // 🔄 TRUY VẤN TOÀN BỘ ĐƠN TỪ VÀ PHÂN LOẠI CHUẨN XÁC THEO DATABASE REAL-TIME
  Future<void> _fetchPendingRequests() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('leave_requests')
          .select()
          .order('date', ascending: false); // Đơn mới nhất xếp lên đầu

      final List<dynamic> requests = data as List<dynamic>;

      // 1. Chỉ đếm số lượng các đơn ĐANG CHỜ DUYỆT để hiển thị lên 4 thẻ Stats ở trên
      int allPending = requests.where((r) => r['status'] == 'Chờ duyệt').length;
      int leavePending = requests.where((r) => r['leave_type'] == 'Nghỉ phép' && r['status'] == 'Chờ duyệt').length;
      
      // Chấp nhận cả 'Xin đi muộn', 'Đi muộn' (dữ liệu cũ) và 'Xin về sớm'
      int latePending = requests.where((r) => 
        (r['leave_type'] == 'Xin đi muộn' || r['leave_type'] == 'Đi muộn' || r['leave_type'] == 'Xin về sớm') 
        && r['status'] == 'Chờ duyệt'
      ).length;
      
      int tripPending = requests.where((r) => r['leave_type'] == 'Đi công tác' && r['status'] == 'Chờ duyệt').length;

      // 2. Lọc riêng danh sách Chờ duyệt để hiển thị ở mục xử lý nhanh
      final List<dynamic> onlyPendingList = requests.where((r) => r['status'] == 'Chờ duyệt').toList();

      if (mounted) {
        setState(() {
          _allRequests = requests; 
          _countAllPending = allPending;
          _countLeavePending = leavePending;
          _countLatePending = latePending;
          _countTripPending = tripPending;
          _top5PendingRequests = onlyPendingList.take(5).toList();
        });
      }
    } catch (e) {
      print("Lỗi tải đơn từ phía Admin: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 📥 HÀM XỬ LÝ XUẤT FILE EXCEL SỔ THEO DÕI ĐƠN TỪ VÀ TỰ ĐỘNG BẬT BẢNG SHARE
  Future<void> _exportToExcel() async {
    if (_allRequests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Không có dữ liệu đơn từ để xuất file!'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Hiện loading nhẹ trong lúc xử lý file dữ liệu lớn
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Row(children: [CircularProgressIndicator(), SizedBox(width: 12), Text('Đang khởi tạo file Excel... ')]), backgroundColor: Colors.blueGrey, duration: Duration(seconds: 1)),
    );

    try {
      // 1. Khởi tạo một Workbook Excel mới
      var excel = Excel.createExcel();
      Sheet sheetObject = excel['So_Theo_Doi_Don_Tu'];
      excel.delete('Sheet1'); // Xóa sheet trắng mặc định

      // 2. Thiết kế Style cao cấp cho hàng Tiêu đề (Header)
      CellStyle headerStyle = CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.blueGrey800, // Nền xám đậm quyền lực
        horizontalAlign: HorizontalAlign.Center,
      );

      // 3. Khai báo tiêu đề các cột đúng chuẩn mô tả nghiệp vụ
      List<String> headers = ["STT", "Họ và Tên", "Loại Đơn", "Ngày Áp Dụng", "Lý Lý Chi Tiết", "Trạng Thái"];
      sheetObject.appendRow(headers.map((e) => TextCellValue(e)).toList());

      // Đổ màu nền và khóa chữ đậm cho hàng tiêu đề (Hàng 0)
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.cellStyle = headerStyle;
      }

      // 4. Duyệt mảng đổ toàn bộ dữ liệu thô từ Supabase vào từng hàng
      for (int index = 0; index < _allRequests.length; index++) {
        final request = _allRequests[index];
        List<CellValue> row = [
          IntCellValue(index + 1), // Cột STT dạng số
          TextCellValue(request['employee_name'] ?? 'Không rõ'),
          TextCellValue(request['leave_type'] ?? 'Nghỉ phép'),
          TextCellValue(request['date'] ?? ''),
          TextCellValue(request['reason'] ?? 'Không có lý do'),
          TextCellValue(request['status'] ?? 'Chờ duyệt'),
        ];
        sheetObject.appendRow(row);
      }

      // 5. Gói luồng bytes và lưu tệp vào thư mục tạm (Cache) của điện thoại
      var fileBytes = excel.save();
      final directory = await getTemporaryDirectory();
      
      // Định danh tên file kèm dấu mốc thời gian để tránh trùng tệp cũ
      String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
      String filePath = "${directory.path}/So_Theo_Doi_Don_Tu_$timeStamp.xlsx";
      
      File file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      // 6. 🔥 BẬT HỘP THOẠI SHARE ĐA NĂNG CỦA HỆ ĐIỀU HÀNH
      final xFile = XFile(filePath);
      await Share.shareXFiles(
        [xFile], 
        text: 'Gửi phòng Nhân sự / Kế toán file tổng hợp danh sách đơn từ của nhân viên công ty.',
      );

    } catch (e) {
      print("Lỗi trong quá trình xuất file Excel: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi xuất file: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ⚡ XỬ LÝ DUYỆT / TỪ CHỐI ĐƠN NHANH TRÊN DATABASE
  Future<void> _updateRequestStatus(String requestId, String newStatus) async {
    try {
      await supabase
          .from('leave_requests')
          .update({'status': newStatus})
          .eq('id', requestId);

      await _fetchPendingRequests(); // Tải lại dữ liệu sau khi duyệt

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 Đã cập nhật đơn sang trạng thái: $newStatus', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            backgroundColor: newStatus == 'Đã duyệt' ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật đơn: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getTypeColor(String type) {
    if (type == 'Nghỉ phép') return Colors.orange;
    if (type == 'Xin đi muộn' || type == 'Đi muộn') return Colors.purple;
    if (type == 'Xin về sớm') return Colors.pink;
    if (type == 'Đi công tác') return Colors.teal;
    return Colors.blue;
  }

  void _navigateToLeaveFilter(String filterType, String title, Color pageColor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminLeaveTabContainerScreen(
          filterType: filterType,
          screenTitle: title,
          themeColor: pageColor,
          allRequests: _allRequests,
          onStatusUpdated: _fetchPendingRequests,
        ),
      ),
    );
  }

  Widget _buildClickableLeaveCard(String title, String value, Color color, IconData icon, VoidCallback onTap) {
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: _fetchPendingRequests,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TẦNG 1: HEADER TIÊU ĐỀ + 🔥 HỆ THỐNG NÚT DOWNLOAD EXCEL ĐÃ ĐƯỢC TÍCH HỢP ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📊 TRUNG TÂM DUYỆT ĐƠN TỪ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                        const SizedBox(height: 4),
                        Text('Có $_countAllPending đơn đang xếp hàng chờ duyệt', style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // 🔥 NÚT BẤM XUẤT FILE EXCEL CAO CẤP MÀU XANH LÁ
                      IconButton(
                        icon: const Icon(Icons.file_download_rounded, color: Colors.green, size: 30),
                        tooltip: 'Xuất file Excel tổng hợp đơn từ',
                        onPressed: _exportToExcel,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.cached_rounded, color: Colors.grey.shade700, size: 26), 
                        onPressed: _fetchPendingRequests,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // GRID CARD THỐNG KÊ SỐ ĐƠN CHỜ DUYỆT
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.35,
                children: [
                  _buildClickableLeaveCard('Tổng đơn chờ', '$_countAllPending', Colors.blue, Icons.all_inbox_rounded, () => _navigateToLeaveFilter('all', 'TẤT CẢ ĐƠN TỪ', Colors.blue)),
                  _buildClickableLeaveCard('Đơn Nghỉ Phép', '$_countLeavePending', Colors.orange, Icons.no_accounts_rounded, () => _navigateToLeaveFilter('leave', 'ĐƠN XIN NGHỈ PHÉP', Colors.orange)),
                  _buildClickableLeaveCard('Đơn Đi Muộn/Về Sớm', '$_countLatePending', Colors.purple, Icons.alarm_rounded, () => _navigateToLeaveFilter('late', 'ĐƠN ĐI MUỘN / VỀ SỚM', Colors.purple)),
                  _buildClickableLeaveCard('Đơn Công Tác', '$_countTripPending', Colors.teal, Icons.flight_takeoff_rounded, () => _navigateToLeaveFilter('trip', 'ĐƠN XIN ĐI CÔNG TÁC', Colors.teal)),
                ],
              ),
              const SizedBox(height: 24),

              // DANH SÁCH DUYỆT NHANH ĐƠN HÀNG CHỜ
              Row(
                children: [
                  Container(width: 4, height: 16, decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  const Text('ĐƠN MỚI ĐANG CHỜ DUYỆT GẤP', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                ],
              ),
              const SizedBox(height: 10),

              _top5PendingRequests.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: Text('🎉 Tuyệt vời! Không có đơn nào đang chờ duyệt.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 14))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _top5PendingRequests.length,
                      itemBuilder: (context, index) {
                        final request = _top5PendingRequests[index];
                        final String type = request['leave_type'] ?? 'Nghỉ phép';
                        final Color typeColor = _getTypeColor(type);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(request['employee_name'] ?? 'Nhân viên', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: typeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                      child: Text(type, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('📅 Ngày áp dụng: ${request['date']}', style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('💬 Lý do: ${request['reason']}', style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic, fontSize: 14)),
                                const Divider(height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _updateRequestStatus(request['id'], 'Từ chối'),
                                      icon: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                                      label: const Text('Từ chối', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton.icon(
                                      onPressed: () => _updateRequestStatus(request['id'], 'Đã duyệt'),
                                      icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                                      label: const Text('Duyệt đơn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
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
// 🔍 MÀN HÌNH CHI TIẾT CHIA PHÂN TÁCH TAB: "ĐANG CHỜ" & "LỊCH SỬ DUYỆT"
// ====================================================================
class AdminLeaveTabContainerScreen extends StatelessWidget {
  final String filterType;
  final String screenTitle;
  final Color themeColor;
  final List<dynamic> allRequests;
  final VoidCallback onStatusUpdated;

  const AdminLeaveTabContainerScreen({super.key, required this.filterType, required this.screenTitle, required this.themeColor, required this.allRequests, required this.onStatusUpdated});

  @override
  Widget build(BuildContext context) {
    List<dynamic> baseList = [];
    if (filterType == 'all') {
      baseList = allRequests;
    } else if (filterType == 'leave') {
      baseList = allRequests.where((r) => r['leave_type'] == 'Nghỉ phép').toList();
    } else if (filterType == 'late') {
      baseList = allRequests.where((r) => r['leave_type'] == 'Xin đi muộn' || r['leave_type'] == 'Đi muộn' || r['leave_type'] == 'Xin về sớm').toList();
    } else if (filterType == 'trip') {
      baseList = allRequests.where((r) => r['leave_type'] == 'Đi công tác').toList();
    }

    List<dynamic> pendingTabList = baseList.where((r) => r['status'] == 'Chờ duyệt').toList();
    List<dynamic> historyTabList = baseList.where((r) => r['status'] == 'Đã duyệt' || r['status'] == 'Từ chối').toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(screenTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: themeColor,
          iconTheme: const IconThemeData(color: Colors.white),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: 'ĐANG CHỜ DUYỆT'),
              Tab(text: 'LỊCH SỬ ĐÃ XỬ LÝ'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AdminLeaveInnerListView(requests: pendingTabList, isHistoryMode: false, themeColor: themeColor, onStatusUpdated: onStatusUpdated),
            AdminLeaveInnerListView(requests: historyTabList, isHistoryMode: true, themeColor: themeColor, onStatusUpdated: onStatusUpdated),
          ],
        ),
      ),
    );
  }
}

class AdminLeaveInnerListView extends StatefulWidget {
  final List<dynamic> requests;
  final bool isHistoryMode;
  final Color themeColor;
  final VoidCallback onStatusUpdated;

  const AdminLeaveInnerListView({super.key, required this.requests, required this.isHistoryMode, required this.themeColor, required this.onStatusUpdated});

  @override
  State<AdminLeaveInnerListView> createState() => _AdminLeaveInnerListViewState();
}

class _AdminLeaveInnerListViewState extends State<AdminLeaveInnerListView> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  List<dynamic> _displayList = [];

  @override
  void initState() {
    super.initState();
    _displayList = widget.requests;
  }

  @override
  void didUpdateWidget(covariant AdminLeaveInnerListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requests != widget.requests) {
      _displayList = widget.requests;
      _searchController.clear();
    }
  }

  void _filterSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() => _displayList = widget.requests);
      return;
    }
    final lowerQuery = query.toLowerCase();
    setState(() {
      _displayList = widget.requests.where((r) => (r['employee_name'] ?? '').toString().toLowerCase().contains(lowerQuery)).toList();
    });
  }

  Future<void> _innerUpdateStatus(String requestId, String newStatus) async {
    try {
      await supabase.from('leave_requests').update({'status': newStatus}).eq('id', requestId);
      widget.onStatusUpdated();
    } catch (e) {
      print(e);
    }
  }

  Color _getStatusColor(String status) {
    if (status == 'Đã duyệt') return Colors.green;
    if (status == 'Từ chối') return Colors.red;
    return Colors.orange;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12.0),
          color: widget.themeColor.withOpacity(0.1),
          child: TextField(
            controller: _searchController,
            onChanged: _filterSearch,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm tên nhân viên...',
              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              prefixIcon: Icon(Icons.search, size: 24, color: widget.themeColor),
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
              Text(widget.isHistoryMode ? 'Đơn từ đã giải quyết:' : 'Đơn từ đang đợi duyệt:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              Text('${_displayList.length} đơn', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: widget.themeColor)),
            ],
          ),
        ),
        Expanded(
          child: _displayList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_rounded, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 10),
                      Text('Không tìm thấy đơn từ nào.', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 15)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _displayList.length,
                  itemBuilder: (context, index) {
                    final request = _displayList[index];
                    final String name = request['employee_name'] ?? 'Không xác định';
                    final String type = request['leave_type'] ?? 'Nghỉ phép';
                    final String status = request['status'] ?? 'Chờ duyệt';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: widget.themeColor.withOpacity(0.12),
                                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: TextStyle(fontWeight: FontWeight.bold, color: widget.themeColor, fontSize: 20)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black)),
                                      const SizedBox(height: 4),
                                      Text('Loại đơn: $type', style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('📅 Ngày áp dụng: ${request['date']}', style: const TextStyle(fontSize: 15, color: Colors.black87, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Text('💬 Lý do: ${request['reason']}', style: TextStyle(fontSize: 15, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                            const Divider(height: 24),
                            
                            widget.isHistoryMode
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Trạng thái:', style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                        child: Text(status, style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 13)),
                                      )
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => _innerUpdateStatus(request['id'], 'Từ chối'),
                                        icon: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                                        label: const Text('Từ chối', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                      const SizedBox(width: 16),
                                      ElevatedButton.icon(
                                        onPressed: () => _innerUpdateStatus(request['id'], 'Đã duyệt'),
                                        icon: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                                        label: const Text('Duyệt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          elevation: 0,
                                        ),
                                      ),
                                    ],
                                  )
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}