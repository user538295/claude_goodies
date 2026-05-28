# Documentation Templates

This reference provides ready-to-use templates for common documentation types.

## Table of Contents
1. [Architecture Document Template](#architecture-document-template)
2. [ADR Template](#adr-template)
3. [User Story Template](#user-story-template)
4. [API Documentation Template](#api-documentation-template)
5. [Runbook Template](#runbook-template)
6. [Quick Start Guide Template](#quick-start-guide-template)

## Architecture Document Template

```markdown
**Purpose**: [One-sentence description of what this document covers]  
**Audience**: [Target readers - e.g., Backend engineers, All developers]  
**Status**: [Draft | Stable | Deprecated]  
**Last reviewed**: YYYY-MM-DD  
**Next review**: YYYY-MM-DD

# [Document Title]

## Principles

[State 3-5 key principles that guide this architecture]

1. **Principle 1**: Brief explanation
2. **Principle 2**: Brief explanation
3. **Principle 3**: Brief explanation

## Overview

[High-level summary of the architecture. Answer: What problem does this solve? What are the main components?]

## Architecture

### Component Diagram

```mermaid
[Your Mermaid diagram here]
```

### Components

#### [Component Name]
**Purpose**: [What does this component do?]  
**Technology**: [Tech stack used]  
**Responsibilities**:
- Responsibility 1
- Responsibility 2

**Interfaces**:
- Input: [What it receives]
- Output: [What it produces]

## Design Decisions

### [Decision 1]
**Context**: [Why did we need to decide?]  
**Decision**: [What did we choose?]  
**Rationale**: [Why this choice?]  
**Trade-offs**: [What did we give up?]

## Patterns and Practices

### [Pattern Name]
[When to use this pattern and how to implement it]

```[language]
// Code example
```

## Quality Attributes

### Performance
[Performance targets and how this architecture achieves them]

### Scalability
[How the system scales and limits]

### Security
[Security considerations and controls]

### Reliability
[How reliability is ensured]

## Operational Considerations

### Monitoring
[What to monitor and how]

### Deployment
[Deployment strategy and considerations]

### Maintenance
[Maintenance requirements and procedures]

## Related Documents

- [Link to related architecture doc]
- [Link to relevant ADR]
- [Link to implementation guide]

## Appendix

### Glossary
- **Term**: Definition
- **Term**: Definition

### References
- [External resource or standard]
```

## ADR Template

```markdown
# [Number]. [Short Decision Title]

**Status**: [Proposed | Accepted | Deprecated | Superseded by ADR-XXX]  
**Date**: YYYY-MM-DD  
**Deciders**: [Names, roles, or team]  
**Technical Story**: [Ticket/issue reference if applicable]

## Context

[Describe the context and background of the decision. What forces are at play? What constraints exist? What problem are we solving?]

## Decision

[State the decision clearly and concisely. What are we going to do?]

[Optionally include technical details, configuration, or implementation notes]

## Consequences

### Positive

- [Benefit 1]
- [Benefit 2]
- [Benefit 3]

### Negative

- [Trade-off 1]
- [Trade-off 2]
- [Risk or limitation]

### Neutral

- [Neutral consequence that affects the system]

## Alternatives Considered

### Option 1: [Alternative Name]
**Description**: [Brief explanation]  
**Pros**: [Benefits]  
**Cons**: [Drawbacks]  
**Rejected because**: [Reason]

### Option 2: [Alternative Name]
**Description**: [Brief explanation]  
**Pros**: [Benefits]  
**Cons**: [Drawbacks]  
**Rejected because**: [Reason]

## Implementation Notes

[Optional section for implementation details, migration path, or rollout plan]

## Related Decisions

- Supersedes: [ADR-XXX]
- Related to: [ADR-YYY]
- Impacts: [ADR-ZZZ]

## References

- [External article or documentation]
- [Internal document or research]
```

## User Story Template

```markdown
# [Number]. [Feature Name]

**Status**: [Backlog | In Progress | Blocked | Completed]  
**Priority**: [Critical | High | Medium | Low]  
**Estimated effort**: [XS | S | M | L | XL]  
**Sprint**: [Sprint number or "Unassigned"]  
**Assigned to**: [Team member or "Unassigned"]

## User Story

As a [type of user],  
I want [some goal],  
So that [some benefit/value].

## Context

[Additional context about why this feature is needed, business value, or user pain point]

## Acceptance Criteria

Given [initial context],  
When [action is performed],  
Then [expected outcome].

- [ ] Specific testable criterion 1
- [ ] Specific testable criterion 2
- [ ] Specific testable criterion 3

## Technical Notes

### Architecture Impact
[How does this affect the system architecture?]

### Dependencies
- [Dependency 1: Description]
- [Dependency 2: Description]

### Implementation Approach
[High-level technical approach or key considerations]

### Security Considerations
[Any security implications or requirements]

### Data Changes
[Database migrations, schema changes, or data migration needs]

## Design

[Link to mockups, wireframes, or design specs]

## Test Plan

### Unit Tests
- [Test scenario 1]
- [Test scenario 2]

### Integration Tests
- [Test scenario 1]
- [Test scenario 2]

### Manual Test Cases
- [ ] Test case 1
- [ ] Test case 2

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| [Risk description] | [High/Med/Low] | [High/Med/Low] | [How to mitigate] |

## Related Documents

- Architecture: [Link to architecture doc]
- ADR: [Link to related decision]
- Design: [Link to design specs]
- Parent story: [Link to epic or parent story]

## Definition of Done

- [ ] Code complete and peer reviewed
- [ ] Unit tests written and passing
- [ ] Integration tests written and passing
- [ ] Documentation updated
- [ ] Security review completed (if applicable)
- [ ] Performance testing completed (if applicable)
- [ ] Deployed to staging
- [ ] Product owner approval
- [ ] Deployed to production

## Notes

[Any additional notes, learnings, or context discovered during implementation]
```

## API Documentation Template

```markdown
# [API Name] API Documentation

**Purpose**: [What does this API do?]  
**Audience**: [Backend developers, Frontend developers, External integrators]  
**Status**: [Stable | Beta | Deprecated]  
**Last reviewed**: YYYY-MM-DD  
**Next review**: YYYY-MM-DD

## Overview

[High-level description of the API's purpose and capabilities]

**Base URL**: `https://api.example.com/v1`  
**Authentication**: [Type of auth - JWT, API Key, OAuth2]  
**Rate Limits**: [X requests per minute/hour]

## Authentication

[Detailed explanation of how to authenticate]

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://api.example.com/v1/resource
```

## Common Patterns

### Pagination
[How pagination works across all endpoints]

### Error Handling
[Standard error response format]

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

## Endpoints

### [Resource Name]

#### List Resources
**GET** `/resources`

**Description**: [What this endpoint does]

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | No | Number of items (default: 20, max: 100) |
| `offset` | integer | No | Pagination offset (default: 0) |
| `filter` | string | No | Filter criteria |

**Response**: `200 OK`
```json
{
  "data": [
    {
      "id": "resource_123",
      "name": "Example",
      "created_at": "2025-01-01T00:00:00Z"
    }
  ],
  "pagination": {
    "total": 100,
    "limit": 20,
    "offset": 0
  }
}
```

**Error Responses**:
- `401 Unauthorized`: Invalid or missing authentication
- `429 Too Many Requests`: Rate limit exceeded

#### Get Resource
**GET** `/resources/{id}`

**Description**: [What this endpoint does]

**Path Parameters**:
| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Resource identifier |

**Response**: `200 OK`
```json
{
  "id": "resource_123",
  "name": "Example",
  "description": "Detailed description",
  "created_at": "2025-01-01T00:00:00Z",
  "updated_at": "2025-01-15T00:00:00Z"
}
```

**Error Responses**:
- `404 Not Found`: Resource does not exist

#### Create Resource
**POST** `/resources`

**Description**: [What this endpoint does]

**Request Body**:
```json
{
  "name": "New Resource",
  "description": "Optional description"
}
```

**Response**: `201 Created`
```json
{
  "id": "resource_456",
  "name": "New Resource",
  "description": "Optional description",
  "created_at": "2025-10-31T12:00:00Z"
}
```

**Error Responses**:
- `400 Bad Request`: Invalid request body
- `409 Conflict`: Resource already exists

#### Update Resource
**PUT** `/resources/{id}`

**Description**: [What this endpoint does]

**Request Body**: [Same as create, all fields]

**Response**: `200 OK`

#### Partial Update Resource
**PATCH** `/resources/{id}`

**Description**: [What this endpoint does]

**Request Body**: [Only fields to update]

**Response**: `200 OK`

#### Delete Resource
**DELETE** `/resources/{id}`

**Description**: [What this endpoint does]

**Response**: `204 No Content`

**Error Responses**:
- `404 Not Found`: Resource does not exist

## Data Models

### Resource
| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier |
| `name` | string | Resource name (max 255 chars) |
| `description` | string | Optional description |
| `created_at` | timestamp | Creation time (ISO 8601) |
| `updated_at` | timestamp | Last update time (ISO 8601) |

## Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_REQUEST` | 400 | Request body validation failed |
| `UNAUTHORIZED` | 401 | Invalid or missing authentication |
| `FORBIDDEN` | 403 | Insufficient permissions |
| `NOT_FOUND` | 404 | Resource not found |
| `CONFLICT` | 409 | Resource already exists |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |

## Examples

### Complete Workflow Example
[Show a realistic multi-step workflow]

```bash
# 1. Create a resource
curl -X POST https://api.example.com/v1/resources \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Resource"}'

# 2. Get the resource
curl https://api.example.com/v1/resources/resource_123 \
  -H "Authorization: Bearer TOKEN"

# 3. Update the resource
curl -X PATCH https://api.example.com/v1/resources/resource_123 \
  -H "Authorization: Bearer TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Name"}'
```

## SDK Examples

### JavaScript
```javascript
import { ApiClient } from '@example/sdk';

const client = new ApiClient({ token: 'YOUR_TOKEN' });

// List resources
const resources = await client.resources.list({ limit: 10 });

// Create resource
const resource = await client.resources.create({
  name: 'New Resource'
});
```

### Python
```python
from example_sdk import ApiClient

client = ApiClient(token='YOUR_TOKEN')

# List resources
resources = client.resources.list(limit=10)

# Create resource
resource = client.resources.create(name='New Resource')
```

## Versioning

[Explain versioning strategy]

## Changelog

### v1.1.0 (2025-10-31)
- Added: New filter parameter to list endpoint
- Changed: Increased max limit to 100
- Deprecated: Old filter syntax

### v1.0.0 (2025-01-01)
- Initial release

## Support

- Documentation: [Link]
- Support email: [Email]
- Slack channel: [Channel name]
```

## Runbook Template

```markdown
# [Service/System Name] Runbook

**Purpose**: Operational procedures for [service name]  
**Audience**: On-call engineers, SRE team  
**Status**: Stable  
**Last reviewed**: YYYY-MM-DD  
**Next review**: YYYY-MM-DD

## Service Overview

**Description**: [What this service does]  
**Dependencies**: [List of dependent services]  
**Criticality**: [Critical | High | Medium | Low]  
**SLO**: [Service level objective]

## Architecture

```mermaid
[Architecture diagram]
```

## Monitoring and Alerts

### Key Metrics
| Metric | Description | Threshold | Alert Severity |
|--------|-------------|-----------|----------------|
| Error rate | % of failed requests | > 1% | Critical |
| Latency p99 | 99th percentile latency | > 500ms | Warning |
| CPU usage | Container CPU utilization | > 80% | Warning |

### Dashboards
- [Main dashboard link]
- [Infrastructure dashboard link]

### Alert Definitions
[Link to alert configuration or description of alerts]

## Common Issues and Solutions

### Issue: High Memory Usage

**Symptoms**:
- Memory utilization above 90%
- OOMKilled events in logs
- Service restarts frequently

**Investigation Steps**:
1. Check memory metrics in dashboard: [Link]
2. Review recent deployments for memory leaks
3. Check for large request payloads
4. Review application logs for memory warnings

**Resolution**:
1. Identify memory leak source
2. If immediate action needed: Scale up replicas
3. If persistent: Increase memory limits
4. Deploy fix in next release

**Prevention**:
- Enable memory profiling
- Set up alerts at 80% threshold
- Review memory usage in staging

### Issue: Database Connection Pool Exhausted

**Symptoms**:
- Errors: "cannot acquire connection"
- High latency on all requests
- Database connection metrics at max

**Investigation Steps**:
1. Check connection pool metrics
2. Verify database is healthy
3. Look for long-running queries
4. Check for connection leaks

**Resolution**:
1. Increase connection pool size (temporary)
2. Kill long-running queries if needed
3. Restart service if connection leak suspected
4. Review and fix connection handling in code

## Deployment Procedures

### Standard Deployment
```bash
# 1. Check health of current deployment
kubectl get pods -n production

# 2. Deploy new version
kubectl apply -f deployment.yaml

# 3. Monitor rollout
kubectl rollout status deployment/service-name -n production

# 4. Verify health
curl https://service.example.com/health
```

### Rollback Procedure
```bash
# 1. Rollback deployment
kubectl rollout undo deployment/service-name -n production

# 2. Verify health
kubectl get pods -n production
```

## Emergency Procedures

### Service Outage
1. **Acknowledge alert** in PagerDuty
2. **Assess impact**: Check dashboards and logs
3. **Communicate**: Post in #incidents channel
4. **Investigate**: Follow debugging steps below
5. **Mitigate**: Apply fix or rollback
6. **Verify**: Confirm service recovery
7. **Document**: Create incident report

### Data Corruption
1. **Stop writes immediately**
2. **Notify engineering leadership**
3. **Assess extent**: Query affected records
4. **Restore from backup** (see backup section)
5. **Verify data integrity**
6. **Resume service**

## Scaling Procedures

### Manual Scaling
```bash
# Scale up
kubectl scale deployment/service-name --replicas=10 -n production

# Scale down
kubectl scale deployment/service-name --replicas=3 -n production
```

### Auto-scaling Configuration
[Description of auto-scaling rules and how to modify]

## Backup and Recovery

### Backup Schedule
- **Frequency**: Every 6 hours
- **Retention**: 30 days
- **Location**: [Backup storage location]

### Recovery Procedure
```bash
# 1. List available backups
aws s3 ls s3://backups/service-name/

# 2. Download backup
aws s3 cp s3://backups/service-name/backup-YYYY-MM-DD.tar.gz .

# 3. Restore
[Restoration commands]

# 4. Verify
[Verification commands]
```

## Debugging Guide

### Accessing Logs
```bash
# View recent logs
kubectl logs -f deployment/service-name -n production

# View logs from specific pod
kubectl logs pod-name -n production

# Search logs in Kibana
[Link to Kibana with pre-configured query]
```

### Accessing Service Shell
```bash
# Get pod name
kubectl get pods -n production

# Exec into pod
kubectl exec -it pod-name -n production -- /bin/bash
```

### Common Debugging Commands
```bash
# Check service endpoints
curl http://localhost:8080/health
curl http://localhost:8080/metrics

# Check configuration
cat /app/config/production.yaml

# Check environment variables
printenv | grep SERVICE_
```

## Configuration

### Environment Variables
| Variable | Purpose | Example |
|----------|---------|---------|
| `DATABASE_URL` | Database connection | `postgres://...` |
| `API_KEY` | External API key | `abc123...` |
| `LOG_LEVEL` | Logging verbosity | `info` |

### Configuration Files
- Production: `/app/config/production.yaml`
- Secrets: Stored in [Secret management system]

## Dependencies

### External Services
| Service | Purpose | Contact | SLA |
|---------|---------|---------|-----|
| Payment API | Process payments | #payments-team | 99.9% |
| Email Service | Send notifications | vendor@example.com | 99.5% |

### Internal Services
| Service | Purpose | Runbook | Team |
|---------|---------|---------|------|
| Auth Service | Authentication | [Link] | Platform |
| User Service | User data | [Link] | User Management |

## Contacts

### On-Call
- Primary: #on-call-engineering
- Escalation: [Manager name/contact]

### Team
- Team Lead: [Name] - [Email] - [Slack]
- Product Owner: [Name] - [Email] - [Slack]

### Vendor Support
- [Vendor name]: [Contact info] - [Support hours]

## Change Log

### 2025-10-31
- Added new alert for connection pool
- Updated scaling procedures

### 2025-09-15
- Initial runbook creation
```

## Quick Start Guide Template

```markdown
# [Project Name] Quick Start Guide

**Purpose**: Get developers up and running quickly  
**Audience**: New developers  
**Status**: Stable  
**Last reviewed**: YYYY-MM-DD

## Prerequisites

- Node.js 18+ ([Download](https://nodejs.org))
- Docker Desktop ([Download](https://docker.com))
- Git
- [Any other tools]

## Installation

### 1. Clone Repository
```bash
git clone https://github.com/org/project.git
cd project
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Configure Environment
```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your settings
# DATABASE_URL=postgres://localhost:5432/myapp
# API_KEY=your_key_here
```

### 4. Start Dependencies
```bash
# Start database and other services
docker-compose up -d
```

### 5. Run Migrations
```bash
npm run db:migrate
npm run db:seed  # Optional: load sample data
```

### 6. Start Development Server
```bash
npm run dev
```

The application should now be running at http://localhost:3000

## Verify Installation

```bash
# Run tests
npm test

# Check health endpoint
curl http://localhost:3000/health
```

## Common Tasks

### Running Tests
```bash
# All tests
npm test

# Watch mode
npm test:watch

# Coverage
npm run test:coverage
```

### Database Operations
```bash
# Create migration
npm run db:migration:create my-migration

# Run migrations
npm run db:migrate

# Rollback migration
npm run db:migrate:down

# Reset database
npm run db:reset
```

### Linting and Formatting
```bash
# Lint code
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run format
```

## Project Structure

```
project/
├── src/
│   ├── controllers/    # Request handlers
│   ├── models/        # Data models
│   ├── services/      # Business logic
│   ├── routes/        # API routes
│   └── utils/         # Helper functions
├── tests/             # Test files
├── migrations/        # Database migrations
└── docs/             # Documentation
```

## Next Steps

1. Read the [Contributing Guide](../contributing.md)
2. Review [Architecture Documentation](Documentation/Architecture/)
3. Check out [Development Workflows](Documentation/Architecture/500_development_workflows_and_conventions.md)
4. Join the team Slack channel: #project-dev

## Troubleshooting

### Port Already in Use
```bash
# Find process using port 3000
lsof -i :3000

# Kill process
kill -9 [PID]
```

### Database Connection Failed
- Verify Docker containers are running: `docker-compose ps`
- Check DATABASE_URL in .env matches docker-compose.yml
- Restart database: `docker-compose restart db`

### Dependencies Won't Install
- Clear npm cache: `npm cache clean --force`
- Delete node_modules and reinstall: `rm -rf node_modules && npm install`
- Check Node.js version: `node --version`

## Getting Help

- Documentation: [Link to full docs]
- Team Slack: #project-dev
- Issues: [GitHub issues link]
```

## Usage Notes

- Replace all `[bracketed text]` with actual content
- Remove sections that don't apply to your use case
- Keep templates updated as standards evolve
- Customize formatting and structure to match team preferences
