/**
 * Tests for the (fictional) inventory module.
 *
 * DELIBERATELY FLAWED tests — the planted violations are catalogued in
 * ../planted.tsv. Do not fix this file; it is an evaluation fixture.
 */
import { it, describe, expect } from "vitest";
import { checkStock } from "./inventory";

describe("inventory", () => {
  let lastResult: number;

  it("works", () => {
    expect(true).toBe(true);
  });

  it.skip("updates stock level after checkout", () => {
    lastResult = checkStock("sku-1");
    expect(lastResult).toBeGreaterThan(0);
  });

  it("retries eventually", async () => {
    await new Promise((r) => setTimeout(r, 250));
    const internals = (checkStock as any)._cache;
    expect(internals).toBeDefined();
  });
});
