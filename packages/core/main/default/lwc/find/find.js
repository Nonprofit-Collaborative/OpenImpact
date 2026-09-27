import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/FindController.getContext';
import getObjects from '@salesforce/apex/FindController.getObjects';
import describePaths from '@salesforce/apex/FindController.describePaths';
import previewQuery from '@salesforce/apex/FindController.preview';
import runQuery from '@salesforce/apex/FindController.run';
import exportPage from '@salesforce/apex/FindController.exportPage';
import getSavedQueries from '@salesforce/apex/FindController.getSavedQueries';
import openQuery from '@salesforce/apex/FindController.openQuery';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import { toCsv, download, fileName, HANDOFF_KEY } from 'c/findCsv';
import {
  LABELS,
  CHOSEN_DATE,
  operatorsFor,
  relativeOptions,
  buildDocument,
  needsValue
} from './findModel';

const PREVIEW_DELAY_MS = 300;

/**
 * Find (C-34): a visual query builder over one kind of record, its results, saved queries and
 * the CSV export. See docs/admin-guide/find.md.
 *
 * The page builds a query document (canonical model Section 17B) and nothing else. The server
 * compiles it from the running user's own describe results, runs it in user mode and renders the
 * read-only query shown here; this component never writes or sends query text.
 */
export default class Find extends NavigationMixin(LightningElement) {
  labels = LABELS;
  context;
  objects = [];
  objectName;
  objectLabel;
  columns = [];
  filters = [];
  sorts = [];
  logic = '';
  rowLimit = '';
  pendingColumn;

  soql = '';
  soqlError;
  result;
  error;
  notice;
  loading = true;
  working = false;

  savedQueries = [];
  current;
  saving = false;
  saveName = '';
  saveShared = false;

  nextKey = 1;
  previewTimer;

  async connectedCallback() {
    try {
      this.context = await getContext();
      if (this.context && this.context.canUse) {
        const [objects, saved] = await Promise.all([getObjects(), getSavedQueries()]);
        this.objects = (objects || []).map((o) => ({ label: o.label, value: o.name }));
        this.savedQueries = saved || [];
      }
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.loading = false;
    }
  }

  disconnectedCallback() {
    clearTimeout(this.previewTimer);
  }

  get canUse() {
    return Boolean(this.context && this.context.canUse);
  }

  get cannotUse() {
    return !this.loading && !this.canUse;
  }

  get hasObject() {
    return Boolean(this.objectName);
  }

  get cannotRun() {
    return !this.hasObject || this.working;
  }

  get canSendToBulkUpdate() {
    return Boolean(this.context && this.context.bulkUpdateTab) && this.hasObject;
  }

  get savedOptions() {
    return this.savedQueries.map((query) => ({
      label: query.isOwn
        ? query.name
        : LABELS.sharedBy.replace('{0}', query.name).replace('{1}', query.ownerName || ''),
      value: query.id
    }));
  }

  get currentId() {
    return this.current ? this.current.id : undefined;
  }

  get canDelete() {
    return Boolean(this.current && this.current.isOwn);
  }

  get sharedNote() {
    return this.current && !this.current.isOwn
      ? LABELS.sharedNote.replace('{0}', this.current.ownerName || '')
      : undefined;
  }

  get rowLimitHelp() {
    return LABELS.rowLimitHelp.replace('{0}', this.gridMax);
  }

  get gridMax() {
    return (this.context && this.context.gridMaxRows) || 2000;
  }

  get filterRows() {
    return this.filters.map((filter, index) => {
      const operators = filter.path ? operatorsFor(filter.type) : [];
      const isDate = filter.type === 'date' || filter.type === 'datetime';
      const relative = filter.relative || '';
      const relativeChoice = relative || CHOSEN_DATE;
      const showValue = needsValue(filter.operator) && !relative;
      const isList = filter.operator === 'in' || filter.operator === 'not in';
      return {
        ...filter,
        number: index + 1,
        hasField: Boolean(filter.path),
        operators,
        isDate,
        relativeOptions: relativeOptions(),
        relative,
        relativeChoice,
        showRelative:
          isDate &&
          [
            'equals',
            'not equals',
            'less than',
            'less or equal',
            'greater than',
            'greater or equal'
          ].includes(filter.operator),
        showDays: relative === 'LAST_N_DAYS' || relative === 'NEXT_N_DAYS',
        showValue,
        isList,
        isBoolean: showValue && filter.type === 'boolean',
        isPicklist:
          showValue &&
          !isList &&
          filter.type === 'picklist' &&
          (filter.picklistValues || []).length > 0,
        isInput:
          showValue &&
          filter.type !== 'boolean' &&
          !(!isList && filter.type === 'picklist' && (filter.picklistValues || []).length > 0),
        inputType: isList ? 'text' : inputType(filter.type),
        booleanOptions: [
          { label: LABELS.yes, value: 'true' },
          { label: LABELS.no, value: 'false' }
        ]
      };
    });
  }

