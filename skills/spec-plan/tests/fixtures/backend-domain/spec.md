# Backend Specification

> Extracted from: E-Commerce Platform PRD
> Generated: 2026-01-15T10:00:00Z
> Source sections: API Design, Database Schema, Authentication, Order Processing

## Overview
[GENERATED] The backend domain covers RESTful API services, database management, authentication, and order processing for the e-commerce platform. Built with Node.js and PostgreSQL.

## Requirements

### Database Schema
[EXTRACTED] The platform requires a PostgreSQL database with tables for users, products, categories, orders, order_items, and cart_items. All tables must have created_at and updated_at timestamps. Products must support multiple images and variant options (size, color).

### User Authentication
[EXTRACTED] Users must be able to register with email/password and login to receive a JWT token. Tokens expire after 24 hours. Password reset via email must be supported. All passwords stored as bcrypt hashes.

### Product API
[EXTRACTED] RESTful API endpoints for products: GET /api/v1/products (list with pagination, filtering, sorting), GET /api/v1/products/:id (detail), GET /api/v1/categories (list categories). Response format is JSON with consistent error handling.

### Order Processing
[EXTRACTED] POST /api/v1/orders creates a new order from the current cart. The endpoint must validate stock availability, calculate totals, process payment via Stripe, and send confirmation email. Orders have statuses: pending, paid, shipped, delivered, cancelled.

## Technical Details
[EXTRACTED] Backend uses Express.js with TypeScript, Prisma ORM for database access, and Jest for testing. API follows RESTful conventions with JSON responses.

## Dependencies
[GENERATED] Depends on infrastructure for PostgreSQL database provisioning. Frontend consumes all API endpoints.
