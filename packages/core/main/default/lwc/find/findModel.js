import noPermission from '@salesforce/label/c.Core_Find_ErrorNoPermission';
import heading from '@salesforce/label/c.Core_Find_Heading';
import objectLabel from '@salesforce/label/c.Core_Find_ObjectLabel';
import objectPlaceholder from '@salesforce/label/c.Core_Find_ObjectPlaceholder';
import columnsHeading from '@salesforce/label/c.Core_Find_ColumnsHeading';
import addColumn from '@salesforce/label/c.Core_Find_AddColumnButton';
import remove from '@salesforce/label/c.Core_Find_RemoveButton';
import filtersHeading from '@salesforce/label/c.Core_Find_FiltersHeading';
import addFilter from '@salesforce/label/c.Core_Find_AddFilterButton';
import field from '@salesforce/label/c.Core_Find_FieldLabel';
import condition from '@salesforce/label/c.Core_Find_ConditionLabel';
import value from '@salesforce/label/c.Core_Find_ValueLabel';
import when from '@salesforce/label/c.Core_Find_WhenLabel';
import whenValue from '@salesforce/label/c.Core_Find_WhenValue';
import days from '@salesforce/label/c.Core_Find_DaysLabel';
import listHint from '@salesforce/label/c.Core_Find_ListHint';
import logicLabel from '@salesforce/label/c.Core_Find_LogicLabel';
import logicHelp from '@salesforce/label/c.Core_Find_LogicHelp';
import sortHeading from '@salesforce/label/c.Core_Find_SortHeading';
import addSort from '@salesforce/label/c.Core_Find_AddSortButton';
import direction from '@salesforce/label/c.Core_Find_DirectionLabel';
import ascending from '@salesforce/label/c.Core_Find_Ascending';
import descending from '@salesforce/label/c.Core_Find_Descending';
import rowLimitLabel from '@salesforce/label/c.Core_Find_RowLimitLabel';
import rowLimitHelp from '@salesforce/label/c.Core_Find_RowLimitHelp';
import run from '@salesforce/label/c.Core_Find_RunButton';
import queryLabel from '@salesforce/label/c.Core_Find_QueryLabel';
import resultsCount from '@salesforce/label/c.Core_Find_ResultsCount';
import resultsLimit from '@salesforce/label/c.Core_Find_ResultsLimit';
import noResults from '@salesforce/label/c.Core_Find_NoResults';
import save from '@salesforce/label/c.Core_Find_SaveButton';
import saveName from '@salesforce/label/c.Core_Find_SaveNameLabel';
import saveShare from '@salesforce/label/c.Core_Find_SaveShareLabel';
import saveConfirm from '@salesforce/label/c.Core_Find_SaveConfirmButton';
import cancel from '@salesforce/label/c.Core_Find_CancelButton';
import saved from '@salesforce/label/c.Core_Find_Saved';
import sharedNote from '@salesforce/label/c.Core_Find_SharedNote';
import openSaved from '@salesforce/label/c.Core_Find_OpenSavedLabel';
import sharedBy from '@salesforce/label/c.Core_Find_SharedBy';
import deleteQuery from '@salesforce/label/c.Core_Find_DeleteButton';
import deleted from '@salesforce/label/c.Core_Find_Deleted';
import exportButton from '@salesforce/label/c.Core_Find_ExportButton';
import exportProgress from '@salesforce/label/c.Core_Find_ExportProgress';
import exportDone from '@salesforce/label/c.Core_Find_ExportDone';
import exportStopped from '@salesforce/label/c.Core_Find_ExportStopped';
import sendToBulkUpdate from '@salesforce/label/c.Core_Find_SendToBulkUpdate';
import opEquals from '@salesforce/label/c.Core_Find_OpEquals';
import opNotEquals from '@salesforce/label/c.Core_Find_OpNotEquals';
import opLess from '@salesforce/label/c.Core_Find_OpLess';
import opLessEqual from '@salesforce/label/c.Core_Find_OpLessEqual';
import opGreater from '@salesforce/label/c.Core_Find_OpGreater';
import opGreaterEqual from '@salesforce/label/c.Core_Find_OpGreaterEqual';
import opContains from '@salesforce/label/c.Core_Find_OpContains';
import opNotContains from '@salesforce/label/c.Core_Find_OpNotContains';
import opStarts from '@salesforce/label/c.Core_Find_OpStarts';
import opNull from '@salesforce/label/c.Core_Find_OpNull';
import opNotNull from '@salesforce/label/c.Core_Find_OpNotNull';
import opIn from '@salesforce/label/c.Core_Find_OpIn';
import opNotIn from '@salesforce/label/c.Core_Find_OpNotIn';
import relToday from '@salesforce/label/c.Core_Find_RelToday';
import relThisMonth from '@salesforce/label/c.Core_Find_RelThisMonth';
import relLastMonth from '@salesforce/label/c.Core_Find_RelLastMonth';
import relThisYear from '@salesforce/label/c.Core_Find_RelThisYear';
import relLastYear from '@salesforce/label/c.Core_Find_RelLastYear';
import relLastNDays from '@salesforce/label/c.Core_Find_RelLastNDays';
import relNextNDays from '@salesforce/label/c.Core_Find_RelNextNDays';
import yes from '@salesforce/label/c.Core_Find_Yes';
import no from '@salesforce/label/c.Core_Find_No';
import loadingAltText from '@salesforce/label/c.Core_Find_LoadingAltText';

