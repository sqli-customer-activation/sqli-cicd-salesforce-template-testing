/**
 * Tests for ExpenseService: the approval lifecycle of expense claims
 * and the reimbursement totals reported per Account.
 */
@isTest
private class ExpenseServiceTest {
  private static final Integer BULK_SIZE = 251;
  private static final Decimal REIMBURSABLE_AMOUNT = 100.00;
  private static final Decimal COMPANY_CARD_AMOUNT = 50.00;
  private static final Decimal PENDING_AMOUNT = 25.00;
  private static final Decimal EXPECTED_BILLED_TOTAL = 300.00;
  private static final String REJECTION_REASON = 'Receipt missing';

  @TestSetup
  static void setupTestData() {
    List<Account> accounts = TestDataFactory.createAccounts(2, true);
    Id billedAccountId = accounts[0].Id;

    List<Expense__c> expenses = new List<Expense__c>();
    // Only these three feed the billed Account total: approved and reimbursable.
    expenses.addAll(
      TestDataFactory.createExpenses(
        3,
        billedAccountId,
        ExpenseService.STATUS_APPROVED,
        REIMBURSABLE_AMOUNT,
        true,
        false
      )
    );
    // Approved but paid on a company card, so excluded from the total.
    expenses.add(
      TestDataFactory.buildExpense(
        billedAccountId,
        ExpenseService.STATUS_APPROVED,
        COMPANY_CARD_AMOUNT,
        false
      )
    );
    // Reimbursable but still awaiting approval, so excluded from the total.
    expenses.add(
      TestDataFactory.buildExpense(
        billedAccountId,
        ExpenseService.STATUS_SUBMITTED,
        PENDING_AMOUNT,
        true
      )
    );
    // Internal expenses (no Account) used by the transition tests.
    expenses.addAll(
      TestDataFactory.createExpenses(
        2,
        null,
        ExpenseService.STATUS_SUBMITTED,
        REIMBURSABLE_AMOUNT,
        true,
        false
      )
    );
    expenses.add(
      TestDataFactory.buildExpense(null, 'Draft', REIMBURSABLE_AMOUNT, true)
    );

    insert expenses;
  }

  // ─── Approval ────────────────────────────────────────────────────────

  @isTest
  static void shouldApproveExpenses_WhenAllAreSubmitted() {
    // Given
    Map<Id, Expense__c> submitted = new Map<Id, Expense__c>(
      getInternalExpenses(ExpenseService.STATUS_SUBMITTED)
    );

    // When
    Test.startTest();
    List<Expense__c> approved = ExpenseService.approveExpenses(
      submitted.keySet()
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      2,
      approved.size(),
      'Both submitted expenses should be returned'
    );
    for (Expense__c expense : [
      SELECT Status__c
      FROM Expense__c
      WHERE Id IN :submitted.keySet()
    ]) {
      Assert.areEqual(
        ExpenseService.STATUS_APPROVED,
        expense.Status__c,
        'Expense should be approved in the database'
      );
    }
  }

  @isTest
  static void shouldApproveSingleExpense_WhenUsingOverload() {
    // Given
    Expense__c submitted = getInternalExpenses(
      ExpenseService.STATUS_SUBMITTED
    )[0];

    // When
    Test.startTest();
    Expense__c approved = ExpenseService.approveExpense(submitted.Id);
    Test.stopTest();

    // Then
    Assert.areEqual(
      submitted.Id,
      approved.Id,
      'The overload should return the requested expense'
    );
    Expense__c reloaded = [
      SELECT Status__c
      FROM Expense__c
      WHERE Id = :submitted.Id
    ];
    Assert.areEqual(
      ExpenseService.STATUS_APPROVED,
      reloaded.Status__c,
      'Expense should be approved in the database'
    );
  }

  @isTest
  static void shouldApproveEveryExpense_WhenVolumeExceedsBatchBoundary() {
    // Given
    List<Account> accounts = [SELECT Id FROM Account ORDER BY Name];
    Map<Id, Expense__c> bulkExpenses = new Map<Id, Expense__c>(
      TestDataFactory.createExpenses(
        BULK_SIZE,
        accounts[1].Id,
        ExpenseService.STATUS_SUBMITTED,
        REIMBURSABLE_AMOUNT,
        true,
        true
      )
    );

    // When
    Test.startTest();
    List<Expense__c> approved = ExpenseService.approveExpenses(
      bulkExpenses.keySet()
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      BULK_SIZE,
      approved.size(),
      'Every expense in the batch should be returned'
    );
    Integer approvedCount = [
      SELECT COUNT()
      FROM Expense__c
      WHERE
        Id IN :bulkExpenses.keySet()
        AND Status__c = :ExpenseService.STATUS_APPROVED
    ];
    Assert.areEqual(
      BULK_SIZE,
      approvedCount,
      'Every expense in the batch should be approved in the database'
    );
  }

