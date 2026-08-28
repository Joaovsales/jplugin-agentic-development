---
name: security-scan
description: "OWASP-focused security audit scoped to the files changed in this session, worked through an explicit per-category checklist (input validation, authn/authz, secrets, crypto, dependencies, error handling). Use before committing or deploying changed code. Triggers on: 'security scan', 'check for vulnerabilities', 'any security issues in what I changed', 'is this safe to ship', 'OWASP audit'."
disable-model-invocation: false
harness: universal
---

# /security-scan — Security Review

Run a focused security audit on recently changed code before committing or deploying.

## Scope — Files to Scan

```bash
# Changed but not yet committed:
git diff --name-only

# Changed in last commit:
git diff --name-only HEAD~1..HEAD
```

Only scan files that were actually modified. Skip generated files and lock files.

## Security Checklist

Work through each changed file and check:

### Input Validation
- [ ] All external inputs validated at system boundaries (user input, API requests, file uploads)
- [ ] No raw SQL string concatenation — use parameterized queries or ORM
- [ ] File uploads validated: type, size, and content (not just extension)
- [ ] URL and file path inputs sanitized to prevent directory traversal

### Authentication & Authorization
- [ ] Authentication required on all sensitive endpoints
- [ ] Authorization checked per-request (not just login state)
- [ ] No hardcoded credentials, tokens, or API keys in source
- [ ] Secrets loaded from environment variables only
- [ ] Session tokens have expiry and are invalidated on logout

### Data Exposure
- [ ] No sensitive data (PII, tokens, passwords) in logs
- [ ] API responses don't leak internal fields or stack traces
- [ ] Error messages in production are generic (no implementation details)
- [ ] Database queries select only needed columns (no `SELECT *` on sensitive tables)

### Injection Vectors
- [ ] No XSS: user content is escaped before rendering as HTML
- [ ] No command injection: no `shell=True` or `exec()` with user-controlled input
- [ ] No template injection: user input not embedded raw in template strings
- [ ] No SSRF: user-controlled URLs are validated against an allowlist

### Dependencies
- [ ] No new packages introduced with known CVEs (`npm audit` / `pip-audit`)
- [ ] No `eval()` with user input
- [ ] No deserializing untrusted data with `pickle`, `yaml.load`, or equivalent

## Output Format

```markdown
## Security Scan — [YYYY-MM-DD]

### Files Scanned
- path/to/file1.py
- path/to/file2.ts

### Issues Found

| Severity | File | Issue | Recommendation |
|----------|------|-------|----------------|
| HIGH     | ...  | ...   | ...            |
| MEDIUM   | ...  | ...   | ...            |

### Clean Files
- [files with no issues found]

### Verdict
[PASS — no issues found]
[FAIL — N issue(s) must be fixed before committing]
```

## On Failure

Fix all HIGH and MEDIUM issues immediately. Do not commit until the scan passes.
For LOW issues: document them and create follow-up tasks in `tasks/todo.md`.
