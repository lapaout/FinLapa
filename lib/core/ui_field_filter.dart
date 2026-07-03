/// Чи слід приховати поле від користувача в UI-списках і картках записів.
bool isHiddenUiField(String headerName) {
  final lower = headerName.toLowerCase();
  return headerName.startsWith('_') ||
      lower.contains('(приховано)') ||
      lower.contains('(hidden)') ||
      lower.contains('дата і час') ||
      lower.contains('час') ||
      lower.contains('date') ||
      lower.contains('time');
}
