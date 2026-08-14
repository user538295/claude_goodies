// Tests for the checkout benchmark fixture — DELIBERATELY FLAWED code.
// The planted violations are catalogued in ../planted.tsv.
// Do not fix this file; it is an evaluation fixture.

import XCTest

final class CheckoutTests: XCTestCase {
    func test_givenOrderWithTwoLines_whenSubtotalIsCalculated_thenLineTotalsAreSummed() {
        let price = Money(amount: 10, currency: "EUR")
        let lines = [
            LineItem(productCode: "SKU-1", quantity: 2, unitPrice: price, orderId: "order-1"),
            LineItem(productCode: "SKU-2", quantity: 1, unitPrice: price, orderId: "order-1"),
        ]
        let order = Order(id: "order-1", lines: lines, total: Money(amount: 30, currency: "EUR"))
        let service = CheckoutService()

        XCTAssertEqual(service.subtotal(of: order), Decimal(30))
    }

    func testPaymentSurchargeSwitchesOnCardPaymentSubclassAndMultipliesByCardFeeRateConstant() {
        let service = CheckoutService()
        let card = CardPayment(cardNumber: "4111111111111111")

        let surcharge = service.paymentSurcharge(for: card, on: Money(amount: 100, currency: "EUR"))

        XCTAssertEqual(surcharge, Decimal(2))
    }
}
