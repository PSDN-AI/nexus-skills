# DeFi Yield Aggregator

**Author**: Protocol Team
**Date**: 2025-06-01
**Version**: 1.0

## 1. Overview

Build a DeFi yield aggregator that sources the best APY across lending protocols on Ethereum L2 rollups. Users connect their wallet, deposit ERC-20 tokens, and the vault auto-compounds rewards.

## 2. Smart Contracts

- Solidity vault contract using OpenZeppelin upgradeable proxy pattern
- ERC-4337 account abstraction for gasless deposits via paymaster
- Chainlink oracle integration for on-chain price feeds
- Reentrancy guard on all external calls
- Timelock governance for parameter changes

## 3. Frontend dApp

- React dashboard with wagmi and viem for wallet connection
- MetaMask and WalletConnect support
- Display TVL, APY, and user position in real-time
- Responsive layout with Tailwind CSS

## 4. Indexing and Data

- Subgraph on The Graph for indexing vault events
- Track deposits, withdrawals, and harvest transactions
- Analytics pipeline for protocol-level KPI dashboards

## 5. Infrastructure

- RPC node provider via Alchemy for Optimism and Base
- IPFS for storing governance proposal metadata
- Terraform for deploying monitoring infrastructure on AWS

## 6. Security

- Smart contract audit checklist: reentrancy, flash loan attacks, MEV exposure
- Rate limiting on RPC endpoints
- SOC2 compliance for the off-chain API layer
