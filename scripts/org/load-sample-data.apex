// Anonymous Apex run by scripts/org/seed-sample-data.sh. Starts the C-10 sample data
// load; the loader runs as a chain of queueable jobs, so this call returns immediately.
// See docs/admin-guide/sample-data.md and data/sample/README.md.
SampleDataLoader.load();