/**
 * The query model behind the Find page: its labels, the conditions each field type offers
 * (the same lists the server enforces, canonical model R-R2 and R-Q2), and the query document
 * the page sends (Section 17B).
 */
export const LABELS = {
  noPermission,
  heading,
  objectLabel,
  objectPlaceholder,
  columnsHeading,
  addColumn,
  remove,
  filtersHeading,
  addFilter,
  field,
  condition,
  value,
  when,
  whenValue,
  days,
  listHint,
  logicLabel,
  logicHelp,
  sortHeading,
  addSort,
  direction,
  ascending,
  descending,
  rowLimit: rowLimitLabel,
  rowLimitHelp,
  run,
  queryLabel,
  resultsCount,
  resultsLimit,
  noResults,
  save,
  saveName,
  saveShare,
  saveConfirm,
  cancel,
  saved,
  sharedNote,
  openSaved,
  sharedBy,
  deleteQuery,
  deleted,
  exportButton,
  exportProgress,
  exportDone,
  exportStopped,
  sendToBulkUpdate,
  yes,
  no,
  loadingAltText
};

const TEXT = ['string', 'textarea', 'email', 'phone', 'url', 'combobox'];
const NUMBER = ['integer', 'long', 'double', 'currency', 'percent'];
const NO_VALUE = ['is null', 'is not null'];
/** The relative option meaning a date typed in; stored as no period at all. */
export const CHOSEN_DATE = 'VALUE';

const OPERATOR_LABELS = {
  equals: opEquals,
  'not equals': opNotEquals,
  'less than': opLess,
  'less or equal': opLessEqual,
  'greater than': opGreater,
  'greater or equal': opGreaterEqual,
  contains: opContains,
  'does not contain': opNotContains,
  'starts with': opStarts,
  'is null': opNull,
  'is not null': opNotNull,
  in: opIn,
  'not in': opNotIn
};

const COMPARE = [
  'equals',
  'not equals',
  'less than',
  'less or equal',
  'greater than',
  'greater or equal'
];
const LIKE = ['contains', 'does not contain', 'starts with'];
const LIST = ['in', 'not in'];

/** The conditions a field of this describe type may use, as combobox options. */
export function operatorsFor(type) {
  let operators;
  if (type === 'boolean') {
    operators = ['equals', 'not equals'];
  } else if (type === 'multipicklist') {
    operators = ['equals', 'not equals', ...NO_VALUE];
  } else if (type === 'id' || type === 'reference') {
    operators = ['equals', 'not equals', ...LIST, ...NO_VALUE];
  } else if (type === 'picklist') {
    operators = ['equals', 'not equals', ...LIST, ...LIKE, ...NO_VALUE];
  } else if (TEXT.includes(type)) {
    operators = [...COMPARE, ...LIKE, ...LIST, ...NO_VALUE];
  } else if (NUMBER.includes(type) || type === 'date' || type === 'datetime') {
    operators = [...COMPARE, ...LIST, ...NO_VALUE];
  } else {
    operators = [...NO_VALUE];
  }
  return operators.map((operator) => ({ label: OPERATOR_LABELS[operator], value: operator }));
}

/** The relative periods a date filter offers, after "a date I choose". */
export function relativeOptions() {
  return [
    { label: whenValue, value: CHOSEN_DATE },
    { label: relToday, value: 'TODAY' },
    { label: relThisMonth, value: 'THIS_MONTH' },
    { label: relLastMonth, value: 'LAST_MONTH' },
    { label: relThisYear, value: 'THIS_YEAR' },
    { label: relLastYear, value: 'LAST_YEAR' },
    { label: relLastNDays, value: 'LAST_N_DAYS' },
    { label: relNextNDays, value: 'NEXT_N_DAYS' }
  ];
}

/** Whether a condition takes a value at all. */
export function needsValue(operator) {
  return !NO_VALUE.includes(operator);
}

/**
 * The query document (canonical model Section 17B) for what the page holds. Filters without a
 * field yet are left out; they are still being built.
 */
export function buildDocument({ objectName, columns, filters, logic, sorts, rowLimit }) {
  const chosen = (filters || []).filter((f) => f.path);
  const conditions = chosen.map((f, index) => {
    const entry = { id: index + 1, field: f.path, operator: f.operator };
    if (!needsValue(f.operator)) {
      return entry;
    }
    if (f.relative) {
      entry.relative = f.relative;
      if (f.relative === 'LAST_N_DAYS' || f.relative === 'NEXT_N_DAYS') {
        entry.n = f.n === undefined || f.n === '' ? undefined : Number(f.n);
      }
      return entry;
    }
    if (LIST.includes(f.operator)) {
      entry.value = String(f.value || '')
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part.length > 0);
      return entry;
    }
    entry.value = f.value === undefined ? '' : f.value;
    return entry;
  });
  const document = {
    version: 1,
    object: objectName,
    fields: (columns || []).map((c) => c.path),
    filter: { conditions },
    orderBy: (sorts || [])
      .filter((s) => s.path)
      .map((s) => ({
        field: s.path,
        direction: s.direction === 'DESC' ? 'DESC' : 'ASC',
        nulls: 'LAST'
      }))
  };
  if (logic && String(logic).trim()) {
    document.filter.logic = String(logic).trim();
  }
  if (rowLimit !== undefined && rowLimit !== null && String(rowLimit).trim() !== '') {
    document.limit = Number(rowLimit);
  }
  return document;
}
