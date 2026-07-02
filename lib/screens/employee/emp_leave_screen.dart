import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  final supabase = Supabase.instance.client;
  final _reasonController = TextEditingController();
  
  String _selectedType = 'Nghỉ phép'; 
  DateTime _selectedDate = DateTime.now();
  bool _isSubmitting = false;
  
  List<dynamic> _myRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchMyRequests();
  }

  @override
  void dispose() {
    _reasonController.dispose(); // 🔥 Giải phóng bộ nhớ tránh leak và đơ phím
    super.dispose();
  }

  Future<void> _fetchMyRequests() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final data = await supabase
          .from('leave_requests')
          .select()
          .eq('user_id', user.id)
          .order('date', ascending: false);
          
      if (!mounted) return;
      setState(() {
        _myRequests = data;
      });
    } catch (e) {
      print("Lỗi tải lịch sử đơn: $e");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      if (!mounted) return;
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Vui lòng nhập lý do chi tiết!'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isSubmitting = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profileData = await supabase
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .single();
      
      final String empName = profileData['full_name'] ?? 'Nhên viên';

      await supabase.from('leave_requests').insert({
        'user_id': user.id,
        'employee_name': empName,
        'leave_type': _selectedType,
        'date': _selectedDate.toIso8601String().substring(0, 10),
        'reason': _reasonController.text.trim(),
        'status': 'Chờ duyệt',
      });

      _reasonController.clear();
      FocusScope.of(context).unfocus(); // 🔥 Ẩn bàn phím đi sau khi gửi đơn thành công
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🚀 Gửi đơn thành công, đang chờ Sếp duyệt!'), backgroundColor: Colors.green),
      );

      _fetchMyRequests();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi gửi đơn: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Đã duyệt': return Colors.green;
      case 'Từ chối': return Colors.red;
      default: return Colors.orange;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Nghỉ phép': return Colors.orange;
      case 'Xin đi muộn': return Colors.purple;
      case 'Xin về sớm': return Colors.pink;
      case 'Đi công tác': return Colors.teal;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 Giải pháp tối ưu: Chia giao diện làm 2 khối riêng biệt chống giật khung hình khi gõ phím
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📝 TẠO ĐƠN TRÌNH DUYỆT CÔNG TY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 12),

            // KHỐI 1: BỘ FORM ĐIỀN ĐƠN (Được bọc gọn chống tràn bàn phím)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(), 
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      labelText: 'Loại đơn xin',
                    ),
                    items: <String>['Nghỉ phép', 'Xin đi muộn', 'Xin về sớm', 'Đi công tác'].map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                    onChanged: (newValue) => setState(() => _selectedType = newValue!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}"),
                          const Icon(Icons.calendar_month, color: Colors.blue, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // 🔥 ĐÃ CẢI TIẾN: Ô nhập liệu chống hoàn toàn lỗi gõ dấu tiếng Việt
            TextField(
              controller: _reasonController,
              maxLines: 2,
              keyboardType: TextInputType.multiline, // Đảm bảo hỗ trợ nhập chuỗi nhiều dòng
              autocorrect: false,                     // ❌ Tắt tự sửa chính tả tiếng Anh gây nuốt dấu
              enableSuggestions: true,               // Bật gợi ý từ của bàn phím tiếng Việt
              textCapitalization: TextCapitalization.sentences, // Tự động viết hoa đầu câu chuẩn chỉ
              decoration: const InputDecoration(
                hintText: 'Nhập lý do chi tiết (Ví dụ: gặp đối tác, hỏng xe)...', 
                border: OutlineInputBorder()
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitRequest,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: _isSubmitting 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text('GỬI ĐƠN LÊN HỆ THỐNG', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              ),
            ),
            
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            
            const Text('📋 LỊCH SỬ ĐƠN TỪ ĐÃ GỬI', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 10),

            // KHỐI 2: DANH SÁCH LỊCH SỬ ĐƠN
            Expanded(
              child: _myRequests.isEmpty
                  ? const Center(child: Text('Bạn chưa gửi đơn từ nào.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)))
                  : RefreshIndicator(
                      onRefresh: _fetchMyRequests,
                      child: ListView.builder(
                        itemCount: _myRequests.length,
                        itemBuilder: (context, index) {
                          final request = _myRequests[index];
                          final String status = request['status'] ?? 'Chờ duyệt';
                          final String type = request['leave_type'] ?? 'Nghỉ phép';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getTypeColor(type).withOpacity(0.12),
                                child: Icon(Icons.description_rounded, color: _getTypeColor(type), size: 20),
                              ),
                              title: Text(
                                '$type - Ngày ${request['date']}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text('Lý do: ${request['reason']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}