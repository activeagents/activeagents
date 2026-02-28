# Investor Portal Feature

## Overview

The Investor Portal provides a comprehensive solution for managing friends & family and pre-seed investors, with integration capabilities for Stripe Atlas and Pulley.

## Branch

`feature/investor-portal`

## Features

### Admin Dashboard (for Founders)

- **Investor Management** (`/admin/investors`)
  - Add, edit, and remove investors
  - Send magic link portal invites
  - Track investor activity and document access
  - Support for individual, entity, and trust investor types

- **Document Management** (`/admin/investor_documents`)
  - Upload and manage pitch decks, PPMs, SAFEs, etc.
  - Control access per-document or make public to all investors
  - Track views and downloads with analytics
  - Google Cloud Storage backend

- **SAFE Agreement Tracking** (`/admin/safe_agreements`)
  - Create and track SAFE agreements
  - Link to Stripe Atlas SAFEs
  - Status workflow: Draft → Sent → Signed → Converted
  - Email notifications on status changes

- **Cap Table** (`/admin/cap_table`)
  - View ownership breakdown by stakeholder type
  - Track equity holders and pending SAFEs
  - OCF-compatible data model for Pulley sync

### Investor Portal (for Investors)

- **Magic Link Authentication**
  - No passwords - investors receive email with secure access link
  - 30-day token expiration with regeneration capability

- **Dashboard** (`/investor/dashboard`)
  - Investment summary (total invested, ownership %)
  - SAFE agreement status and details
  - Quick access to documents

- **Documents** (`/investor/documents`)
  - View and download shared documents
  - Access logging for compliance

## Database Schema

### New Tables

1. `investors` - Investor contact info, portal access tokens, Pulley sync
2. `safe_agreements` - SAFE terms, status workflow, Atlas integration
3. `investor_documents` - Document metadata, access control
4. `document_access_grants` - Per-investor document access
5. `document_access_logs` - View/download tracking
6. `cap_table_entries` - OCF-compatible ownership records

## Email Notifications

- `InvestorMailer#portal_invite` - Magic link access
- `InvestorMailer#document_shared` - New document notification
- `InvestorMailer#safe_status_update` - SAFE status changes
- `InvestorMailer#portal_access_expiring` - Access expiry reminder

## Configuration Required

### Google Cloud Storage

Add to credentials or environment:

```yaml
gcs:
  project_id: your-project-id
  credentials: path/to/credentials.json
  bucket: your-bucket-name
```

Or set environment variables:
- `GCS_PROJECT_ID`
- `GCS_CREDENTIALS`
- `GCS_BUCKET`

### Email Delivery

Configure Action Mailer for production email delivery (SendGrid, Postmark, etc.)

## Routes

### Investor Portal (public)
- `GET /investor/login` - Login page
- `GET /investor/auth/:token` - Magic link authentication
- `GET /investor/dashboard` - Investor dashboard
- `GET /investor/documents` - Document list
- `GET /investor/documents/:id` - View document
- `GET /investor/documents/:id/download` - Download document

### Admin Dashboard (authenticated)
- `/admin/investors` - Investor CRUD
- `/admin/safe_agreements` - SAFE CRUD
- `/admin/investor_documents` - Document CRUD
- `/admin/cap_table` - Cap table view

### API Endpoints
- `/api/admin/investors`
- `/api/admin/safe_agreements`
- `/api/admin/investor_documents`
- `/api/admin/cap_table`

## Pulley Integration Strategy

### Phase 1 (Current)
- Standalone with Pulley-compatible data model
- All models include `pulley_id` for future sync
- OCF-compatible field naming
- `metadata` JSONB for extensibility

### Phase 2 (Future)
- Pulley API sync via background jobs
- OCF export endpoint
- Webhook receiver for Pulley updates

## Related Files

### Models
- `app/models/investor.rb`
- `app/models/safe_agreement.rb`
- `app/models/investor_document.rb`
- `app/models/document_access_grant.rb`
- `app/models/document_access_log.rb`
- `app/models/cap_table_entry.rb`

### Controllers
- `app/controllers/investor_portal_controller.rb`
- `app/controllers/admin/investors_controller.rb`
- `app/controllers/admin/safe_agreements_controller.rb`
- `app/controllers/admin/investor_documents_controller.rb`
- `app/controllers/admin/cap_table_controller.rb`

### React Pages
- `app/javascript/pages/InvestorPortal/`
- `app/javascript/pages/Admin/Investors/`
- `app/javascript/pages/Admin/Documents/`
- `app/javascript/pages/Admin/SafeAgreements/`
- `app/javascript/pages/Admin/CapTable/`
