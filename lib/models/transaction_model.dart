// lib/models/transaction_model.dart

import 'package:uuid/uuid.dart'; // For generating UUIDs

// Special Account IDs for external sources/destinations
const String EXTERNAL_SOURCE_ACCOUNT_ID =
    "EXTERNAL_SOURCE"; // For general income not from a user
const String EXPENSE_DESTINATION_ACCOUNT_ID =
    "EXPENSE_DESTINATION"; // For general expenses not to a user

/// [TransactionType] (enum): ประเภทของธุรกรรม
/// ใช้เพื่อจำแนกและกำหนดลักษณะการทำงานของแต่ละธุรกรรม
enum TransactionType {
  // --- Transactions initiated by/related to Driver ---
  /// พระฝากเงินให้คนขับรถ
  DEPOSIT_FROM_MONK_TO_DRIVER,

  /// คนขับรถเบิกเงินให้พระ (จากยอดที่พระฝากไว้กับคนขับ)
  WITHDRAWAL_FOR_MONK_FROM_DRIVER,

  /// คนขับรถบันทึกค่าใช้จ่ายในการเดินทาง (หักจากเงินสำรองของคนขับ)
  TRIP_EXPENSE_BY_DRIVER,

  /// คนขับรถบันทึกรายรับสำหรับค่าเดินทาง (เช่น เงินทำบุญค่าน้ำมัน เพิ่มเข้าเงินสำรองของคนขับ)
  TRIP_INCOME_FOR_DRIVER,

  /// คนขับรถได้รับเงินสำรองเดินทางจากไวยาวัจกรณ์ (อาจบันทึกอัตโนมัติเมื่อ import file หรือไวยาวัจกรณ์บันทึก)
  RECEIVE_DRIVER_ADVANCE,

  /// คนขับรถคืนเงินสำรองเดินทางที่เหลือให้ไวยาวัจกรณ์
  RETURN_DRIVER_ADVANCE_TO_TREASURER,

  /// คนขับรถรับเงินฝากของพระมาจากไวยาวัจกรณ์ (ไวยาวัจกรณ์โอนยอดของพระมาให้คนขับดูแลต่อ)
  RECEIVE_MONK_FUND_FROM_TREASURER,

  // --- Transactions initiated by/related to Treasurer (Temple's main account) ---
  /// รายรับของวัด (เช่น เงินบริจาคทั่วไป)
  TEMPLE_INCOME,

  /// รายจ่ายของวัด (เช่น ค่าน้ำค่าไฟวัด)
  TEMPLE_EXPENSE,

  /// ไวยาวัจกรณ์ให้เงินสำรองเดินทางแก่คนขับรถ
  GIVE_DRIVER_ADVANCE,
  // RECEIVE_RETURNED_DRIVER_ADVANCE, // Covered by RETURN_DRIVER_ADVANCE_TO_TREASURER from driver's perspective, treasurer records as income.
  /// ไวยาวัจกรณ์รับเงินฝากของพระจากคนขับรถ (คนขับรถนำเงินที่พระฝากไว้มาส่งให้ไวยาวัจกรณ์)
  DEPOSIT_FROM_DRIVER_FOR_MONK,

  /// ไวยาวัจกรณ์โอนเงินฝากของพระให้คนขับรถดูแลต่อ
  TRANSFER_MONK_FUND_TO_DRIVER,

  /// คนขับรถส่งยอดเงินสุทธิของพระที่ตนดูแลอยู่คืนให้กับไวยาวัจกรณ์
  FORWARD_MONK_FUND_TO_TREASURER,

  /// พระฝากเงินกับไวยาวัจกรณ์โดยตรง
  DEPOSIT_FROM_MONK_TO_TREASURER,

  /// พระเบิกเงินจากไวยาวัจกรณ์โดยตรง
  MONK_WITHDRAWAL_FROM_TREASURER,

  // --- Initial Balance Setups (often done during first data import or setup) ---
  /// ตั้งค่ายอดเงินเริ่มต้นของพระที่ฝากกับไวยาวัจกรณ์
  INITIAL_MONK_FUND_AT_TREASURER,

  /// ตั้งค่ายอดเงินเริ่มต้นของพระที่ฝากกับคนขับรถ (อาจเกิดเมื่อคนขับ import initial file)
  INITIAL_MONK_FUND_AT_DRIVER,

  /// ตั้งค่ายอดเงินสำรองเดินทางเริ่มต้นของคนขับรถ (เมื่อคนขับ import initial file)
  INITIAL_DRIVER_ADVANCE,

  /// ตั้งค่ายอดเงินกองกลางเริ่มต้นของวัด
  INITIAL_TEMPLE_FUND,