  // ─── Rejection ───────────────────────────────────────────────────────

  @isTest
  static void shouldRejectExpensesWithReason_WhenAllAreSubmitted() {
    // Given
    Map<Id, Expense__c> submitted = new Map<Id, Expense__c>(
      getInternalExpenses(ExpenseService.STATUS_SUBMITTED)
    );

    // When
    Test.startTest();
    List<Expense__c> rejected = ExpenseService.rejectExpenses(
      submitted.keySet(),
      REJECTION_REASON
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      2,
      rejected.size(),
      'Both submitted expenses should be returned'
    );
    for (Expense__c expense : [
      SELECT Status__c, Comments__c
      FROM Expense__c
      WHERE Id IN :submitted.keySet()
    ]) {
      Assert.areEqual(
        ExpenseService.STATUS_REJECTED,
        expense.Status__c,
        'Expense should be rejected in the database'
      );
      Assert.areEqual(
        REJECTION_REASON,
        expense.Comments__c,
        'The rejection reason should be recorded on the expense'
      );
    }
  }

  @isTest
  static void shouldRejectSingleExpense_WhenUsingOverload() {
    // Given
    Expense__c submitted = getInternalExpenses(
      ExpenseService.STATUS_SUBMITTED
    )[0];

    // When
    Test.startTest();
    Expense__c rejected = ExpenseService.rejectExpense(
      submitted.Id,
      REJECTION_REASON
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      submitted.Id,
      rejected.Id,
      'The overload should return the requested expense'
    );
    Expense__c reloaded = [
      SELECT Status__c, Comments__c
      FROM Expense__c
      WHERE Id = :submitted.Id
    ];
    Assert.areEqual(
      ExpenseService.STATUS_REJECTED,
      reloaded.Status__c,
      'Expense should be rejected in the database'
    );
    Assert.areEqual(
      REJECTION_REASON,
      reloaded.Comments__c,
      'The rejection reason should be recorded on the expense'
    );
  }