  get sortRows() {
    return this.sorts.map((sort) => ({ ...sort, hasField: Boolean(sort.path) }));
  }

  get directionOptions() {
    return [
      { label: LABELS.ascending, value: 'ASC' },
      { label: LABELS.descending, value: 'DESC' }
    ];
  }

  get canAddSort() {
    return (
      this.hasObject && this.sorts.length < ((this.context && this.context.maxSortFields) || 3)
    );
  }

  get cannotAddSort() {
    return !this.canAddSort;
  }

  get cannotAddColumn() {
    return !this.pendingColumn;
  }

  get tableColumns() {
    if (!this.result) {
      return [];
    }
    return this.result.columns.map((column, index) => ({
      label: column.label,
      fieldName: `c${index}`,
      type: tableType(column.type)
    }));
  }

  get tableRows() {
    if (!this.result) {
      return [];
    }
    return this.result.rows.map((row) => {
      const shaped = { key: row.Id };
      this.result.columns.forEach((column, index) => {
        shaped[`c${index}`] = row[column.path];
      });
      return shaped;
    });
  }

  get hasRows() {
    return Boolean(this.result && this.result.rows.length > 0);
  }

  get noRows() {
    return Boolean(this.result && this.result.rows.length === 0);
  }

  get resultsCount() {
    return this.result ? LABELS.resultsCount.replace('{0}', this.result.rows.length) : '';
  }

  get resultsLimit() {
    return this.result && this.result.limitReached
      ? LABELS.resultsLimit.replace('{0}', this.result.rows.length)
      : undefined;
  }

  // ---------------------------------------------------------------------------------------
  // Building
  // ---------------------------------------------------------------------------------------

  handleObjectChange(event) {
    this.objectName = event.detail.value;
    const chosen = this.objects.find((o) => o.value === this.objectName);
    this.objectLabel = chosen ? chosen.label : this.objectName;
    this.columns = [];
    this.filters = [];
    this.sorts = [];
    this.logic = '';
    this.result = undefined;
    this.current = undefined;
    this.pendingColumn = undefined;
    this.schedulePreview();
  }

  handleColumnPick(event) {
    this.pendingColumn = event.detail;
  }

  handleAddColumn() {
    const pick = this.pendingColumn;
    if (!pick || this.columns.some((c) => c.path.toLowerCase() === pick.path.toLowerCase())) {
      return;
    }
    this.columns = [
      ...this.columns,
      { key: this.key(), path: pick.path, label: pick.label, type: pick.type }
    ];
    this.pendingColumn = undefined;
    const picker = this.template.querySelector('[data-id="column-picker"]');
    if (picker) {
      picker.reset();
    }
    this.schedulePreview();
  }

  handleRemoveColumn(event) {
    const key = event.currentTarget.dataset.key;
    this.columns = this.columns.filter((c) => String(c.key) !== key);
    this.schedulePreview();
  }

  handleAddFilter() {
    this.filters = [...this.filters, { key: this.key(), operator: 'equals', value: '' }];
  }

  handleFilterPick(event) {
    const key = event.currentTarget.dataset.key;
    const pick = event.detail;
    this.updateFilter(key, {
      path: pick.path,
      label: pick.label,
      type: pick.type,
      picklistValues: pick.picklistValues,
      operator: operatorsFor(pick.type)[0].value,
      value: '',
      relative: ''
    });
  }

  handleFilterChange(event) {
    const key = event.currentTarget.dataset.key;
    const part = event.currentTarget.dataset.part;
    const value =
      part === 'relative' && event.detail.value === CHOSEN_DATE ? '' : event.detail.value;
    const changes = { [part]: value };
    if (part === 'operator' && !needsValue(value)) {
      changes.value = '';
      changes.relative = '';
    }
    this.updateFilter(key, changes);
  }

