// lib/services/database_helper.dart
import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path_provider/path_provider.dart';
import 'package:moneywat/models/user_model.dart';
import 'package:moneywat/models/transaction_model.dart' as model;
import 'package:moneywat/models/account_balance_models.dart';
import 'package:intl/intl.dart'; // Import DateFormat

class DatabaseHelper {
  // Table names
  static const String tableUsers = 'users';
  static const String tableTransactions = 'transactions';
  static const String tableMonkFundsAtTreasurer = 'monk_funds_at_treasurer';
  static const String tableMonkFundsAtDriver = 'monk_funds_at_driver';
  static const String tableDriverAdvanceAccounts = 'driver_advance_accounts';
  static const String tableTempleFundAccounts = 'temple_fund_accounts';

  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static sqflite.Database? _database;

  Future<sqflite.Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<sqflite.Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'money_app.db');
    return await sqflite.openDatabase(
      path,
      version: 1, // Increment version if schema changes
      onCreate: _onCreate,
      // onUpgrade: _onUpgrade, // Optional: for database schema migrations
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      }, // Enable foreign key constraints
    );
  }

  Future<void> _onCreate(sqflite.Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableUsers (
        primaryId TEXT PRIMARY KEY,
        secondaryId TEXT NOT NULL UNIQUE, 
        displayName TEXT NOT NULL,
        role TEXT NOT NULL, 
        hashedPin TEXT 
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTransactions (
        uuid TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        note TEXT NOT NULL,
        recordedByPrimaryId TEXT NOT NULL,
        sourceAccountId TEXT,
        destinationAccountId TEXT,
        expenseCategory TEXT,
        status TEXT,
        processedByPrimaryId TEXT,
        FOREIGN KEY (recordedByPrimaryId) REFERENCES $tableUsers (primaryId)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMonkFundsAtTreasurer (
        accountId TEXT NOT NULL, 
        treasurerPrimaryId TEXT NOT NULL,
        balance INTEGER NOT NULL,
        lastUpdated TEXT NOT NULL,
        PRIMARY KEY (accountId, treasurerPrimaryId),
        FOREIGN KEY (accountId) REFERENCES $tableUsers (primaryId),
        FOREIGN KEY (treasurerPrimaryId) REFERENCES $tableUsers (primaryId)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMonkFundsAtDriver (
        accountId TEXT NOT NULL, 
        driverPrimaryId TEXT NOT NULL,
        balance INTEGER NOT NULL,
        lastUpdated TEXT NOT NULL,
        PRIMARY KEY (accountId, driverPrimaryId),
        FOREIGN KEY (accountId) REFERENCES $tableUsers (primaryId),
        FOREIGN KEY (driverPrimaryId) REFERENCES $tableUsers (primaryId)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableDriverAdvanceAccounts (
        accountId TEXT PRIMARY KEY, 
        balance INTEGER NOT NULL,
        lastUpdated TEXT NOT NULL,
        FOREIGN KEY (accountId) REFERENCES $tableUsers (primaryId)
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTempleFundAccounts (
        accountId TEXT PRIMARY KEY, 
        balance INTEGER NOT NULL,
        lastUpdated TEXT NOT NULL,
        FOREIGN KEY (accountId) REFERENCES $tableUsers (primaryId)
      )
    ''');
  }

  // --- User Table Methods ---
  Future<int> insertUser(User user, {sqflite.Transaction? txn}) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableUsers,
      user.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<User?> getUser(String primaryId, {sqflite.Transaction? txn}) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableUsers,
      where: 'primaryId = ?',
      whereArgs: [primaryId],
    );
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateUser(User user, {sqflite.Transaction? txn}) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.update(
      tableUsers,
      user.toMap(),
      where: 'primaryId = ?',
      whereArgs: [user.primaryId],
    );
  }

  Future<int> deleteUser(String primaryId, {sqflite.Transaction? txn}) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.delete(
      tableUsers,
      where: 'primaryId = ?',
      whereArgs: [primaryId],
    );
  }

  Future<List<User>> getAllUsers({sqflite.Transaction? txn}) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableUsers,
      orderBy: 'role ASC, displayName ASC',
    );
    return List.generate(maps.length, (i) {
      return User.fromMap(maps[i]);
    });
  }

  Future<List<User>> getUsersByRole(
    UserRole role, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableUsers,
      where: 'role = ?',
      whereArgs: [role.name],
      orderBy: 'displayName ASC',
    );
    return List.generate(maps.length, (i) {
      return User.fromMap(maps[i]);
    });
  }

  Future<List<User>> getActiveMonks({sqflite.Transaction? txn}) async {
    // Now that status is removed, this just gets all monks.
    return await getUsersByRole(UserRole.monk, txn: txn);
  }

  Future<bool> isSecondaryIdTaken(
    String secondaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableUsers,
      columns: ['primaryId'],
      where: 'secondaryId = ?',
      whereArgs: [secondaryId],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<List<User>> getUsersByDisplayNameAndRole(
    String displayName,
    UserRole role, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableUsers,
      where: 'displayName = ? AND role = ?',
      whereArgs: [displayName, role.name],
    );
    return List.generate(maps.length, (i) {
      return User.fromMap(maps[i]);
    });
  }

  // New method to get users with their last activity timestamp
  Future<List<Map<String, dynamic>>> getUsersByRoleWithLastActivity(
    UserRole role, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    // This query joins the users table with a subquery that finds the maximum (latest)
    // timestamp from the transactions table for each user involved in any transaction.
    // Users with no transactions will have a NULL last_activity_timestamp.
    final List<Map<String, dynamic>> userMaps = await dbClient.rawQuery(
      '''
      SELECT 
        u.*, 
        (
          SELECT MAX(t.timestamp) 
          FROM $tableTransactions t 
          WHERE t.recordedByPrimaryId = u.primaryId 
             OR t.sourceAccountId = u.primaryId 
             OR t.destinationAccountId = u.primaryId
             OR t.processedByPrimaryId = u.primaryId
        ) as last_activity_timestamp
      FROM $tableUsers u
      WHERE u.role = ?
    ''',
      [role.name],
    );
    return userMaps;
  }

  // --- Transaction Table Methods ---
  Future<int> insertTransaction(
    model.Transaction transaction, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableTransactions,
      transaction.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.fail,
    );
  }

  Future<model.Transaction?> getTransaction(
    String uuid, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
    if (maps.isNotEmpty) {
      return model.Transaction.fromMap(maps.first);
    }
    return null;
  }

  Future<List<model.Transaction>> getAllTransactions({
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) {
      return model.Transaction.fromMap(maps[i]);
    });
  }

  Future<List<model.Transaction>> getTransactionsByRecordedUser(
    String recordedByPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: 'recordedByPrimaryId = ?',
      whereArgs: [recordedByPrimaryId],
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) {
      return model.Transaction.fromMap(maps[i]);
    });
  }

  Future<int> updateTransactionStatus(
    String uuid,
    model.TransactionStatus status, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.update(
      tableTransactions,
      {'status': status.name},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<List<model.Transaction>> getTransactionsForMonkAndDriver(
    String monkPrimaryId,
    String driverPrimaryId, {
    model.TransactionStatus? status,
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    String whereClause =
        '(sourceAccountId = ? AND destinationAccountId = ?) OR (sourceAccountId = ? AND destinationAccountId = ?)';
    List<dynamic> whereArgs = [
      monkPrimaryId,
      driverPrimaryId,
      driverPrimaryId,
      monkPrimaryId,
    ];

    if (status != null) {
      whereClause += ' AND status = ?';
      whereArgs.add(status.name);
    }

    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) {
      return model.Transaction.fromMap(maps[i]);
    });
  }

  Future<List<model.Transaction>> getTransactionsByTypeAndStatus(
    String recordedByPrimaryId,
    model.TransactionType type,
    model.TransactionStatus status, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: 'recordedByPrimaryId = ? AND type = ? AND status = ?',
      whereArgs: [recordedByPrimaryId, type.name, status.name],
      orderBy: 'timestamp DESC',
    );
    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) {
        return model.Transaction.fromMap(maps[i]);
      });
    }
    return [];
  }

  Future<List<model.Transaction>> getMonkHistoryForDriverView(
    String monkPrimaryId,
    String driverPrimaryId, {
    model.TransactionStatus? status,
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;

    String directTxClause =
        '(sourceAccountId = ? AND destinationAccountId = ?) OR (sourceAccountId = ? AND destinationAccountId = ?)';
    List<dynamic> directTxArgs = [
      monkPrimaryId,
      driverPrimaryId,
      driverPrimaryId,
      monkPrimaryId,
    ];

    String initialFundClause =
        '(type = ? AND destinationAccountId = ? AND recordedByPrimaryId = ?)';
    List<dynamic> initialFundArgs = [
      model.TransactionType.INITIAL_MONK_FUND_AT_DRIVER.name,
      monkPrimaryId,
      driverPrimaryId,
    ];

    String finalWhereClause = '($directTxClause) OR ($initialFundClause)';
    List<dynamic> finalWhereArgs = [...directTxArgs, ...initialFundArgs];

    if (status != null) {
      finalWhereClause = '($finalWhereClause) AND status = ?';
      finalWhereArgs.add(status.name);
    }

    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: finalWhereClause,
      whereArgs: finalWhereArgs,
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) {
      return model.Transaction.fromMap(maps[i]);
    });
  }

  Future<List<model.Transaction>> getTransactionsByStatusAndProcessor(
    model.TransactionStatus status,
    String processedByPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: 'status = ? AND processedByPrimaryId = ?',
      whereArgs: [status.name, processedByPrimaryId],
      orderBy: 'timestamp ASC',
    );
    if (maps.isNotEmpty) {
      return List.generate(maps.length, (i) {
        return model.Transaction.fromMap(maps[i]);
      });
    }
    return [];
  }

  Future<List<model.Transaction>> getTempleFundTransactionsForMonth(
    String treasurerPrimaryId,
    DateTime monthYear, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final String monthYearString = DateFormat('yyyy-MM').format(monthYear);

    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where:
          "strftime('%Y-%m', timestamp) = ? AND ((type = ? AND destinationAccountId = ?) OR (type = ? AND sourceAccountId = ?) OR (type = ? AND sourceAccountId = ?))",
      whereArgs: [
        monthYearString,
        model.TransactionType.TEMPLE_INCOME.name,
        treasurerPrimaryId,
        model.TransactionType.TEMPLE_EXPENSE.name,
        treasurerPrimaryId,
        model.TransactionType.GIVE_DRIVER_ADVANCE.name,
        treasurerPrimaryId,
      ],
      orderBy: 'timestamp DESC',
    );
    return List.generate(
      maps.length,
      (i) => model.Transaction.fromMap(maps[i]),
    );
  }

  Future<List<model.Transaction>> getMonkFinancialHistory(
    String monkPrimaryId,
    String treasurerPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: '''
        (
          ( (type = ? AND sourceAccountId = ?) OR (type = ? AND destinationAccountId = ?) OR (type = ? AND sourceAccountId = ?) )
          AND recordedByPrimaryId = ?
        ) OR (
          ( (type = ? AND sourceAccountId = ?) OR (type = ? AND destinationAccountId = ?) )
          AND processedByPrimaryId = ? AND status = ?
        )
      ''',
      whereArgs: [
        model.TransactionType.DEPOSIT_FROM_MONK_TO_TREASURER.name,
        monkPrimaryId,
        model.TransactionType.MONK_WITHDRAWAL_FROM_TREASURER.name,
        monkPrimaryId,
        model.TransactionType.TRANSFER_MONK_FUND_TO_DRIVER.name,
        monkPrimaryId,
        treasurerPrimaryId,
        model.TransactionType.DEPOSIT_FROM_MONK_TO_DRIVER.name,
        monkPrimaryId,
        model.TransactionType.WITHDRAWAL_FOR_MONK_FROM_DRIVER.name,
        monkPrimaryId,
        treasurerPrimaryId,
        model.TransactionStatus.reconciledByTreasurer.name,
      ],
      orderBy: 'timestamp DESC',
    );
    return List.generate(
      maps.length,
      (i) => model.Transaction.fromMap(maps[i]),
    );
  }

  Future<List<model.Transaction>> getDriverFinancialHistory(
    String driverPrimaryId,
    String treasurerPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTransactions,
      where: '''
        (
          (type = ? AND destinationAccountId = ? AND recordedByPrimaryId = ?) OR 
          (type = ? AND sourceAccountId = ? AND processedByPrimaryId = ? AND status = ?) OR
          (type = ? AND sourceAccountId = ? AND destinationAccountId = ? AND processedByPrimaryId = ? AND status = ?)
        )
      ''',
      whereArgs: [
        model.TransactionType.GIVE_DRIVER_ADVANCE.name,
        driverPrimaryId,
        treasurerPrimaryId,
        model.TransactionType.TRIP_EXPENSE_BY_DRIVER.name,
        driverPrimaryId,
        treasurerPrimaryId,
        model.TransactionStatus.reconciledByTreasurer.name,
        model
            .TransactionType
            .TEMPLE_INCOME
            .name, // This covers RETURN_DRIVER_ADVANCE_TO_TREASURER when reconciled
        driverPrimaryId, // source is driver
        treasurerPrimaryId, // destination is treasurer
        treasurerPrimaryId, // processed by treasurer
        model.TransactionStatus.reconciledByTreasurer.name,
      ],
      orderBy: 'timestamp DESC',
    );
    return List.generate(maps.length, (i) {
      return model.Transaction.fromMap(maps[i]);
    });
  }

  // --- MonkFundAtTreasurer Methods ---
  Future<int> insertOrUpdateMonkFundAtTreasurer(
    MonkFundAtTreasurer fund, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableMonkFundsAtTreasurer,
      fund.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<MonkFundAtTreasurer?> getMonkFundAtTreasurer(
    String monkPrimaryId,
    String treasurerPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableMonkFundsAtTreasurer,
      where: 'accountId = ? AND treasurerPrimaryId = ?',
      whereArgs: [monkPrimaryId, treasurerPrimaryId],
    );
    if (maps.isNotEmpty) {
      return MonkFundAtTreasurer.fromMap(maps.first);
    }
    return null;
  }

  // --- MonkFundAtDriver Methods ---
  Future<int> insertOrUpdateMonkFundAtDriver(
    MonkFundAtDriver fund, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableMonkFundsAtDriver,
      fund.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<MonkFundAtDriver?> getMonkFundAtDriver(
    String monkPrimaryId,
    String driverPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableMonkFundsAtDriver,
      where: 'accountId = ? AND driverPrimaryId = ?',
      whereArgs: [monkPrimaryId, driverPrimaryId],
    );
    if (maps.isNotEmpty) {
      return MonkFundAtDriver.fromMap(maps.first);
    }
    return null;
  }

  Future<List<MonkFundAtDriver>> getMonkFundsByDriver(
    String driverPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableMonkFundsAtDriver,
      where: 'driverPrimaryId = ?',
      whereArgs: [driverPrimaryId],
    );
    return List.generate(maps.length, (i) {
      return MonkFundAtDriver.fromMap(maps[i]);
    });
  }

  // --- DriverAdvanceAccount Methods ---
  Future<int> insertOrUpdateDriverAdvance(
    DriverAdvanceAccount advance, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableDriverAdvanceAccounts,
      advance.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<DriverAdvanceAccount?> getDriverAdvance(
    String driverPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableDriverAdvanceAccounts,
      where: 'accountId = ?',
      whereArgs: [driverPrimaryId],
    );
    if (maps.isNotEmpty) {
      return DriverAdvanceAccount.fromMap(maps.first);
    }
    return null;
  }

  // --- TempleFundAccount Methods ---
  Future<int> insertOrUpdateTempleFund(
    TempleFundAccount fund, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.insert(
      tableTempleFundAccounts,
      fund.toMap(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  Future<TempleFundAccount?> getTempleFund(
    String treasurerPrimaryId, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    final List<Map<String, dynamic>> maps = await dbClient.query(
      tableTempleFundAccounts,
      where: 'accountId = ?',
      whereArgs: [treasurerPrimaryId],
    );
    if (maps.isNotEmpty) {
      return TempleFundAccount.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateTransactionFields(
    model.Transaction transaction, {
    sqflite.Transaction? txn,
  }) async {
    final sqflite.DatabaseExecutor dbClient = txn ?? await database;
    return await dbClient.update(
      tableTransactions,
      transaction
          .toMap(), // This will update all fields based on the new transaction object
      where: 'uuid = ?',
      whereArgs: [transaction.uuid],
    );
  }

  Future<void> updateTempleFundBalance(
    String treasurerPrimaryId,
    int amountChange, {
    sqflite.Transaction? txn,
  }) async {
    // final sqflite.DatabaseExecutor dbClient = txn ?? await database; // Not needed here as getTempleFund and insertOrUpdateTempleFund handle txn
    TempleFundAccount? fund = await getTempleFund(treasurerPrimaryId, txn: txn);

    if (fund != null) {
      fund.balance += amountChange;
      fund.lastUpdated = DateTime.now();
      await insertOrUpdateTempleFund(fund, txn: txn);
    } else {
      final newFund = TempleFundAccount(
        treasurerPrimaryId: treasurerPrimaryId,
        balance: amountChange,
        lastUpdated: DateTime.now(),
      );
      await insertOrUpdateTempleFund(newFund, txn: txn);
    }
  }
}
