// Dock Finder usage data → Google Sheet.
//
// The app POSTs {"events": [...]} here (ios/biker-app/Services/Metrics.swift).
// Each event becomes a row in the "Events" tab, and the "Users" tab keeps
// one row per install (name, first and last seen, how often they come back)
// up to date. Setup is in metrics/README.md: paste this into the sheet's
// Extensions → Apps Script, then Deploy → New deployment → Web app → Who
// has access: Anyone. After changing it: Deploy → Manage deployments →
// Edit → Version: New version, so the URL stays the same.

const COLUMNS = [
  'received', 'date', 'event', 'install_id', 'app_version',
  'latitude', 'longitude', 'station', 'avoided_station',
  'minutes_saved', 'dollars_saved', 'details', 'event_id',
  'user_name',
];

// The Users tab. Rewritten after every batch, newest activity first.
const USER_COLUMNS = [
  'name', 'install_id', 'last_opened', 'last_active', 'first_seen',
  'days_active', 'app_opens', 'rides_started', 'siri_requests',
  'directions_started', 'full_docks_avoided', 'minutes_saved', 'app_version',
];

// Which events count toward which Users column. `app_launch` is what builds
// before the Users tab sent; it also fired for background relaunches.
const OPEN_EVENTS = ['app_opened', 'app_launch'];
const COUNTED = {
  rides_started: ['ride_started'],
  siri_requests: ['siri_answer'],
  directions_started: ['directions_started'],
  full_docks_avoided: ['full_dock_avoided'],
};

// The app only drops a batch from its queue when the reply says ok: true,
// and resends it otherwise. So ok is about the Events rows alone: once
// they're saved, a failure in the Users tab must not make the app resend
// them as duplicates (run rebuildUsers to fix the tab instead).
function doPost(e) {
  const lock = LockService.getScriptLock();
  // One batch at a time, so rows never interleave. Gives up well before
  // the app's 20-second timeout, so the app hears the answer.
  if (!lock.tryLock(10000)) return json({ ok: false, error: 'busy' });
  try {
    const book = SpreadsheetApp.getActiveSpreadsheet();
    const events = (JSON.parse(e.postData.contents).events || []);
    appendEvents(book, events, new Date());
    try {
      if (book.getSheetByName('Users')) {
        updateUsers(book, events, readUsers(book));
      } else {
        rebuildUsers(); // first batch since adding the Users tab: include past events
      }
    } catch (error) {
      return json({ ok: true, added: events.length, usersError: String(error) });
    }
    return json({ ok: true, added: events.length });
  } catch (error) {
    return json({ ok: false, error: String(error) });
  } finally {
    lock.releaseLock();
  }
}

/// Builds the Users tab from every row in Events. Runs by itself on the
/// first batch after the tab is added; run it from the editor (select it,
/// then ▶ Run) to rebuild after deleting rows or if the numbers look off.
function rebuildUsers() {
  const book = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = book.getSheetByName('Events');
  if (!sheet || sheet.getLastRow() < 2) return;
  const header = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  const col = (name) => header.indexOf(name);
  const events = sheet.getRange(2, 1, sheet.getLastRow() - 1, header.length).getValues()
    .map((row) => ({
      date: row[col('date')] || row[col('received')],
      name: row[col('event')],
      installID: row[col('install_id')],
      appVersion: row[col('app_version')],
      minutesSaved: row[col('minutes_saved')] === '' ? null : row[col('minutes_saved')],
      userName: col('user_name') >= 0 ? row[col('user_name')] : '',
    }))
    .sort((a, b) => new Date(a.date) - new Date(b.date));
  updateUsers(book, events, new Map());
}

function appendEvents(book, events, received) {
  const sheet = book.getSheetByName('Events') || book.insertSheet('Events');
  // Also adds headers for columns added since the sheet was made.
  if (sheet.getLastColumn() < COLUMNS.length) {
    sheet.getRange(1, 1, 1, COLUMNS.length).setValues([COLUMNS]);
    sheet.setFrozenRows(1);
  }
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
    ev.userName || '',
  ]);
  if (rows.length) {
    sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, COLUMNS.length).setValues(rows);
  }
}

function readUsers(book) {
  const users = new Map();
  const sheet = book.getSheetByName('Users');
  if (!sheet || sheet.getLastRow() < 2) return users;
  sheet.getRange(2, 1, sheet.getLastRow() - 1, USER_COLUMNS.length).getValues().forEach((row) => {
    const user = {};
    USER_COLUMNS.forEach((name, i) => { user[name] = row[i]; });
    if (user.install_id) users.set(String(user.install_id), user);
  });
  return users;
}

function updateUsers(book, events, users) {
  const zone = book.getSpreadsheetTimeZone();
  const day = (date) => Utilities.formatDate(date, zone, 'yyyy-MM-dd');

  events.forEach((ev) => {
    const id = String(ev.installID || '');
    if (!id) return;
    const date = ev.date ? new Date(ev.date) : new Date();
    let user = users.get(id);
    if (!user) {
      user = { install_id: id, name: '', first_seen: date, last_active: '', last_opened: '', days_active: 0, app_version: '' };
      Object.keys(COUNTED).forEach((column) => { user[column] = 0; });
      user.app_opens = 0;
      user.minutes_saved = 0;
      users.set(id, user);
    }
    if (ev.userName) user.name = ev.userName;
    if (ev.appVersion) user.app_version = ev.appVersion;
    if (!user.first_seen || date < new Date(user.first_seen)) user.first_seen = date;

    // A new day of use; events usually arrive in order, and rebuildUsers sorts them.
    const lastActive = user.last_active ? new Date(user.last_active) : null;
    if (!lastActive || (date > lastActive && day(date) !== day(lastActive))) {
      user.days_active = Number(user.days_active || 0) + 1;
    }
    if (!lastActive || date > lastActive) user.last_active = date;

    if (OPEN_EVENTS.includes(ev.name)) {
      user.app_opens = Number(user.app_opens || 0) + 1;
      if (!user.last_opened || date > new Date(user.last_opened)) user.last_opened = date;
    }
    Object.entries(COUNTED).forEach(([column, names]) => {
      if (names.includes(ev.name)) user[column] = Number(user[column] || 0) + 1;
    });
    if (typeof ev.minutesSaved === 'number') {
      user.minutes_saved = Math.round((Number(user.minutes_saved || 0) + ev.minutesSaved) * 10) / 10;
    }
  });

  const sheet = book.getSheetByName('Users') || book.insertSheet('Users', 0);
  const rows = [...users.values()]
    .sort((a, b) => new Date(b.last_active || 0) - new Date(a.last_active || 0))
    .map((user) => USER_COLUMNS.map((name) => user[name] ?? ''));
  sheet.clearContents();
  sheet.getRange(1, 1, 1, USER_COLUMNS.length).setValues([USER_COLUMNS]).setFontWeight('bold');
  sheet.setFrozenRows(1);
  if (rows.length) {
    sheet.getRange(2, 1, rows.length, USER_COLUMNS.length).setValues(rows);
    sheet.getRange(2, 3, rows.length, 3).setNumberFormat('yyyy-mm-dd h:mm am/pm');
  }
}

function json(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