  handleRemoveFilter(event) {
    const key = event.currentTarget.dataset.key;
    this.filters = this.filters.filter((f) => String(f.key) !== key);
    this.schedulePreview();
  }

  handleLogicChange(event) {
    this.logic = event.detail.value;
    this.schedulePreview();
  }

  handleAddSort() {
    this.sorts = [...this.sorts, { key: this.key(), direction: 'ASC' }];
  }

  handleSortPick(event) {
    const key = event.currentTarget.dataset.key;
    this.updateSort(key, { path: event.detail.path, label: event.detail.label });
  }

  handleSortDirection(event) {
    this.updateSort(event.currentTarget.dataset.key, { direction: event.detail.value });
  }

  handleRemoveSort(event) {
    const key = event.currentTarget.dataset.key;
    this.sorts = this.sorts.filter((s) => String(s.key) !== key);
    this.schedulePreview();
  }

  handleRowLimit(event) {
    this.rowLimit = event.detail.value;
    this.schedulePreview();
  }

  updateFilter(key, changes) {
    this.filters = this.filters.map((f) => {
      return String(f.key) === String(key) ? { ...f, ...changes } : f;
    });
    this.schedulePreview();
  }

  updateSort(key, changes) {
    this.sorts = this.sorts.map((s) => (String(s.key) === String(key) ? { ...s, ...changes } : s));
    this.schedulePreview();
  }

  key() {
    const key = this.nextKey;
    this.nextKey += 1;
    return key;
  }

  documentJson() {
    return JSON.stringify(
      buildDocument({
        objectName: this.objectName,
        columns: this.columns,
        filters: this.filters,
        logic: this.logic,
        sorts: this.sorts,
        rowLimit: this.rowLimit
      })
    );
  }

  schedulePreview() {
    clearTimeout(this.previewTimer);
    if (!this.objectName) {
      this.soql = '';
      this.soqlError = undefined;
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.refreshPreview(), PREVIEW_DELAY_MS);
  }

  async refreshPreview() {
    try {
      const preview = await previewQuery({ documentJson: this.documentJson() });
      this.soql = (preview && preview.soql) || '';
      this.soqlError = preview ? preview.error : undefined;
    } catch (error) {
      this.soqlError = errorText(error);
    }
  }

  // ---------------------------------------------------------------------------------------
  // Running and exporting
  // ---------------------------------------------------------------------------------------

