// lib/models/account_balance_models.dart

/// [AccountBalanceBase] (abstract class): คลาสแม่แบบนามธรรมสำหรับโมเดลบัญชีเงินคงเหลือ
abstract class AccountBalanceBase {
  /// [accountId] (String): ID ของบัญชี ซึ่งโดยทั่วไปจะเป็น Primary ID ของผู้ที่เกี่ยวข้อง
  final String accountId;

  /// [balance] (int): ยอดเงินคงเหลือปัจจุบันของบัญชี เป็นจำนวนเต็ม (หน่วย: สตางค์ หรือ บาท*100)
  /// **หมายเหตุ:** แนะนำให้เก็บเป็น integer (เช่น สตางค์) เพื่อความแม่นยำในการคำนวณ
  int balance; // Made mutable to allow direct updates

  /// [lastUpdated] (DateTime): วันที่และเวลาล่าสุดที่มีการอัปเดตยอดเงินคงเหลือของบัญชีนี้
  DateTime lastUpdated; // Made mutable

  AccountBalanceBase({
    required this.accountId,
    required this.balance,
    required this.lastUpdated,
  });

  /// Method สำหรับแปลงอ็อบเจกต์เป็น Map<String, dynamic>
  /// เพื่อใช้กับ sqflite ในการ insert/update ข้อมูลลงตาราง
  Map<String, dynamic> toMap();

  /// Method สำหรับสร้างอ็อบเจกต์ใหม่พร้อมกับค่าที่อัปเดต (คล้ายๆ copyWith)
  AccountBalanceBase copyWithNewBalance({
    required int newBalance,
    required DateTime newLastUpdated,
  });
}

/// [MonkFundAtTreasurer] (class): โมเดลสำหรับยอดเงินคงเหลือของพระที่ฝากกับไวยาวัจกรณ์
/// ใน SQLite ตารางนี้จะมี composite primary key (accountId (monkPrimaryId), treasurerPrimaryId)
class MonkFundAtTreasurer extends AccountBalanceBase {
  /// [treasurerPrimaryId] (String): Primary ID ของไวยาวัจกรณ์ที่พระรูปนี้ฝากเงินไว้ด้วย
  final String treasurerPrimaryId;

  MonkFundAtTreasurer({
    required String monkPrimaryId, // นี่คือค่าที่จะถูกส่งไปให้ super.accountId
    required this.treasurerPrimaryId,
    required super.balance,
    required super.lastUpdated,
  }) : super(accountId: monkPrimaryId);

