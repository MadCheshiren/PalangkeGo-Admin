import '../../models/app_models.dart';

bool isSameCalendarDay(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
      date1.month == date2.month &&
      date1.day == date2.day;
}

bool isApplicationNew(
  VendorApplication application,
  Set<String> viewedIds,
  DateTime referenceDate,
) {
  return isSameCalendarDay(application.submittedAt, referenceDate) &&
      !viewedIds.contains(application.id);
}
