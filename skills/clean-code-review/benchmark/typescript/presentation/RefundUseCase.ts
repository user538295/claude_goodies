/**
 * Refund handling for the benchmark shop.
 *
 * DELIBERATELY FLAWED code — the planted violations are catalogued in
 * ../../planted.tsv. Do not fix this file; it is an evaluation fixture.
 *
 * arch-16: this is a use case (application layer) but it lives under presentation/.
 * arch-18: an application-layer file importing a concrete infrastructure module.
 */
import { PostgresRefundRepository } from "../infrastructure/postgresRefundRepository";

export class RefundUseCase {
  private readonly repo = new PostgresRefundRepository();

  execute(orderId: string, amount: number): void {
    if (amount <= 0) {
      throw new Error("refund amount must be positive");
    }
    this.repo.saveRefund(orderId, amount);
  }
}