  // --- Other/System Transactions ---
  /// การปรับยอด (เช่น แก้ไขข้อผิดพลาด)
  BALANCE_ADJUSTMENT,
}

/// [TransactionStatus] (enum): สถานะของธุรกรรม
/// ใช้เพื่อติดตามความคืบหน้าของธุรกรรม โดยเฉพาะธุรกรรมที่สร้างโดยคนขับรถและต้องรอการยืนยันจากไวยาวัจกรณ์
enum TransactionStatus {
  /// [pendingExport]: ธุรกรรมที่คนขับรถบันทึกแล้ว แต่ยังไม่ได้ส่งออกข้อมูลให้ไวยาวัจกรณ์
  pendingExport,

  /// [exportedToTreasurer]: ธุรกรรมที่คนขับรถส่งออกข้อมูลให้ไวยาวัจกรณ์แล้ว รอการตรวจสอบ
  exportedToTreasurer,

  /// [pendingReconciliationByTreasurer]: ธุรกรรมที่ไวยาวัจกรณ์นำเข้าแล้ว แต่ยังไม่ได้ยืนยัน/ตรวจสอบขั้นสุดท้าย
  pendingReconciliationByTreasurer,

  /// [reconciledByTreasurer]: ธุรกรรมที่ไวยาวัจกรณ์ตรวจสอบและยืนยันแล้ว
  reconciledByTreasurer,

  /// [exportedToDriver]: ธุรกรรม (เช่น การโอนเงินปัจจัยพระ) ที่ไวยาวัจกรณ์ส่งออกข้อมูลให้คนขับรถแล้ว
  exportedToDriver,

  /// [completed]: ธุรกรรมที่เสร็จสมบูรณ์แล้ว (สำหรับธุรกรรมที่ไม่ต้องการการ reconcile เช่น ไวยาวัจกรณ์บันทึกเอง)
  completed,

  /// [cancelled]: ธุรกรรมที่ถูกยกเลิก
  cancelled,
}

/// [Transaction] (class): โมเดลสำหรับจัดเก็บข้อมูลธุรกรรมทางการเงิน
/// เป็นหัวใจสำคัญในการบันทึกการเคลื่อนไหวของเงินในระบบ
class Transaction {
  /// [uuid] (String): Unique Universal Identifier (UUID) ที่ไม่ซ้ำกันสำหรับแต่ละธุรกรรม
  /// ใน SQLite, uuid จะเป็น PRIMARY KEY ของตาราง transactions
  final String uuid;

  /// [type] (TransactionType): ประเภทของธุรกรรม
  /// SQLite จะเก็บค่านี้เป็น String (ชื่อของ enum)
  final TransactionType type;

  /// [amount] (int): จำนวนเงินของธุรกรรม เป็นจำนวนเต็ม (หน่วย: สตางค์ หรือ บาท*100 เพื่อหลีกเลี่ยงปัญหาทศนิยม)
  /// **หมายเหตุ:** แนะนำให้เก็บเป็น integer (เช่น สตางค์) เพื่อความแม่นยำในการคำนวณ
  final int amount;

  /// [timestamp] (DateTime): วันที่และเวลาที่ธุรกรรมเกิดขึ้นจริง หรือวันที่และเวลาที่บันทึกธุรกรรม
  /// SQLite จะเก็บค่านี้เป็น String (ISO8601 format) หรือ int (millisecondsSinceEpoch)
  final DateTime timestamp;

  /// [note] (String): หมายเหตุประกอบธุรกรรม
  final String note;

  /// [recordedByPrimaryId] (String): Primary ID ของผู้ใช้งานที่บันทึกธุรกรรมนี้
  final String recordedByPrimaryId;

  /// [sourceAccountId] (String?): Primary ID ของบัญชีต้นทาง (เช่น ID ของพระ, ID ของคนขับ, ID ของไวยาวัจกรณ์, หรือค่าคงที่พิเศษ)
  final String? sourceAccountId;

  /// [destinationAccountId] (String?): Primary ID ของบัญชีปลายทาง (เช่น ID ของพระ, ID ของคนขับ, ID ของไวยาวัจกรณ์, หรือค่าคงที่พิเศษ)
  final String? destinationAccountId;

  /// [expenseCategory] (String?): ประเภทของค่าใช้จ่าย (เช่น ค่าน้ำมัน, ค่าอาหาร) - ใช้สำหรับธุรกรรมประเภทรายจ่าย
  final String? expenseCategory;

  /// [status] (TransactionStatus?): สถานะของธุรกรรม
  /// SQLite จะเก็บค่านี้เป็น String (ชื่อของ enum) หรือ null
  final TransactionStatus? status;

