# MCP Servers Testing Notes

## Branch
`feature/mcp-servers`

## Summary
Added MCP (Model Context Protocol) server support to the Coder k8s-workspace template.

## MCP Servers Implemented

| Server | Package | Version | Notes |
|--------|---------|---------|-------|
| Playwright | `@playwright/mcp` | 0.0.48 | Browser automation |
| Coder | `coder exp mcp server` | built-in | Requires `coder_login` enabled |
| Kubernetes | `kubernetes-mcp-server` | 0.0.54 | Creates SA but no RBAC yet |
| GitHub | Remote server | - | Uses `api.githubcopilot.com/mcp/` |
| Memory | `@modelcontextprotocol/server-memory` | 0.6.3 | Persists to `/home/coder/.claude/memory.json` |
| Context7 | `@upstash/context7-mcp` | 1.0.29 | Documentation lookup |

## Testing Checklist

### Parameter UI Testing
- [ ] MCP Servers section appears below Claude Code section
- [ ] MCP Servers section only appears when Claude Code is enabled
- [ ] Individual server toggles only appear when "Enable MCP Servers" is checked
- [ ] Coder MCP toggle is disabled (grayed out) when `coder_login` is false
- [ ] All icons display correctly

### MCP Server Functionality Testing

#### Playwright
- [ ] Enable and verify MCP server starts
- [ ] Test: Ask Claude to navigate to a website and extract information
- [ ] Note: Browser runs headless, no visual display

#### Coder
- [ ] Only test when `coder_login` is enabled
- [ ] Test: Ask Claude to list workspaces or templates
- [ ] Test: Ask Claude to check workspace status

#### Kubernetes
- [ ] Enable and verify MCP server starts
- [ ] Test: Ask Claude to list pods in the development namespace
- [ ] Note: Service account created but has no RBAC permissions yet (will fail)
- [ ] TODO: Add RBAC or use Teleport for kubeconfig

#### GitHub
- [ ] Enable and verify connection to remote MCP server
- [ ] Test: Ask Claude to list issues in a repository
- [ ] Test: Ask Claude to get PR details
- [ ] Note: Requires GitHub Copilot access via external auth

#### Memory
- [ ] Enable and verify MCP server starts
- [ ] Test: Ask Claude to remember something, then restart workspace
- [ ] Verify memory persists in `/home/coder/.claude/memory.json`

#### Context7
- [ ] Enable and verify MCP server starts
- [ ] Test: Ask Claude to look up documentation for a library

## Files Changed
- `mcp.tf` - New file with all MCP server configuration
- `claude.tf` - Added `mcp = local.mcp_config` to module
- `kubernetes.tf` - Updated parameter ordering chain

## Known Issues / TODOs
1. Kubernetes MCP service account has no RBAC - will need separate setup or Teleport integration
2. GitHub MCP uses remote server requiring Copilot access
3. No VNC for Playwright browser visibility (by design)
4. Icons may need to be added to Coder if not present (playwright.svg, book.svg)

## Rollback
If issues occur, the branch can be reverted. The main changes are isolated to the new `mcp.tf` file.

## Post-Testing
After successful testing:
1. Create PR from `feature/mcp-servers` to `master`
2. Add RBAC for Kubernetes MCP service account (separate task)
3. Consider adding more MCP servers as needed
