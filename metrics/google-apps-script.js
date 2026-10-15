// Dock Finder usage data → Google Sheet.
//
// The app POSTs {"events": [...]} here (ios/biker-app/Services/Metrics.swift)
// and this appends one row per event to the "Events" tab. Setup is in
// metrics/README.md: paste this into the sheet's Extensions → Apps Script,
// then Deploy → New deployment → Web app → Who has access: Anyone.

const COLUMNS = [
  'received', 'date', 'event', 'install_id', 'app_version',
  'latitude', 'longitude', 'station', 'avoided_station',
  'minutes_saved', 'dollars_saved', 'details', 'event_id',
];

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000); // one batch at a time, so rows never interleave
  try {
    const book = SpreadsheetApp.getActiveSpreadsheet();
    const sheet = book.getSheetByName('Events') || book.insertSheet('Events');
    if (sheet.getLastRow() === 0) {
      sheet.appendRow(COLUMNS);
      sheet.setFrozenRows(1);
    }

    const events = (JSON.parse(e.postData.contents).events || []);
    const received = new Date();
    const rows = events.map((ev) => [
      received,
      ev.date ? new Date(ev.date) : '',
      ev.name || '',
      ev.installID || '',
      ev.appVersion || '',
      ev.latitude ?? '',
      ev.longitude ?? '',
      ev.station ?? '',
      ev.avoidedStation ?? '',
      ev.minutesSaved ?? '',
      ev.dollarsSaved ?? '',
      JSON.stringify(ev.details || {}),
      ev.id || '',
    ]);
    if (rows.length) {
      sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, COLUMNS.length).setValues(rows);
    }
    return json({ ok: true, added: rows.length });
  } catch (error) {
    return json({ ok: false, error: String(error) });
  } finally {
    lock.releaseLock();
  }
}

function json(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