  /// getter เพื่อให้เข้าถึง monkPrimaryId (ซึ่งคือ accountId) ได้ง่ายและสื่อความหมาย
  String get monkPrimaryId => super.accountId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'accountId': super.accountId, // หรือ monkPrimaryId
      'treasurerPrimaryId': treasurerPrimaryId,
      'balance': super.balance,
      'lastUpdated': super.lastUpdated.toIso8601String(),
    };
  }

  factory MonkFundAtTreasurer.fromMap(Map<String, dynamic> map) {
    return MonkFundAtTreasurer(
      monkPrimaryId: map['accountId'] as String,
      treasurerPrimaryId: map['treasurerPrimaryId'] as String,
      balance: map['balance'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  @override
  MonkFundAtTreasurer copyWithNewBalance({
    required int newBalance,
    required DateTime newLastUpdated,
  }) {
    return MonkFundAtTreasurer(
      monkPrimaryId: super.accountId,
      treasurerPrimaryId: treasurerPrimaryId,
      balance: newBalance,
      lastUpdated: newLastUpdated,
    );
  }
}

/// [MonkFundAtDriver] (class): โมเดลสำหรับยอดเงินคงเหลือของพระที่ฝากกับคนขับรถ
/// ใน SQLite ตารางนี้จะมี composite primary key (accountId (monkPrimaryId), driverPrimaryId)
class MonkFundAtDriver extends AccountBalanceBase {
  /// [driverPrimaryId] (String): Primary ID ของคนขับรถที่พระรูปนี้ฝากเงินไว้ด้วย
  final String driverPrimaryId;

  MonkFundAtDriver({
    required String monkPrimaryId, // นี่คือค่าที่จะถูกส่งไปให้ super.accountId
    required this.driverPrimaryId,
    required super.balance,
    required super.lastUpdated,
  }) : super(accountId: monkPrimaryId);

  /// getter เพื่อให้เข้าถึง monkPrimaryId (ซึ่งคือ accountId) ได้ง่ายและสื่อความหมาย
  String get monkPrimaryId => super.accountId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'accountId': super.accountId, // หรือ monkPrimaryId
      'driverPrimaryId': driverPrimaryId,
      'balance': super.balance,
      'lastUpdated': super.lastUpdated.toIso8601String(),
    };
  }

  factory MonkFundAtDriver.fromMap(Map<String, dynamic> map) {
    return MonkFundAtDriver(
      monkPrimaryId: map['accountId'] as String,
      driverPrimaryId: map['driverPrimaryId'] as String,
      balance: map['balance'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  @override
  MonkFundAtDriver copyWithNewBalance({
    required int newBalance,
    required DateTime newLastUpdated,
  }) {
    return MonkFundAtDriver(
      monkPrimaryId: super.accountId,
      driverPrimaryId: driverPrimaryId,
      balance: newBalance,
      lastUpdated: newLastUpdated,
    );
  }
}

/// [DriverAdvanceAccount] (class): โมเดลสำหรับยอดเงินสำรองเดินทางของคนขับรถ
/// ใน SQLite ตารางนี้จะมี accountId (driverPrimaryId) เป็น PRIMARY KEY
class DriverAdvanceAccount extends AccountBalanceBase {
  DriverAdvanceAccount({
    required String
        driverPrimaryId, // นี่คือค่าที่จะถูกส่งไปให้ super.accountId
    required super.balance,
    required super.lastUpdated,
  }) : super(accountId: driverPrimaryId);

  /// getter เพื่อให้เข้าถึง driverPrimaryId (ซึ่งคือ accountId) ได้ง่ายและสื่อความหมาย
  String get driverPrimaryId => super.accountId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'accountId': super.accountId, // หรือ driverPrimaryId
      'balance': super.balance,
      'lastUpdated': super.lastUpdated.toIso8601String(),
    };
  }

  factory DriverAdvanceAccount.fromMap(Map<String, dynamic> map) {
    return DriverAdvanceAccount(
      driverPrimaryId: map['accountId'] as String,
      balance: map['balance'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  @override
  DriverAdvanceAccount copyWithNewBalance({
    required int newBalance,
    required DateTime newLastUpdated,
  }) {
    return DriverAdvanceAccount(
      driverPrimaryId: super.accountId,
      balance: newBalance,
      lastUpdated: newLastUpdated,
    );
  }
}

/// [TempleFundAccount] (class): โมเดลสำหรับยอดเงินกองกลางของวัด (ที่ไวยาวัจกรณ์ดูแล)
/// ใน SQLite ตารางนี้จะมี accountId (treasurerPrimaryId) เป็น PRIMARY KEY
class TempleFundAccount extends AccountBalanceBase {
  TempleFundAccount({
    required String
        treasurerPrimaryId, // นี่คือค่าที่จะถูกส่งไปให้ super.accountId
    required super.balance,
    required super.lastUpdated,
  }) : super(accountId: treasurerPrimaryId);

  /// getter เพื่อให้เข้าถึง treasurerPrimaryId (ซึ่งคือ accountId) ได้ง่ายและสื่อความหมาย
  String get treasurerPrimaryId => super.accountId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'accountId': super.accountId, // หรือ treasurerPrimaryId
      'balance': super.balance,
      'lastUpdated': super.lastUpdated.toIso8601String(),
    };
  }

  factory TempleFundAccount.fromMap(Map<String, dynamic> map) {
    return TempleFundAccount(
      treasurerPrimaryId: map['accountId'] as String,
      balance: map['balance'] as int,
      lastUpdated: DateTime.parse(map['lastUpdated'] as String),
    );
  }

  @override
  TempleFundAccount copyWithNewBalance({
    required int newBalance,
    required DateTime newLastUpdated,
  }) {
    return TempleFundAccount(
      treasurerPrimaryId: super.accountId,
      balance: newBalance,
      lastUpdated: newLastUpdated,
    );
  }
}