  @isTest
  static void shouldThrowException_WhenRejectionReasonIsBlank() {
    // Given
    Map<Id, Expense__c> submitted = new Map<Id, Expense__c>(
      getInternalExpenses(ExpenseService.STATUS_SUBMITTED)
    );

    // When / Then
    Test.startTest();
    try {
      ExpenseService.rejectExpenses(submitted.keySet(), '   ');
      Assert.fail('Expected ExpenseServiceException to be thrown');
    } catch (ExpenseService.ExpenseServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('rejection reason is required'),
        'Exception message should call out the missing reason, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  // ─── Transition guards ───────────────────────────────────────────────

  @isTest
  static void shouldThrowException_WhenExpenseIsNotSubmitted() {
    // Given
    Expense__c draft = getInternalExpenses('Draft')[0];

    // When / Then
    Test.startTest();
    try {
      ExpenseService.approveExpenses(new Set<Id>{ draft.Id });
      Assert.fail('Expected ExpenseServiceException to be thrown');
    } catch (ExpenseService.ExpenseServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('Only Submitted expenses'),
        'Exception message should call out the invalid status, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();

    Expense__c reloaded = [
      SELECT Status__c
      FROM Expense__c
      WHERE Id = :draft.Id
    ];
    Assert.areEqual(
      'Draft',
      reloaded.Status__c,
      'A rejected transition should leave the expense untouched'
    );
  }

  @isTest
  static void shouldThrowException_WhenNoRecordIsFound() {
    // Given
    Expense__c submitted = getInternalExpenses(
      ExpenseService.STATUS_SUBMITTED
    )[0];
    Id deletedId = submitted.Id;
    delete submitted;

    // When / Then
    Test.startTest();
    try {
      ExpenseService.approveExpenses(new Set<Id>{ deletedId });
      Assert.fail('Expected ExpenseServiceException to be thrown');
    } catch (ExpenseService.ExpenseServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('No accessible Expense record'),
        'Exception message should call out the missing record, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  @isTest
  static void shouldThrowException_WhenExpenseIdsAreEmpty() {
    // When / Then
    Test.startTest();
    try {
      ExpenseService.approveExpenses(new Set<Id>());
      Assert.fail('Expected ExpenseServiceException to be thrown');
    } catch (ExpenseService.ExpenseServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('At least one Expense Id'),
        'Exception message should call out the empty input, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  @isTest
  static void shouldThrowException_WhenExpenseIdsAreNull() {
    // When / Then
    Test.startTest();
    try {
      ExpenseService.approveExpenses((Set<Id>) null);
      Assert.fail('Expected ExpenseServiceException to be thrown');
    } catch (ExpenseService.ExpenseServiceException e) {
      Assert.isTrue(
        e.getMessage().contains('At least one Expense Id'),
        'Exception message should call out the null input, got: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }

  // ─── User mode enforcement ───────────────────────────────────────────

  @isTest
  static void shouldApproveExpenses_WhenRunningAsPermissionedUser() {
    // Given
    User expenseUser = TestDataFactory.createExpenseUser();
    Map<Id, Expense__c> submitted = new Map<Id, Expense__c>(
      getInternalExpenses(ExpenseService.STATUS_SUBMITTED)
    );

    // When
    Test.startTest();
    System.runAs(expenseUser) {
      ExpenseService.approveExpenses(submitted.keySet());
    }
    Test.stopTest();

    // Then
    Integer approvedCount = [
      SELECT COUNT()
      FROM Expense__c
      WHERE
        Id IN :submitted.keySet()
        AND Status__c = :ExpenseService.STATUS_APPROVED
    ];
    Assert.areEqual(
      submitted.size(),
      approvedCount,
      'The Expense User permission set should be sufficient to approve expenses'
    );
  }

  @isTest
  static void shouldThrowQueryException_WhenUserCannotReadExpenses() {
    // Given
    User strangerUser = TestDataFactory.createUserWithoutExpenseAccess();
    Map<Id, Expense__c> submitted = new Map<Id, Expense__c>(
      getInternalExpenses(ExpenseService.STATUS_SUBMITTED)
    );

    // When / Then
    Test.startTest();
    System.runAs(strangerUser) {
      try {
        ExpenseService.approveExpenses(submitted.keySet());
        Assert.fail('Expected the USER_MODE query to be refused');
      } catch (QueryException e) {
        // WITH USER_MODE refuses the read for a user without object access.
        Assert.isTrue(
          String.isNotBlank(e.getMessage()),
          'The refusal should explain why the read was blocked'
        );
      }
    }
    Test.stopTest();

    // Then
    Integer untouchedCount = [
      SELECT COUNT()
      FROM Expense__c
      WHERE
        Id IN :submitted.keySet()
        AND Status__c = :ExpenseService.STATUS_SUBMITTED
    ];
    Assert.areEqual(
      submitted.size(),
      untouchedCount,
      'A user without access should not be able to change any expense'
    );
  }

  // ─── Reimbursement totals ────────────────────────────────────────────

  @isTest
  static void shouldSumApprovedReimbursableExpenses_WhenTotalsAreRequested() {
    // Given
    List<Account> accounts = [SELECT Id FROM Account ORDER BY Name];
    Id billedAccountId = accounts[0].Id;

    // When
    Test.startTest();
    Map<Id, Decimal> totalsByAccountId = ExpenseService.getReimbursableTotalsByAccount(
      new Set<Id>{ billedAccountId }
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      EXPECTED_BILLED_TOTAL,
      totalsByAccountId.get(billedAccountId).setScale(2),
      'Only approved reimbursable expenses should be summed'
    );
  }

  @isTest
  static void shouldReturnZeroTotal_WhenAccountHasNoApprovedExpense() {
    // Given
    List<Account> accounts = [SELECT Id FROM Account ORDER BY Name];
    Id unbilledAccountId = accounts[1].Id;

    // When
    Test.startTest();
    Map<Id, Decimal> totalsByAccountId = ExpenseService.getReimbursableTotalsByAccount(
      new Set<Id>{ unbilledAccountId }
    );
    Test.stopTest();

    // Then
    Assert.isTrue(
      totalsByAccountId.containsKey(unbilledAccountId),
      'Every requested Account should be present in the map'
    );
    Assert.areEqual(
      0.00,
      totalsByAccountId.get(unbilledAccountId).setScale(2),
      'An Account without approved expenses should total zero'
    );
  }

  @isTest
  static void shouldReturnEmptyMap_WhenAccountIdsAreEmpty() {
    // When
    Test.startTest();
    Map<Id, Decimal> totalsByAccountId = ExpenseService.getReimbursableTotalsByAccount(
      new Set<Id>()
    );
    Test.stopTest();

    // Then
    Assert.isTrue(
      totalsByAccountId.isEmpty(),
      'An empty request should return an empty map'
    );
  }

  @isTest
  static void shouldReturnEmptyMap_WhenAccountIdsAreNull() {
    // When
    Test.startTest();
    Map<Id, Decimal> totalsByAccountId = ExpenseService.getReimbursableTotalsByAccount(
      null
    );
    Test.stopTest();

    // Then
    Assert.isTrue(
      totalsByAccountId.isEmpty(),
      'A null request should return an empty map'
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  /**
   * Returns the expenses created without an Account, which the transition
   * tests own; the Account-linked expenses belong to the totals tests.
   */
  private static List<Expense__c> getInternalExpenses(String status) {
    return [
      SELECT Id, Name, Status__c, Comments__c
      FROM Expense__c
      WHERE Account__c = NULL AND Status__c = :status
      ORDER BY Name
    ];
  }
}
