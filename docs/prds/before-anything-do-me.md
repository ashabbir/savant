change think 
remove driver from think as we have a new engine 

update workflow remove driver version from workflows remove rules from workflows 



for drivers, personas, rulesets, workflows 
understand this 
all MCP reads and writes to the data base 
we do not need the yaml files 
we dont keep the yaml files 
this data will be seeded 


there is a mongo i need a make task to connect to that mongo and run mongo console so i can query it 
it should be called make mongosh

in mongo we need savant_development and savant_test db 
all logs are stored in respective db for respective collections 
e.g. for mcp personas logs are in personas collection
driver logs are in drivers collection 

hub logs are in hub collection 

make sure all logs are stored accordingly 
also these logs need to be stdioed as well 

Once you have done that look at 
docs/prds/architecture/00-architecture-full.md

and there is an implementation plan in the same directory implement it one by one 

---

## Agent Implementation Plan

1) Swap Think → Drivers for driver prompts
- Remove any Think engine driver loading. Use Drivers engine (DB-backed) to fetch driver by name.
- Change Boot to accept `driver_name` (default: `developer`) instead of `driver_version`.
- Update CLI output to show driver name and version.

2) Database-only catalogs (no YAML persistence)
- Ensure Personas, Drivers, Rulesets, and Think Workflows CRUD go through Postgres.
- Keep YAML import/export only as optional helpers; do not persist YAML files in repo.

3) Logging to Mongo + stdio
- Use `Savant::Logging::MongoLogger` for MCP engines (personas, drivers, rules, think, context, git, jira) and Hub.
- Collections: one per service (e.g., `personas`, `drivers`, `hub`).
- Keep stdout JSON logging enabled.
- Provide `make mongosh` to connect (uses `savant_development` / `savant_test`).

4) Docs updates (Memory Bank)
- Update `memory_bank/logging.md` with Mongo logger usage, env vars (`MONGO_URI`, `SAVANT_ENV`), and `make mongosh`.
- Clarify that Think no longer injects a driver; workflows must call Drivers if needed.

5) Validate
- Run `bundle exec rubocop -A` and `bundle exec rspec`.
- Commit on branch `feature/before-anything-do-me` and push.

Deliverables
- Code changes in Boot and logging sites.
- Updated Memory Bank docs.
- Tests and lints green.


all logs should be written in mongo 
that includes Run logs and workflow execution logs 
i will use them to fill up the UI 