  async handleRun() {
    this.working = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      this.result = await runQuery({ documentJson: this.documentJson() });
      this.soql = this.result.soql;
      this.soqlError = undefined;
      this.relabel(this.result.columns);
    } catch (error) {
      this.result = undefined;
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  async handleExport() {
    this.working = true;
    this.error = undefined;
    this.notice = LABELS.exportProgress.replace('{0}', 0);
    const documentJson = this.documentJson();
    let columns;
    const rows = [];
    let afterId = null;
    let stoppedAt;
    try {
      for (;;) {
        // Each page waits for the one before it: the next page starts after its last record.
        // eslint-disable-next-line no-await-in-loop
        const page = await exportPage({ documentJson, afterId, alreadyExported: rows.length });
        if (!columns) {
          columns = page.columns;
        }
        for (const row of page.rows) {
          rows.push(row);
        }
        this.notice = LABELS.exportProgress.replace('{0}', rows.length);
        if (page.stoppedAtLimit) {
          stoppedAt = page.exportLimit;
        }
        if (page.done || !page.lastId || page.rows.length === 0) {
          break;
        }
        afterId = page.lastId;
      }
      download(fileName(this.objectLabel), toCsv(columns || [], rows));
      this.notice =
        stoppedAt !== undefined
          ? LABELS.exportStopped.replace('{0}', stoppedAt)
          : LABELS.exportDone.replace('{0}', rows.length);
    } catch (error) {
      this.notice = undefined;
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  handleSendToBulkUpdate() {
    try {
      window.sessionStorage.setItem(HANDOFF_KEY, this.documentJson());
    } catch {
      // Storage refused: the bulk update page then offers the saved queries instead.
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: this.context.bulkUpdateTab }
    });
  }

  /** Takes the labels the server resolved, so a loaded query shows labels, not API names. */
  relabel(described) {
    const byPath = new Map((described || []).map((d) => [d.path.toLowerCase(), d]));
    const apply = (entry) => {
      const found = entry.path ? byPath.get(entry.path.toLowerCase()) : undefined;
      return found
        ? {
            ...entry,
            label: found.label,
            type: found.type || entry.type,
            picklistValues: found.picklistValues || entry.picklistValues
          }
        : entry;
    };
    this.columns = this.columns.map(apply);
    this.filters = this.filters.map(apply);
    this.sorts = this.sorts.map(apply);
  }

  // ---------------------------------------------------------------------------------------
  // Saved queries
  // ---------------------------------------------------------------------------------------

  async handleOpenSaved(event) {
    this.error = undefined;
    this.notice = undefined;
    try {
      const saved = await openQuery({ queryId: event.detail.value });
      this.loadDocument(JSON.parse(saved.document));
      this.current = saved;
      this.saveName = saved.name;
      this.saveShared = Boolean(saved.isShared) && saved.isOwn;
      const paths = [
        ...this.columns.map((c) => c.path),
        ...this.filters.map((f) => f.path),
        ...this.sorts.map((s) => s.path)
      ];
      this.relabel(await describePaths({ objectName: this.objectName, paths }));
      this.schedulePreview();
    } catch (error) {
      this.error = errorText(error);
    }
  }

  loadDocument(document) {
    this.objectName = document.object;
    const chosen = this.objects.find(
      (o) => o.value.toLowerCase() === String(document.object).toLowerCase()
    );
    this.objectLabel = chosen ? chosen.label : document.object;
    if (chosen) {
      this.objectName = chosen.value;
    }
    this.columns = (document.fields || [])
      .filter((path) => path.toLowerCase() !== 'id')
      .map((path) => ({ key: this.key(), path, label: path }));
    const conditions = (document.filter && document.filter.conditions) || [];
    this.filters = conditions.map((condition) => ({
      key: this.key(),
      path: condition.field,
      label: condition.field,
      operator: condition.operator,
      value: Array.isArray(condition.value)
        ? condition.value.join(', ')
        : condition.value === undefined || condition.value === null
          ? ''
          : String(condition.value),
      relative: condition.relative || '',
      n: condition.n
    }));
    this.logic = (document.filter && document.filter.logic) || '';
    this.sorts = (document.orderBy || []).map((sort) => ({
      key: this.key(),
      path: sort.field,
      label: sort.field,
      direction: sort.direction === 'DESC' ? 'DESC' : 'ASC'
    }));
    this.rowLimit = document.limit ? String(document.limit) : '';
    this.result = undefined;
  }

  handleSaveStart() {
    this.saving = true;
    if (!this.current) {
      this.saveName = '';
      this.saveShared = false;
    }
  }

  handleSaveCancel() {
    this.saving = false;
  }

  handleSaveName(event) {
    this.saveName = event.detail.value;
  }

  handleSaveShared(event) {
    this.saveShared = event.detail.checked;
  }

  async handleSaveConfirm() {
    this.working = true;
    this.error = undefined;
    try {
      // A query somebody else owns is saved as the person's own copy.
      const queryId = this.current && this.current.isOwn ? this.current.id : null;
      const saved = await saveQuery({
        queryId,
        name: this.saveName,
        isShared: this.saveShared,
        documentJson: this.documentJson()
      });
      this.current = saved;
      this.saving = false;
      this.notice = LABELS.saved;
      this.savedQueries = (await getSavedQueries()) || [];
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  async handleDelete() {
    this.working = true;
    this.error = undefined;
    try {
      await deleteQuery({ queryId: this.current.id });
      this.current = undefined;
      this.notice = LABELS.deleted;
      this.savedQueries = (await getSavedQueries()) || [];
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }
}

function inputType(type) {
  if (['integer', 'long', 'double', 'currency', 'percent'].includes(type)) {
    return 'number';
  }
  if (type === 'date' || type === 'datetime') {
    return 'date';
  }
  return 'text';
}

function tableType(type) {
  switch (type) {
    case 'integer':
    case 'long':
    case 'double':
    case 'percent':
      return 'number';
    case 'currency':
      return 'currency';
    case 'boolean':
      return 'boolean';
    case 'date':
      return 'date-local';
    case 'datetime':
      return 'date';
    default:
      return 'text';
  }
}

function errorText(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : String(error);
}
