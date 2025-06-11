class AppConstants {
  // SharedPreferences Keys
  static const String isSetupComplete = 'is_setup_complete';
  static const String userPrimaryId = 'user_primary_id';
  static const String userDisplayName = 'user_display_name';
  static const String userSecondaryId = 'user_secondary_id';
  static const String userRole = 'user_role';
  static const String associatedTreasurerPrimaryId =
      'associated_treasurer_primary_id';
  static const String associatedTreasurerSecondaryId =
      'associated_treasurer_secondary_id';
  static const String driverInitialDataImported =
      'driver_initial_data_imported';

  // File Types (used in FileExportService metadata)
  static const String fileTypeInitialDriverData = 'initial_driver_data';
  static const String fileTypeDriverDataToTreasurer =
      'driver_data_to_treasurer';
  static const String fileTypeTreasurerUpdateForDriver =
      'treasurer_update_for_driver';

  // Special Account IDs (used in Transaction model)
  static const String externalSourceAccountId = "EXTERNAL_SOURCE";
  static const String expenseDestinationAccountId = "EXPENSE_DESTINATION";

  // ID Ranges (as per plan)
  static const int treasurerPrimaryIdMin = 1000;
  static const int treasurerPrimaryIdMax = 9999;
  static const int treasurerSecondaryIdMin = 1000;
  static const int treasurerSecondaryIdMax = 9999;

  static const int driverPrimaryIdMin = 10000;
  static const int driverPrimaryIdMax = 99999;
  static const int driverSecondaryIdMin = 10000;
  static const int driverSecondaryIdMax = 99999;

  static const int monkPrimaryIdTreasurerMin = 100000;
  static const int monkPrimaryIdTreasurerMax = 599999;
  static const int monkPrimaryIdDriverMin = 600000;
  static const int monkPrimaryIdDriverMax = 999999;
  static const int monkSecondaryIdMin = 100000;
  static const int monkSecondaryIdMax = 999999;

  // PIN Lengths
  static const int minPinLength = 4;
  static const int maxPinLength = 6;
}

class TransactionTypeNames {
  static const String depositFromMonkToDriver = 'พระฝากเงิน (กับคนขับ)';
  static const String withdrawalForMonkFromDriver = 'เบิกเงินให้พระ (จากคนขับ)';
  static const String tripExpenseByDriver = 'ค่าใช้จ่ายเดินทาง';
  static const String receiveDriverAdvance = 'รับเงินสำรองเดินทาง';
  static const String returnDriverAdvanceToTreasurer =
      'คืนเงินสำรองเดินทาง (ให้ไวยาวัจกรณ์)';
  static const String receiveMonkFundFromTreasurer =
      'รับเงินปัจจัยพระ (จากไวยาวัจกรณ์)';
  static const String templeIncome = 'รายรับวัด';
  static const String templeExpense = 'รายจ่ายวัด';
  static const String giveDriverAdvance = 'ให้เงินสำรองเดินทาง (แก่คนขับ)';
  static const String depositFromDriverForMonk =
      'รับเงินปัจจัยพระ (จากคนขับ)'; // Driver brings monk's deposit to treasurer
  static const String transferMonkFundToDriver =
      'โอนเงินปัจจัยพระ (ให้คนขับดูแล)';
  static const String depositFromMonkToTreasurer =
      'พระฝากเงิน (กับไวยาวัจกรณ์)';
  static const String monkWithdrawalFromTreasurer =
      'พระเบิกเงิน (จากไวยาวัจกรณ์)';
  static const String initialMonkFundAtTreasurer =
      'ยอดเริ่มต้นปัจจัยพระ (กับไวยาวัจกรณ์)';
  static const String initialMonkFundAtDriver =
      'ยอดเริ่มต้นปัจจัยพระ (กับคนขับ)';
  static const String initialDriverAdvance = 'ยอดเงินสำรองเดินทางเริ่มต้น';
  static const String initialTempleFund = 'ยอดเงินกองกลางวัดเริ่มต้น';
  static const String balanceAdjustment = 'ปรับปรุงยอด';
  static const String forwardMonkFundToTreasurer =
      'คนขับส่งยอดปัจจัยพระคืนไวยาวัจกรณ์';
}

class UserRoleNames {
  static const String treasurer = 'ไวยาวัจกรณ์';
  static const String driver = 'คนขับรถ';
  static const String monk = 'พระ';
}
