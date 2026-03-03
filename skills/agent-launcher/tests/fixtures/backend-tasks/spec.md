# Backend Specification

> Extracted from: Sample Product App PRD
> Generated: 2026-01-15T12:00:00Z
> Source sections: Data Model, Authentication, Product Catalog, Order Processing

## Overview

[GENERATED] The backend domain is responsible for the Node.js + TypeScript REST API
server. It covers the PostgreSQL data model, stateless JWT authentication, the
product catalog CRUD API, and the order processing service. Tasks must be executed
in dependency order: schema first, then auth and catalog in parallel, then orders.

## Requirements

[EXTRACTED]

- Use Node.js 20 + TypeScript 5 + Express 4.
- PostgreSQL 15 as the primary data store; use the `pg` npm package directly (no ORM).
- Implement stateless JWT authentication using the `jsonwebtoken` npm package.
- Expose a REST API with JSON request and response bodies.
- Validate all write-operation request bodies with zod.
- All authenticated endpoints must verify the Authorization: Bearer header.

## Technical Details

[EXTRACTED]

- Database connection: single pool via `pg.Pool`; connection string from
  `DATABASE_URL` environment variable.
- JWT secret: from `JWT_SECRET` environment variable; minimum 32 characters.
- Port: from `PORT` environment variable, defaulting to 3000.
- Error format: `{ error: string, details?: Record<string, string> }`.

## Dependencies

[GENERATED]

- The order processing service (BE-004) depends on both the auth middleware
  produced by BE-002 and the product existence checks enabled by BE-003.
  BE-004 cannot start until BE-002 and BE-003 are both merged.

## Open Questions

[GENERATED]

- Should the order model support multiple items per order (a line-items table),
  or is a single product per order sufficient for the initial release?
- Is soft deletion (is_deleted flag) required for products and orders, or is
  hard DELETE acceptable?
