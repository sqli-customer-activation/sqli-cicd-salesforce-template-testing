/**
 * Service class for Expense__c business logic.
 * Owns the approval lifecycle of expense claims and the reimbursement
 * totals reported against a client Account.
 */
public with sharing class ExpenseService {
  // ─── Constants ───────────────────────────────────────────────────────
  @TestVisible
  private static final String STATUS_SUBMITTED = 'Submitted';
  @TestVisible
  private static final String STATUS_APPROVED = 'Approved';
  @TestVisible
  private static final String STATUS_REJECTED = 'Rejected';

  private static final String ERROR_NO_IDS = 'At least one Expense Id must be provided.';
  private static final String ERROR_NO_RECORDS = 'No accessible Expense record was found for the provided Ids.';
  private static final String ERROR_BLANK_REASON = 'A rejection reason is required.';
  private static final String ERROR_NOT_SUBMITTED = 'Only Submitted expenses can be approved or rejected. Offending records: ';
  private static final String ERROR_DML = 'Failed to update Expense records: ';

  // ─── Public API ──────────────────────────────────────────────────────

  /**
   * Approves every submitted expense in the provided set.
   * @param expenseIds Set of Expense__c Ids to approve
   * @return The approved Expense__c records
   * @throws ExpenseServiceException if the set is empty, a record is not Submitted, or the update fails
   * @example
   * List<Expense__c> approved = ExpenseService.approveExpenses(new Set<Id>{ expenseId });
   */
  public static List<Expense__c> approveExpenses(Set<Id> expenseIds) {
    List<Expense__c> expenses = loadSubmittedExpenses(expenseIds);

    for (Expense__c expense : expenses) {
      expense.Status__c = STATUS_APPROVED;
    }

    persist(expenses);
    return expenses;
  }

  /**
   * Rejects every submitted expense in the provided set and records why.
   * @param expenseIds Set of Expense__c Ids to reject
   * @param reason Business justification stored on the Comments field
   * @return The rejected Expense__c records
   * @throws ExpenseServiceException if the set is empty, the reason is blank, a record is not Submitted, or the update fails
   * @example
   * List<Expense__c> rejected = ExpenseService.rejectExpenses(ids, 'Receipt missing');
   */
  public static List<Expense__c> rejectExpenses(
    Set<Id> expenseIds,
    String reason
  ) {
    if (String.isBlank(reason)) {
      throw new ExpenseServiceException(ERROR_BLANK_REASON);
    }

    List<Expense__c> expenses = loadSubmittedExpenses(expenseIds);

    for (Expense__c expense : expenses) {
      expense.Status__c = STATUS_REJECTED;
      expense.Comments__c = reason;
    }

    persist(expenses);
    return expenses;
  }

  /**
   * Sums the approved, reimbursable expenses booked against each Account.
   * Accounts with no matching expense are returned with a zero total, so the
   * caller never has to null-check the map.
   * @param accountIds Set of Account Ids to report on
   * @return Total reimbursable amount keyed by Account Id
   * @example
   * Map<Id, Decimal> totals = ExpenseService.getReimbursableTotalsByAccount(accountIds);
   */
  public static Map<Id, Decimal> getReimbursableTotalsByAccount(
    Set<Id> accountIds
  ) {
    Map<Id, Decimal> totalsByAccountId = new Map<Id, Decimal>();
    if (accountIds == null || accountIds.isEmpty()) {
      return totalsByAccountId;
    }

    for (Id accountId : accountIds) {
      totalsByAccountId.put(accountId, 0);
    }

    List<AggregateResult> results = [
      SELECT Account__c accountId, SUM(Amount__c) totalAmount
      FROM Expense__c
      WHERE
        Account__c IN :accountIds
        AND Status__c = :STATUS_APPROVED
        AND Reimbursable__c = TRUE
      WITH USER_MODE
      GROUP BY Account__c
    ];

    for (AggregateResult result : results) {
      totalsByAccountId.put(
        (Id) result.get('accountId'),
        (Decimal) result.get('totalAmount')
      );
    }

    return totalsByAccountId;
  }

  // ─── Convenience Overloads ───────────────────────────────────────────

  /**
   * Single-record convenience overload of approveExpenses.
   * @param expenseId The Expense__c Id to approve
   * @return The approved Expense__c record
   */
  public static Expense__c approveExpense(Id expenseId) {
    return approveExpenses(new Set<Id>{ expenseId })[0];
  }

  /**
   * Single-record convenience overload of rejectExpenses.
   * @param expenseId The Expense__c Id to reject
   * @param reason Business justification stored on the Comments field
   * @return The rejected Expense__c record
   */
  public static Expense__c rejectExpense(Id expenseId, String reason) {
    return rejectExpenses(new Set<Id>{ expenseId }, reason)[0];
  }

  // ─── Private Helpers ─────────────────────────────────────────────────

  /**
   * Queries the expenses and refuses the batch unless every record is still Submitted,
   * so a partially applied transition can never be persisted.
   */
  private static List<Expense__c> loadSubmittedExpenses(Set<Id> expenseIds) {
    if (expenseIds == null || expenseIds.isEmpty()) {
      throw new ExpenseServiceException(ERROR_NO_IDS);
    }

    List<Expense__c> expenses = [
      SELECT Id, Name, Status__c, Comments__c
      FROM Expense__c
      WHERE Id IN :expenseIds
      WITH USER_MODE
    ];

    if (expenses.isEmpty()) {
      throw new ExpenseServiceException(ERROR_NO_RECORDS);
    }

    assertAllSubmitted(expenses);
    return expenses;
  }

  private static void assertAllSubmitted(List<Expense__c> expenses) {
    List<String> invalidNames = new List<String>();
    for (Expense__c expense : expenses) {
      if (expense.Status__c != STATUS_SUBMITTED) {
        invalidNames.add(expense.Name);
      }
    }

    if (!invalidNames.isEmpty()) {
      throw new ExpenseServiceException(
        ERROR_NOT_SUBMITTED + String.join(invalidNames, ', ')
      );
    }
  }

  private static void persist(List<Expense__c> expenses) {
    try {
      Database.update(expenses, true, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      throw new ExpenseServiceException(ERROR_DML + e.getMessage(), e);
    }
  }

  // ─── Exception ───────────────────────────────────────────────────────

  /**
   * Custom exception for ExpenseService errors.
   */
  public class ExpenseServiceException extends Exception {
  }
}
