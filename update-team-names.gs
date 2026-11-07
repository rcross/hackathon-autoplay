/**
 * Fills the "Team name" question of the judging form with the team names
 * from the submission responses sheet. Safe to run again whenever new
 * submissions arrive: it replaces the whole list each time.
 *
 * How to use:
 *   1. Open the judging form in edit mode, then ⋮ (top right) → Apps Script.
 *   2. Replace the code in the editor with this file and click Save.
 *   3. Choose "updateTeamNames" in the function menu and click Run.
 *      The first time, Google asks you to authorise access to the form and sheet.
 *   4. Optional: run "updateEveryHour" once to keep the list up to date automatically.
 *
 * The question must be a Dropdown, Multiple choice or Checkboxes question with
 * "team name" in its title.
 */

const FORM_ID   = '1Qpef_wyRbkxIazXpPMkIdN-cI7yVH4wcnKOchppjgQk';
const SHEET_ID  = '1TuKzcx9GDQsScX8izS0m_QAssY0nIFnrsKUOXsBLABI';
const SHEET_GID = 1733447410;
const QUESTION_TITLE = /team\s*name/i;
const IGNORE_TEAMS   = /^(dummy|test)\d*$/i;   // test submissions

function updateTeamNames() {
  // Read the team names from the responses sheet
  const ss = SpreadsheetApp.openById(SHEET_ID);
  const sheet = ss.getSheets().find(s => s.getSheetId() === SHEET_GID) || ss.getSheets()[0];
  const rows = sheet.getDataRange().getDisplayValues();
  const col = rows[0].findIndex(h => /^team name/i.test(String(h).trim()));
  if (col < 0) throw new Error('The responses sheet has no "Team name" column');

  // Tidy spaces, drop blanks/test entries, remove duplicates (ignoring case), sort A-Z
  const unique = new Map();
  rows.slice(1).forEach(r => {
    const name = String(r[col]).replace(/\s+/g, ' ').trim();
    if (!name || IGNORE_TEAMS.test(name)) return;
    const key = name.toLowerCase();
    if (!unique.has(key)) unique.set(key, name);
  });
  const names = [...unique.values()].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base', numeric: true }));
  if (!names.length) throw new Error('No team names found in the responses sheet');

  // Find the Team name question and replace its options
  const form = FormApp.openById(FORM_ID);
  const item = form.getItems().find(i => QUESTION_TITLE.test(i.getTitle()));
  if (!item) throw new Error('The form has no question with "team name" in its title');
  let question;
  switch (item.getType()) {
    case FormApp.ItemType.LIST:            question = item.asListItem(); break;
    case FormApp.ItemType.MULTIPLE_CHOICE: question = item.asMultipleChoiceItem(); break;
    case FormApp.ItemType.CHECKBOX:        question = item.asCheckboxItem(); break;
    default:
      throw new Error('"' + item.getTitle() + '" is a ' + item.getType() +
        ' question. Change it to Dropdown (or Multiple choice) first.');
  }
  question.setChoiceValues(names);
  Logger.log('Updated "%s" with %s teams:\n%s', item.getTitle(), names.length, names.join('\n'));
}

/** Run once to refresh the team list every hour (delete the trigger after the event). */
function updateEveryHour() {
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'updateTeamNames')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('updateTeamNames').timeBased().everyHours(1).create();
  updateTeamNames();
}
