/**
 * Central builder for records used by Apex tests, so a test never builds
 * record lists inline. Record builders can return unsaved instances for
 * in-memory assertions; the user builders always insert, because a User has
 * to exist before it can be handed to System.runAs.
 */
@isTest
public class TestDataFactory {
  private static final String DEFAULT_CATEGORY = 'Travel';
  private static final String STANDARD_PROFILE = 'Standard User';
  private static final String EXPENSE_PERMISSION_SET = 'Expense_User';

  /**
   * @param count Number of Accounts to build
   * @param doInsert Whether the records should be inserted
   * @return The built Accounts, with Ids populated when inserted
   */
  public static List<Account> createAccounts(Integer count, Boolean doInsert) {
    List<Account> accounts = new List<Account>();
    for (Integer i = 0; i < count; i++) {
      accounts.add(
        new Account(Name = 'Test Account ' + String.valueOf(i).leftPad(3, '0'))
      );
    }

    if (doInsert) {
      insert accounts;
    }
    return accounts;
  }

  /**
   * @param accountId Account the expense is rebilled to; may be null for internal expenses
   * @param status Value for the Status picklist
   * @param amount Claimed amount, which must be strictly positive
   * @param reimbursable Whether the employee is paid back
   * @return An unsaved Expense__c record
   */
  public static Expense__c buildExpense(
    Id accountId,
    String status,
    Decimal amount,
    Boolean reimbursable
  ) {
    return new Expense__c(
      Account__c = accountId,
      Status__c = status,
      Amount__c = amount,
      Reimbursable__c = reimbursable,
      Category__c = DEFAULT_CATEGORY,
      Expense_Date__c = Date.today()
    );
  }

  /**
   * @param count Number of Expenses to build
   * @param accountId Account the expenses are rebilled to
   * @param status Value for the Status picklist
   * @param amount Claimed amount per expense
   * @param reimbursable Whether the employee is paid back
   * @param doInsert Whether the records should be inserted
   * @return The built Expenses, with Ids populated when inserted
   */
  public static List<Expense__c> createExpenses(
    Integer count,
    Id accountId,
    String status,
    Decimal amount,
    Boolean reimbursable,
    Boolean doInsert
  ) {
    List<Expense__c> expenses = new List<Expense__c>();
    for (Integer i = 0; i < count; i++) {
      expenses.add(buildExpense(accountId, status, amount, reimbursable));
    }

    if (doInsert) {
      insert expenses;
    }
    return expenses;
  }

  /**
   * Creates a standard user granted the Expense User permission set, so tests
   * can exercise the USER_MODE code paths under a realistic set of permissions.
   * @return The inserted User
   */
  public static User createExpenseUser() {
    User expenseUser = buildStandardUser();

    // Inserting a setup object (User) alongside Expense__c records in one
    // transaction raises MIXED_DML_OPERATION unless it happens inside runAs.
    System.runAs(currentUser()) {
      insert expenseUser;
      insert new PermissionSetAssignment(
        AssigneeId = expenseUser.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = :EXPENSE_PERMISSION_SET
          LIMIT 1
        ]
        .Id
      );
    }

    return expenseUser;
  }

  /**
   * Creates a standard user with no access whatsoever to Expense__c, used to
   * prove that the service refuses to read records the user cannot see.
   * @return The inserted User
   */
  public static User createUserWithoutExpenseAccess() {
    User strangerUser = buildStandardUser();

    System.runAs(currentUser()) {
      insert strangerUser;
    }

    return strangerUser;
  }

  private static User buildStandardUser() {
    String uniqueSuffix =
      String.valueOf(DateTime.now().getTime()) +
      String.valueOf(Math.abs(Crypto.getRandomInteger()));

    return new User(
      ProfileId = [
        SELECT Id
        FROM Profile
        WHERE Name = :STANDARD_PROFILE
        LIMIT 1
      ]
      .Id,
      LastName = 'Expense Tester',
      Alias = 'exptest',
      Email = 'expense.tester@sqli.cicd.test',
      Username = 'expense.tester.' + uniqueSuffix + '@sqli.cicd.test',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      TimeZoneSidKey = 'GMT'
    );
  }

  private static User currentUser() {
    return new User(Id = UserInfo.getUserId());
  }
}
