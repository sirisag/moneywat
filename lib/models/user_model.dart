// lib/models/user_model.dart

/// [UserRole] (enum): บทบาทของผู้ใช้งานในระบบ
/// ใช้เพื่อกำหนดสิทธิ์การเข้าถึงและหน้าจอที่แตกต่างกันสำหรับผู้ใช้แต่ละประเภท
enum UserRole {
  treasurer, // ไวยาวัจกรณ์
  driver, // คนขับรถ
  monk, // พระ
}

/// [User] (class): โมเดลสำหรับจัดเก็บข้อมูลผู้ใช้งาน
/// เก็บข้อมูลพื้นฐานที่จำเป็นสำหรับผู้ใช้ทุกคนในระบบ
class User {
  /// [primaryId] (String): ID หลักของผู้ใช้ ที่เราใช้ใน business logic
  /// - ไวยาวัจกรณ์: PIN 4 หลัก (ผู้ใช้กำหนดเอง)
  /// - คนขับรถ: ตัวเลข 5 หลัก (ระบบสุ่ม)
  /// - พระ: ตัวเลข 6 หลัก (ระบบสุ่ม)
  /// ใน SQLite, primaryId จะเป็น PRIMARY KEY ของตาราง users
  final String primaryId;

  /// [secondaryId] (String): ID รองของผู้ใช้ (ระบบสุ่มให้)
  /// - ไวยาวัจกรณ์: ตัวเลข 4 หลัก
  /// - คนขับรถ: ตัวเลข 5 หลัก
  /// - พระ: ตัวเลข 6 หลัก
  /// ใช้สำหรับการตรวจสอบความถูกต้องของข้อมูลภายในระบบ และอาจใช้ในการกู้คืนบัญชี
  final String secondaryId;

  /// [displayName] (String): ชื่อที่ใช้แสดงผลในแอปพลิเคชันและรายงานต่างๆ
  /// ตั้งค่าเมื่อสร้างบัญชี และไม่สามารถเปลี่ยนแปลงได้ในภายหลัง
  final String displayName;

  /// [role] (UserRole): บทบาทของผู้ใช้ในระบบ (ไวยาวัจกรณ์, คนขับรถ, หรือ พระ)
  /// SQLite จะเก็บค่านี้เป็น String (ชื่อของ enum)
  final UserRole role;

  /// [hashedPin] (String?): ค่า hash ของรหัส PIN ที่ใช้สำหรับเข้าสู่ระบบแอปพลิเคชัน
  /// เก็บเป็นค่า hash เพื่อความปลอดภัย ไม่เก็บ PIN โดยตรง
  final String? hashedPin;

  /// Constructor หลักสำหรับสร้างอ็อบเจกต์ User
  User({
    required this.primaryId,
    required this.secondaryId,
    required this.displayName,
    required this.role,
    this.hashedPin,
  });

  User copyWith({
    String? primaryId,
    String? secondaryId,
    String? displayName,
    UserRole? role,
    String? hashedPin,
  }) {
    return User(
      primaryId: primaryId ?? this.primaryId,
      secondaryId: secondaryId ?? this.secondaryId,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      // If 'hashedPin' parameter is provided (not null), use it.
      // Otherwise, use the current instance's 'this.hashedPin'.
      hashedPin: hashedPin ?? this.hashedPin,
    );
  }

  /// Method สำหรับแปลงอ็อบเจกต์ User เป็น Map<String, dynamic>
  /// เพื่อใช้กับ sqflite ในการ insert/update ข้อมูลลงตาราง
  Map<String, dynamic> toMap({bool forFileExport = false}) {
    final Map<String, dynamic> map = {
      'primaryId': primaryId,
      'secondaryId': secondaryId,
      'displayName': displayName,
      'role': role.name, // เก็บชื่อของ enum เป็น String
    };
    if (!forFileExport) {
      // Only include hashedPin for local database storage, not for file export
      map['hashedPin'] = hashedPin;
    }
    return map;
  }

  /// Factory constructor สำหรับสร้างอ็อบเจกต์ User จาก Map<String, dynamic>
  /// ที่อ่านมาจากฐานข้อมูล sqflite
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      primaryId: map['primaryId'] as String,
      secondaryId: map['secondaryId'] as String,
      displayName: map['displayName'] as String,
      role: UserRole.values
          .byName(map['role'] as String), // แปลง String กลับเป็น enum
      hashedPin: map['hashedPin'] as String?,
    );
  }
}
