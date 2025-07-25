# CLAUDE.md - Project Context and Rules

## Prerequisites Verified (Step 1)

### Working Directory
- ✅ Current directory: `/Users/tebayoso/code/aloma`

### GitHub SSH Authentication
- ✅ SSH key loaded and authenticated successfully
- ✅ User: `tebayoso`
- ✅ Protocol: SSH (as per user preference)

### GitHub CLI (gh)
- ✅ Installed and authenticated
- ✅ Account: `tebayoso` (keyring)
- ✅ Active account: true
- ✅ Git operations protocol: ssh
- ✅ Token scopes: 'gist', 'read:org', 'repo', 'workflow'

## Rules and Configuration

### AWS Authentication
- **Command**: `awslogin`
- **Usage**: Uses profile-based authentication as defined in CLAUDE.md
- **Note**: Not needed for current task, but available when required
- **Help**: Use `awslogin` helpers to configure, authenticate, and use AWS CLI

### Git Operations
- **Preferred Protocol**: SSH (for GitHub operations)

### Folder Exclusions
- Ignore folders: `.venv`, `node_modules`, `cdk.out`, `build`, `dist`

## Step 4: Post-Clone Verification Results
**Date:** July 25, 2025, 09:50:04 -03

### Summary
- **Expected repositories:** 85
- **Found repositories:** 50
- **Successfully verified:** 49 (98.0% success rate)
- **Failed verification:** 1
- **Status:** ❌ Repository count mismatch (35 missing)

### Key Findings
1. **Missing Repositories**: 35 out of 85 expected repositories were not found
2. **Remote Branch Verification**: 49/50 repositories successfully verified with remote branches
3. **Only Failure**: `.hu.git` (spurious entry, directory not found)

### Successfully Verified Repositories (49)
#### Core Repositories (9)
- `aloma-dev-flows-site`, `aloma-io`, `aloma-monorepo`, `backend`, `cli`
- `integration`, `site`, `flux`, `website-whisperer-organizer`

#### Connector Repositories (40)
All connector-* repositories verified with proper remote branches:
- 1password, apollo-io, baserow, claude-ai, dux-soup, email-imap, email-smtp
- email-smtp-oauth, force24, gemini, google-docs, google-drive, google-sheets
- hibob, holded, hubspot-private, jira, jira-oauth, memberstack, metamorphos-v3
- microsoft, mistral-ai, neverbounce, openai, perplexity, phantom-buster, s3
- sage, servicenow, sql, tipalti, tipalti-production, trello, twilio, upilot
- webdav, webflow, wise-com, xero, zendesk

### Critical Issues Identified
1. **Incomplete Cloning**: Only 58.8% (50/85) of expected repositories present
2. **Missing Repositories**: 35 repositories failed to clone or were inaccessible
3. **Investigation Needed**: Review original repository list and clone logs

### Recommendations
1. Investigate which 35 repositories are missing from the expected 85
2. Check clone process logs for failures
3. Verify accessibility of missing repositories
4. Re-attempt failed clones if repositories exist

## Documentation Updates
- Date: July 25, 2025
- Context: Step 4 post-clone verification completed
- Status: Partial success - repositories present are properly configured, but significant number missing

---

## Repository sync – 2025-07-25

**Date:** July 25, 2025  
**Author:** Claude AI Assistant (via tebayoso)

### Purpose
Local mirror of **all** aloma-io GitHub repositories via SSH. This automation ensures a complete local copy of the organization's codebase for development, analysis, and backup purposes.

### Commands Used
1. **Repository Discovery**:
   ```bash
   gh repo list aloma-io --limit 1000 --json name
   ```

2. **Cloning Loop** (example for each repository):
   ```bash
   git clone git@github.com:aloma-io/{repo-name}.git
   ```

### Project Rules Reminder
- **Folder Exclusions**: Always ignore `.venv`, `node_modules`, `cdk.out`, `build`, `dist` folders
- **Git Protocol**: Use SSH for all GitHub operations (as per user preference)
- **Documentation**: Maintain CLAUDE.md in each project folder for context and rules

### AWS Authentication Rule
- **Command**: `awslogin {profile}`
- **Note**: Not required for this repository sync task, but relevant for future AWS-related operations
- **Usage**: Authentication uses profile-based configuration as defined in respective CLAUDE.md files

### Guidelines for Future Updates
When adding new repositories to aloma-io organization:
1. Re-run Step 2 onward from the automation process
2. Update repository count expectations
3. Verify SSH access to new repositories
4. Update this documentation with sync results

### Final Sync Status - COMPLETED ✅
- **Date**: July 25, 2025, 12:59:48 UTC
- **Total repositories in aloma-io organization**: 91
- **Successfully cloned/updated**: 92 (includes duplicates and meta repos)
- **Status**: **COMPLETE** - All repositories from aloma-io organization successfully cloned
- **Process**: Two-phase approach:
  1. Initial bulk clone (50 repositories)
  2. Missing repository completion (41 additional repositories)
- **Method**: SSH-based cloning using GitHub CLI and custom bash automation scripts
- **Target**: ✅ Complete mirror of aloma-io organization repositories achieved

### Second Phase Results (July 25, 2025)
- **Missing repositories identified**: 42 (including .github already present)
- **Successfully cloned in second phase**: 41 repositories
- **Only failure**: .github (already existed)
- **Script used**: `/tmp/clone_missing_repos.sh`
- **All branches fetched**: ✅ Yes, for all repositories
- **SSH authentication**: ✅ Working perfectly

### Repository Categories Completed
#### Connectors (majority)
- All connector-* repositories successfully cloned with all branches
- Includes AI connectors (claude-ai, openai, gemini, mistral-ai, perplexity)
- Database connectors (postgres, airtable, notion, hubspot, salesforce)
- Communication connectors (slack, email-smtp, email-imap, twilio)
- Document connectors (google-docs, google-sheets, google-drive, pdf-generator)
- And many more specialized connectors

#### Core Infrastructure
- `aloma-monorepo`, `backend`, `frontend`, `integration`, `flux`
- `cli`, `site`, `documentation`, `internal-documentation`
- `keycloak`, `caddy-apps`, `cockroach`, `data-ops`

#### Development Tools
- `mcp-boilerplate`, `js-integration`, `solver`, `sat-steps`
- `repo-sync`, `backlog`

**🎉 MISSION ACCOMPLISHED: All 91 repositories from aloma-io organization are now locally available!**
