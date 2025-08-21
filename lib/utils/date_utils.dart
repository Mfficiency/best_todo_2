int dateDiffInDays(DateTime from, DateTime to) {
  final fromDate = DateTime(from.year, from.month, from.day);
  final toDate = DateTime(to.year, to.month, to.day);
  return fromDate.difference(toDate).inDays;
}
