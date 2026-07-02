import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminRuleSettingsView extends StatefulWidget {
  const AdminRuleSettingsView({super.key});

  @override
  State<AdminRuleSettingsView> createState() => _AdminRuleSettingsViewState();
}

class _AdminRuleSettingsViewState extends State<AdminRuleSettingsView> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isSaving = false;

  // --- CÁC BỘ ĐIỀU KHIỂN NHẬP LIỆU (CONTROLLERS) ---
  final _wifiController = TextEditingController();
  final _workHoursController = TextEditingController();
  final _startTimeController = TextEditingController();
  final _lunchStartController = TextEditingController();
  final _lunchEndController = TextEditingController();
  
  final _maxLateEarlyController = TextEditingController();
  final _maxHoursPerTurnController = TextEditingController();
  final _halfDayHoursController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCompanySettings();
  }

  @override
  void dispose() {
    _wifiController.dispose();
    _workHoursController.dispose();
    _startTimeController.dispose();
    _lunchStartController.dispose();
    _lunchEndController.dispose();
    _maxLateEarlyController.dispose();
    _maxHoursPerTurnController.dispose();
    _halfDayHoursController.dispose();
    super.dispose();
  }

  // 🔄 ĐỌC TỰ ĐỘNG DỮ LIỆU ĐÃ CÀI ĐẶT SẴN TỪ SUPABASE ĐỂ ĐỔ LÊN FORM
  Future<void> _loadCompanySettings() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await supabase
          .from('company_settings')
          .select()
          .eq('id', 'wifi_setting')
          .maybeSingle();

      if (data != null) {
        // Gán dữ liệu cũ để khi sếp vào xem là thấy luôn giờ giấc đã thiết lập
        _wifiController.text = data['wifi_name'] ?? '';
        _startTimeController.text = data['start_work_time'] ?? '08:00';
        _workHoursController.text = (data['work_hours_required'] ?? 8.0).toString();
        _lunchStartController.text = data['lunch_start_time'] ?? '12:00';
        _lunchEndController.text = data['lunch_end_time'] ?? '13:00';
        
        _maxLateEarlyController.text = (data['max_late_early_per_month'] ?? 4).toString();
        _maxHoursPerTurnController.text = (data['max_hours_per_turn'] ?? 2.0).toString();
        _halfDayHoursController.text = (data['half_day_hours'] ?? 4.0).toString();
      }
    } catch (e) {
      print("Lỗi tải dữ liệu cấu hình: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💾 LƯU TOÀN BỘ CẤU HÌNH XUỐNG DATABASE
  Future<void> _saveAllSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await supabase.from('company_settings').update({
        'wifi_name': _wifiController.text.trim(),
        'start_work_time': _startTimeController.text.trim(),
        'work_hours_required': double.tryParse(_workHoursController.text.trim()) ?? 8.0,
        'lunch_start_time': _lunchStartController.text.trim(),
        'lunch_end_time': _lunchEndController.text.trim(),
        'max_late_early_per_month': int.tryParse(_maxLateEarlyController.text.trim()) ?? 4,
        'max_hours_per_turn': double.tryParse(_maxHoursPerTurnController.text.trim()) ?? 2.0,
        'half_day_hours': double.tryParse(_halfDayHoursController.text.trim()) ?? 4.0,
      }).eq('id', 'wifi_setting');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 Đã cập nhật toàn bộ quy chế thành công!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Thất bại: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 2 Tab: Hành chính văn phòng & Quy chế đi muộn
      child: Scaffold(
        appBar: AppBar(
          title: const Text('⚙️ THIẾT LẬP CẤU HÌNH CÔNG TY', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.business_rounded), text: 'Hành chính & Wifi'),
              Tab(icon: Icon(Icons.gavel_rounded), text: 'Quy chế đi muộn'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Nội dung thay đổi động giữa các Tab bên dưới
                    Expanded(
                      child: TabBarView(
                        children: [
                          // ===================================================
                          // TAB 1: THÔNG SỐ VĂN PHÒNG (Hình ảnh 1 của bạn)
                          // ===================================================
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ListView(
                              children: [
                                Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  color: Colors.blue.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.wifi_tethering_rounded, color: Colors.blue),
                                            SizedBox(width: 8),
                                            Text('CẤU HÌNH QUY CHẾ CÔNG TY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          ],
                                        ),
                                        const Divider(),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: _wifiController,
                                          decoration: const InputDecoration(labelText: 'Tên Wifi văn phòng', isDense: true),
                                          validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _startTimeController,
                                                decoration: const InputDecoration(labelText: 'Giờ vào ca (Ví dụ: 08:00)', isDense: true),
                                                validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _workHoursController,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(labelText: 'Số tiếng cần làm (Ví dụ: 8.0)', isDense: true),
                                                validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: _lunchStartController,
                                                decoration: const InputDecoration(labelText: 'Bắt đầu nghỉ trưa', isDense: true),
                                                validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: TextFormField(
                                                controller: _lunchEndController,
                                                decoration: const InputDecoration(labelText: 'Kết thúc nghỉ trưa', isDense: true),
                                                validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ===================================================
                          // TAB 2: QUY ĐỊNH ĐI MUỘN / VỀ SỚM (Hình ảnh 2 của bạn)
                          // ===================================================
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: ListView(
                              children: [
                                Card(
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(
                                          children: [
                                            Icon(Icons.assignment_rounded, color: Colors.orange),
                                            SizedBox(width: 8),
                                            Text('📋 QUY ĐỊNH ĐI MUỘN / VỀ SỚM', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          ],
                                        ),
                                        const Divider(),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _maxLateEarlyController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(
                                            labelText: 'Số lần đi muộn/về sớm miễn phí tối đa trong tháng',
                                            suffixText: 'lần/tháng',
                                            border: OutlineInputBorder(),
                                          ),
                                          validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _maxHoursPerTurnController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                            labelText: 'Giới hạn số giờ muộn/sớm cho mỗi lần (nếu quá tính gấp đôi)',
                                            suffixText: 'giờ/lần',
                                            border: OutlineInputBorder(),
                                          ),
                                          validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _halfDayHoursController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: const InputDecoration(
                                            labelText: 'Mốc thời gian đi muộn/về sớm tính là nghỉ NỬA NGÀY',
                                            suffixText: 'giờ trở lên',
                                            border: OutlineInputBorder(),
                                          ),
                                          validator: (val) => val!.isEmpty ? 'Không được để trống' : null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // NÚT BẤM LƯU TỔNG CỐ ĐỊNH Ở ĐÁY MÀN HÌNH (DÙNG CHUNG CHO CẢ 2 TAB)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveAllSettings,
                          icon: _isSaving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.save_rounded),
                          label: const Text('LƯU TOÀN BỘ CẤU HÌNH QUY CHẾ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), // Bo tròn như ảnh của bạn
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}