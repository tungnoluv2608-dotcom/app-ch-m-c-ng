import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// Import các màn hình chính ở vòng ngoài
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Đưa plugin ra biến toàn cục để các file khác (như emp_home_view.dart) dễ dàng gọi dùng chung
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Cấu hình cài đặt ban đầu cho Android
  const AndroidInitializationSettings initializationSettingsAndroid = 
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  // 2. Cấu hình cài đặt ban đầu cho iOS (Dùng tên tham số rõ ràng nếu có cấu hình)
  const DarwinInitializationSettings initializationSettingsIOS = 
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
  
  // 3. Đóng gói tổng hợp (Gán đúng tên tham số 'android' và 'iOS')
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS, 
  );

  // Khởi tạo plugin
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  // 3. XIN QUYỀN HIỂN THỊ TRÊN ANDROID 13 TRỞ LÊN (Bắt buộc, nếu không máy sẽ chặn ngầm)
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await dotenv.load(fileName: ".env");

  // 3. ĐỌC KEY TỪ FILE .ENV THAY VÌ HARDCODE CHUỖI CHỮ NHƯ CŨ
  final String supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final String supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Chấm Công Phân Quyền',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// -----------------------------------------------------------------------------
// AUTH GATE: BỘ KIỂM TRA TRẠNG THÁI ĐĂNG NHẬP VÀ PHÂN QUYỀN REAL-TIME
// -----------------------------------------------------------------------------
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;
  
  bool _isCheckingProfile = false;
  String _employeeName = "";
  String _userRole = "employee"; 

  @override
  void initState() {
    super.initState();
    // Lắng nghe sự thay đổi trạng thái Auth (Đăng nhập / Đăng xuất) của Supabase
    supabase.auth.onAuthStateChange.listen((data) {
      final Session? session = data.session;
      if (session != null) {
        _getProfileData(session.user.id);
      } else {
        if (mounted) {
          setState(() {
            _employeeName = "";
            _userRole = "employee";
            _isCheckingProfile = false;
          });
        }
      }
    });
  }

  Future<void> _getProfileData(String userId) async {
    if (!mounted) return;
    setState(() => _isCheckingProfile = true);

    try {
      final data = await supabase
          .from('profiles')
          .select('full_name, role')
          .eq('id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _employeeName = data['full_name'] ?? "Nhân viên chưa đặt tên";
          _userRole = data['role'] ?? "employee";
        });
      }
    } catch (e) {
      print("Lỗi đồng bộ thông tin profiles tài khoản: $e");
    } finally {
      if (mounted) {
        setState(() => _isCheckingProfile = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return const LoginScreen();
    }

    if (_isCheckingProfile) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('🔄 Đang đồng bộ phân quyền tài khoản...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return HomeScreen(
      employeeName: _employeeName,
      userRole: _userRole,
    );
  }
}