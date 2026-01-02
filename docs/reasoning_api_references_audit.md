# Reasoning API References Audit

## Summary
After implementing the Redis-based Reasoning Worker (Phases 1-3), I've audited all references to "REASONING_API" in the codebase.

## Active Code References

### ✅ Safe/Intentional References

These references are either:
1. **Legacy compatibility** - Checking if old API URL is configured
2. **Environment variable names** - Still used for timeout/retry settings
3. **Documentation** - Historical context

#### 1. `lib/savant/reasoning/client.rb` (Lines 20-21)
```ruby
DEFAULT_TIMEOUT_MS = (ENV['REASONING_API_TIMEOUT_MS'] || '30000').to_i
DEFAULT_RETRIES = (ENV['REASONING_API_RETRIES'] || '2').to_i
```
**Status:** ✅ **SAFE** - These env vars control Redis client timeout/retries, not HTTP API
**Action:** None needed - variable names are fine for backwards compatibility

#### 2. `lib/savant/hub/router.rb` (Line 1085)
```ruby
base_url = ENV['REASONING_API_URL'].to_s
```
**Status:** ✅ **SAFE** - Used in diagnostics to check if legacy API is configured
**Context:** Part of `build_reasoning_diagnostics` which checks for old setup
**Action:** Updated comment to clarify this is legacy check

#### 3. `lib/savant/engines/context/fs/repo_indexer.rb` (Line 312)
```ruby
env_url = ENV['REASONING_API_URL'].to_s
```
**Status:** ⚠️ **REVIEW NEEDED** - May be dead code
**Action:** Need to check if this is still used

#### 4. `lib/savant/agent/runtime.rb` (Lines 59, 61, 69, 292)
```ruby
model = 'reasoning_api/v1'
force = ENV['FORCE_REASONING_API']
```
**Status:** ⚠️ **REVIEW NEEDED** - Model identifier and force flag
**Action:** These may be used for routing decisions

## Documentation References

### Files with Documentation/Historical References:
- `docs/ENV_DEFAULTS.md` - Documents env vars (historical)
- `README.md` - Setup instructions (may need update)
- `docs/prds/done/langchain-graph-api.md` - Original PRD (historical)
- `memory_bank/reasoning_api.md` - Architecture docs (needs update)

**Action:** Documentation should be updated to reflect Redis-based architecture

## Recommendations

### Immediate Actions:
1. ✅ **DONE** - Updated hub/router.rb comment
2. ⏳ **TODO** - Check `repo_indexer.rb` usage
3. ⏳ **TODO** - Check `agent/runtime.rb` model routing
4. ⏳ **TODO** - Update `memory_bank/reasoning_api.md` to reflect Redis architecture
5. ⏳ **TODO** - Update `README.md` setup instructions

### Environment Variables Strategy:
**Keep these names for backwards compatibility:**
- `REASONING_API_TIMEOUT_MS` → Controls Redis client timeout
- `REASONING_API_RETRIES` → Controls Redis client retries
- `REASONING_API_URL` → Legacy check only (diagnostics)

**New/Primary variables:**
- `REDIS_URL` → Redis connection string (primary)
- `REASONING_TRANSPORT` → Always 'redis' now

## Conclusion

The core implementation is clean - the Reasoning API HTTP server has been removed and replaced with Redis-based worker. The remaining references are:

1. **Environment variable names** - Kept for backwards compatibility
2. **Diagnostics code** - Checks for legacy setup
3. **Documentation** - Needs updating
4. **Potential dead code** - Needs review in repo_indexer.rb and agent/runtime.rb

No active code is trying to start or connect to the HTTP Reasoning API anymore.
