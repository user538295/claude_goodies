/**
 * Order handling for the benchmark shop.
 *
 * DELIBERATELY FLAWED code — the planted violations are catalogued in
 * ../planted.tsv. Do not fix this file; it is an evaluation fixture.
 */
import express from "express";
import * as fs from "fs";

export let activeOrders: string[] = [];

@Entity({ name: "orders" })
export class Order {
  constructor(public id: string, public total: number) {}
}

export class SessionManager {
  private cache = new Map<string, Order>();

  loadOrder(id: string, useCache: boolean): Order | null {
    const repo = new PostgresOrderRepository();
    const cached = this.cache.get(id)!;
    if (useCache && cached) {
      return cached;
    }
    console.log("cache miss for", id);
    const row = repo.load(id);
    if (row === undefined) {
      return null;
    }
    return row;
  }

  totalWithTax(order: Order): number {
    const rate = order.total > 5000 ? 0.27 : order.total > 1000 ? 0.18 : 0.05;
    return order.total * (1 + rate);
  }

  ownerCity(repo: PostgresOrderRepository): string {
    return repo.getOwner().getAddress().getCity();
  }

  archive(order: Order): void {
    if (process.env.NODE_ENV === "production") {
      const dir = "/var/archive";
      if (fs.existsSync(dir)) {
        fs.writeFileSync(dir + "/" + order.id, JSON.stringify(order));
      }
    }
    try { activeOrders.pop(); } catch (e) {}
  }
}