  /// [processedByPrimaryId] (String?): Primary ID ของผู้ใช้งานที่นำเข้าและประมวลผลธุรกรรมนี้ในระบบของตนเอง
  /// (เช่น ID ของไวยาวัจกรณ์ที่ import ข้อมูลจากคนขับรถ)
  final String? processedByPrimaryId;

  Transaction({
    required this.uuid,
    required this.type,
    required this.amount,
    required this.timestamp,
    required this.note,
    required this.recordedByPrimaryId,
    this.sourceAccountId,
    this.destinationAccountId,
    this.expenseCategory,
    this.status,
    this.processedByPrimaryId,
  });

  /// Factory constructor สำหรับช่วยสร้าง Transaction object ใหม่พร้อม UUID และ timestamp ปัจจุบัน
  factory Transaction.create({
    required TransactionType type,
    required int amount,
    required String note,
    required String recordedByPrimaryId,
    String? sourceAccountId,
    String? destinationAccountId,
    String? expenseCategory,
    TransactionStatus? status,
    DateTime? customTimestamp,
    String? processedByPrimaryId, // For imported transactions
  }) {
    const uuidGenerator = Uuid();
    return Transaction(
      uuid: uuidGenerator.v4(),
      type: type,
      amount: amount,
      timestamp: customTimestamp ?? DateTime.now(),
      note: note,
      recordedByPrimaryId: recordedByPrimaryId,
      sourceAccountId: sourceAccountId,
      destinationAccountId: destinationAccountId,
      expenseCategory: expenseCategory,
      status: status ??
          TransactionStatus.completed, // Default to completed if not specified
      processedByPrimaryId: processedByPrimaryId,
    );
  }

  /// Creates a copy of this Transaction but with the given fields replaced with the new values.
  Transaction copyWith({
    String? uuid,
    TransactionType? type,
    int? amount,
    DateTime? timestamp,
    String? note,
    String? recordedByPrimaryId,
    String? sourceAccountId,
    String? destinationAccountId,
    String? expenseCategory,
    TransactionStatus? status,
    String? processedByPrimaryId,
  }) {
    return Transaction(
      uuid: uuid ?? this.uuid,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      timestamp: timestamp ?? this.timestamp,
      note: note ?? this.note,
      recordedByPrimaryId: recordedByPrimaryId ?? this.recordedByPrimaryId,
      sourceAccountId: sourceAccountId ?? this.sourceAccountId,
      destinationAccountId: destinationAccountId ?? this.destinationAccountId,
      expenseCategory: expenseCategory ?? this.expenseCategory,
      status: status ?? this.status,
      processedByPrimaryId: processedByPrimaryId ?? this.processedByPrimaryId,
    );
  }

  /// Method สำหรับแปลงอ็อบเจกต์ Transaction เป็น Map<String, dynamic>
  /// เพื่อใช้กับ sqflite ในการ insert/update ข้อมูลลงตาราง
  Map<String, dynamic> toMap() {
    return {
      'uuid': uuid,
      'type': type.name, // เก็บชื่อของ enum เป็น String
      'amount': amount,
      'timestamp':
          timestamp.toIso8601String(), // แปลง DateTime เป็น String (ISO8601)
      'note': note,
      'recordedByPrimaryId': recordedByPrimaryId,
      'sourceAccountId': sourceAccountId,
      'destinationAccountId': destinationAccountId,
      'expenseCategory': expenseCategory,
      'status': status
          ?.name, // เก็บชื่อของ enum เป็น String (หรือ null ถ้า status เป็น null)
      'processedByPrimaryId': processedByPrimaryId,
    };
  }

  /// Factory constructor สำหรับสร้างอ็อบเจกต์ Transaction จาก Map<String, dynamic>
  /// ที่อ่านมาจากฐานข้อมูล sqflite
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      uuid: map['uuid'] as String,
      type: TransactionType.values
          .byName(map['type'] as String), // แปลง String กลับเป็น enum
      amount: map['amount'] as int,
      timestamp: DateTime.parse(map['timestamp']
          as String), // แปลง String (ISO8601) กลับเป็น DateTime
      note: map['note'] as String,
      recordedByPrimaryId: map['recordedByPrimaryId'] as String,
      sourceAccountId: map['sourceAccountId'] as String?,
      destinationAccountId: map['destinationAccountId'] as String?,
      expenseCategory: map['expenseCategory'] as String?,
      status: map['status'] != null
          ? TransactionStatus.values.byName(map['status'] as String)
          : null, // แปลง String กลับเป็น enum (ถ้าไม่ null)
      processedByPrimaryId: map['processedByPrimaryId'] as String?,
    );
  }
}
