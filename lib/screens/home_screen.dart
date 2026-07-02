import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Import các file nằm trong thư mục admin
import 'admin/admin_dashboard_view.dart';
import 'admin/admin_hr_view.dart';
import 'admin/admin_leave_view.dart'; 
import 'admin/admin_rules_settings_view.dart'; 

// Import các file nằm trong thư mục employee
import 'employee/emp_home_view.dart';
import 'employee/emp_profile_view.dart';
import 'employee/emp_leave_screen.dart';   

class HomeScreen extends StatefulWidget {
  final String employeeName;
  final String userRole;

  const HomeScreen({super.key, required this.employeeName, required this.userRole});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Hàm đăng xuất
  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = widget.userRole == 'admin';

    // 1. Định nghĩa danh sách các màn hình (Tab) dựa theo Quyền tài khoản
    final List<Widget> screens = isAdmin
        ? [
            // 🔥 ĐÃ SỬA: Thêm const và truyền tham số sạch chuẩn cấu trúc Class Component Widget
            const AdminDashboardView(employeeName: 'Admin'), 
            const AdminLeaveView(),                          
            const AdminHrView(),                             
          ]
        : [
            EmpHomeView(employeeName: widget.employeeName),   
            const LeaveScreen(),                              
            EmpProfileView(employeeName: widget.employeeName),
          ];

    // 2. Định nghĩa các nhãn BottomNavigationBar tương ứng
    final List<BottomNavigationBarItem> navItems = isAdmin
        ? const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Tổng quan'),
            BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Đơn từ'),
            BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Nhân sự'),
          ]
        : const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Trang chủ'),
            BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Đơn từ'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Cá nhân'),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isAdmin ? 'ỨNG DỤNG QUẢN LÝ (ADMIN)' : 'ỨNG DỤNG CHẤM CÔNG',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: Colors.blue,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Đăng xuất',
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: navItems,
      ),
    );
  }
}